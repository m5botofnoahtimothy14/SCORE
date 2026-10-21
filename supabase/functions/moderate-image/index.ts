// ============================================================
// Edge Function: moderate-image
// Server-side image safety classifier.
//
// Primary: OpenAI omni-moderation-latest (accepts image input).
// Fallback: heuristic file/mime checks + size limits when no key.
//
// The scoring engine (same as moderate-message) decides the verdict
// and persists full provenance to moderation_results for the F1/ML
// dashboard. Fail closed: provider error => quarantined, never approved.
// ============================================================
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { encode as base64Encode } from "https://deno.land/std@0.177.0/encoding/base64.ts";
import {
  applyPolicy,
  explainDecision,
  toImageVerdict,
} from "../_shared/moderation_policy.ts";
import { detectSafeSearch } from "./vision.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const INTERNAL_WEBHOOK_SECRET = Deno.env.get("INTERNAL_WEBHOOK_SECRET")!;

const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");

// Google Cloud Vision SafeSearch. The API key is preferred; when it is
// absent the project's service account is used with the cloud-platform scope.
const VISION_API_KEY = Deno.env.get("GOOGLE_CLOUD_VISION_API_KEY");
const GOOGLE_CLIENT_EMAIL = Deno.env.get("FCM_CLIENT_EMAIL");
const GOOGLE_PRIVATE_KEY = Deno.env.get("FCM_PRIVATE_KEY");

const MAX_IMAGE_BYTES = 10 * 1024 * 1024; // 10 MB

type CategoryScores = Record<string, number>;

// The policy engine now lives in the shared module (see the import above).
// For an image the decision is driven by the nudity observation, and it
// fails closed when the classifier could not answer.

serve(async (req: Request) => {  const secret = req.headers.get("x-webhook-secret");
  if (secret !== INTERNAL_WEBHOOK_SECRET) {
    return new Response("Unauthorized", { status: 401 });
  }

  try {
    const body = await req.json();
    const { attachment_id, school_id } = body;

    if (!attachment_id || !school_id) {
      return new Response("Missing fields", { status: 400 });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    const { data: attachment } = await supabase
      .from("attachments")
      .select("*")
      .eq("id", attachment_id)
      .maybeSingle();

    if (!attachment) {
      return new Response("Attachment not found", { status: 404 });
    }

    let categories: CategoryScores = {};
    let provider = "none";
    let providerError: string | undefined;
    let nudityScore: number | null = null;
    let visionError: string | undefined;

    if (attachment.size_bytes && attachment.size_bytes > MAX_IMAGE_BYTES) {
      provider = "policy";
      providerError = "file_too_large";
    } else {
      // The image is fetched once and handed to whichever classifier runs.
      const bytes = await downloadImage(supabase, attachment.storage_path);

      if (!bytes) {
        provider = "none";
        providerError = "image could not be read — held for review";
      } else {
        // 1. Google Cloud Vision SafeSearch — the primary image classifier.
        const vision = await classifyWithVision(bytes);
        visionError = vision.error;
        if (vision.categories && Object.keys(vision.categories).length > 0) {
          categories = vision.categories;
          provider = vision.provider;
          // Vision reports a 0..1 probability per category; the policy works
          // in the 1..5 nudity bands, so the worst category is mapped onto it.
          nudityScore = nudityBandFromCategories(vision.categories);
        } else {
          // 2. OpenAI omni-moderation — the fallback.
          if (!OPENAI_API_KEY) {
            provider = "none";
            providerError = vision.error
              ? `image safety unavailable (${vision.error}) — held for review`
              : "OPENAI_API_KEY not configured — held for review";
          } else {
            const result = await classifyWithOpenAI(bytes, attachment.mime_type);
            if (result.error) {
              provider = "openai";
              // Keep both failures: the Vision error is usually the more
              // actionable one (a revoked key, an API not enabled).
              providerError = vision.error
                ? `${result.error} | vision: ${vision.error}`
                : result.error;
            } else {
              categories = result.categories ?? {};
              provider = "openai_omni";
              nudityScore = nudityBandFromCategories(categories);
            }
          }
        }
      }
    }

    // Determine the audience tier of the uploader (sender of the parent
    // message) so students are held to stricter image thresholds.
    let audience = "unknown";
    if (attachment.message_id) {
      const { data: msg } = await supabase
        .from("messages")
        .select("sender_id")
        .eq("id", attachment.message_id)
        .maybeSingle();
      if (msg?.sender_id) {
        const { data: membership } = await supabase
          .from("school_memberships")
          .select("role")
          .eq("user_id", msg.sender_id)
          .eq("is_active", true)
          .order("joined_at", { ascending: true })
          .limit(1)
          .maybeSingle();
        audience = (membership?.role as string) ?? "unknown";
      }
    }

    // The shared policy owns the decision. An image with no usable
    // observation fails closed and is quarantined for a human.
    const decision = applyPolicy({
      categories,
      text: "",
      context: {
        media: "image",
        audience: "unknown",
        senderRole: audience,
        provider,
        providerError: providerError ?? null,
        nudityScore,
      },
    });

    const verdict = toImageVerdict(decision);
    const attachmentStatus = verdict === "rejected"
      ? "rejected"
      : verdict === "approved"
        ? "approved"
        : "quarantined";

    const scanResult = {
      provider,
      categories,
      policy_version: "v1",
      action: decision.action,
      policy_score: decision.score,
      matched_rules: decision.matchedRules,
      reasons: decision.reasons,
      explanation: explainDecision(decision),
      signals: decision.signals,
      nudity_band: nudityScore,
      // The Vision failure, when there was one: it is the difference
      // between "the image is safe" and "the classifier was unavailable".
      vision_error: visionError ?? null,
    };

    const { data: modResult, error: modErr } = await supabase
      .from("moderation_results")
      .insert({
        school_id,
        attachment_id,
        provider,
        verdict,
        // Confidence = how sure we are of the verdict. For an approval that
        // is the inverse of the risk score; for a hold/block it is the score.
        confidence: verdict === "approved" ? 1 - decision.score : decision.score,
        categories,
        provider_error: providerError,
        raw_response: scanResult,
        processed_at: new Date().toISOString(),
      })
      .select("id")
      .single();
    if (modErr) console.error("moderation_results insert failed:", modErr.message);

    const { error: attachErr } = await supabase
      .from("attachments")
      .update({
        status: attachmentStatus,
        scan_result: scanResult,
        scanned_at: new Date().toISOString(),
      })
      .eq("id", attachment_id);
    if (attachErr) console.error("attachment status update failed:", attachErr.message);

    if (attachmentStatus !== "approved") {
      const { error: caseErr } = await supabase.from("moderation_review_cases").insert({
        school_id,
        moderation_result_id: modResult?.id ?? null,
        status: "pending",
        reason_code: verdict,
      });
      if (caseErr) console.error("moderation_review_cases insert failed:", caseErr.message);
    }

    if (attachmentStatus === "approved" && attachment.message_id) {
      await supabase.from("messages")
        .update({ status: "approved" })
        .eq("id", attachment.message_id)
        .eq("status", "pending_moderation");
    }

    return new Response(
      JSON.stringify({ verdict, attachment_status: attachmentStatus, provider, score: decision.score }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error("moderate-image error:", err);
    return new Response("Server error", { status: 500 });
  }
});

/**
 * Maps a classifier's category probabilities onto the 1..5 nudity band the
 * policy works in:
 *   1-2 safe, 3 borderline, 4-5 explicit.
 *
 * The band is driven by the worst sexual signal, so a single strong
 * category is enough to move the image out of the "safe" band.
 */
function nudityBandFromCategories(categories: CategoryScores): number {
  const sexual = Number(categories.sexual ?? categories.sexual_minors ?? 0);
  const minors = Number(categories.sexual_minors ?? 0);
  const worst = Math.max(sexual, minors);
  if (worst >= 0.9) return 5;
  if (worst >= 0.75) return 4;
  if (worst >= 0.45) return 3;
  if (worst >= 0.2) return 2;
  return 1;
}

async function downloadImage(
  supabase: ReturnType<typeof createClient>,
  storagePath: string,
): Promise<Uint8Array | null> {
  try {
    const { data: blob, error } = await supabase.storage
      .from("attachments")
      .download(storagePath);
    if (error || !blob) return null;
    return new Uint8Array(await blob.arrayBuffer());
  } catch {
    return null;
  }
}

async function classifyWithVision(
  bytes: Uint8Array,
): Promise<{ categories: CategoryScores; provider: string; error?: string }> {
  if (!VISION_API_KEY && !(GOOGLE_CLIENT_EMAIL && GOOGLE_PRIVATE_KEY)) {
    return { categories: {}, provider: "none", error: "no Vision credentials configured" };
  }
  const result = await detectSafeSearch(bytes, {
    apiKey: VISION_API_KEY,
    clientEmail: GOOGLE_CLIENT_EMAIL,
    privateKey: GOOGLE_PRIVATE_KEY,
  });
  return {
    categories: result.categories as CategoryScores,
    provider: result.provider,
    error: result.error,
  };
}

async function classifyWithOpenAI(
  bytes: Uint8Array,
  mimeType: string,
): Promise<CategoryScores & { error?: string }> {
  try {
    const dataUrl = `data:${mimeType || "image/jpeg"};base64,${base64Encode(bytes)}`;

    const res = await fetch("https://api.openai.com/v1/moderations", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${OPENAI_API_KEY}`,
      },
      body: JSON.stringify({
        model: "omni-moderation-latest",
        input: [{ type: "image_url", image_url: { url: dataUrl } }],
      }),
    });

    if (!res.ok) {
      return { categories: {}, error: `OpenAI HTTP ${res.status}: ${(await res.text()).slice(0, 200)}` };
    }

    const data = await res.json();
    const result = data.results?.[0];
    if (!result) {
      return { categories: {}, error: "no moderation result" };
    }

    // The RAW vendor vector is kept; the policy and the nudity band both
    // read the vendor's own category names.
    return { categories: (result.category_scores ?? {}) as CategoryScores };
  } catch (e) {
    return { categories: {}, error: String((e as Error)?.message ?? e) };
  }
}
