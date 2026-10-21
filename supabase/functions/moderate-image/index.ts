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

interface PolicyDecision {
  action: "approve" | "hold" | "block";
  score: number;
  providerScore: number;
  reasons: string[];
  matchedRules: string[];
  provider: string;
  audience: string;
  providerError?: string;
}

/** Map a policy action onto the `moderation_verdict` enum. */
function verdictFor(action: PolicyDecision["action"]): "approved" | "held" | "blocked" {
  switch (action) {
    case "approve": return "approved";
    case "block": return "blocked";
    default: return "held";
  }
}

/** Map a policy action onto the `attachments.status` enum. */
function attachmentStatusFor(action: PolicyDecision["action"]): "approved" | "quarantined" | "rejected" {
  switch (action) {
    case "approve": return "approved";
    case "block": return "rejected";
    default: return "quarantined";
  }
}

/**
 * Normalise OpenAI moderation category keys to the names the policy engine
 * uses ("sexual/minors" -> "sexual_minors", "self-harm" -> "self_harm").
 */
function normaliseCategories(raw: Record<string, unknown>): CategoryScores {
  const out: CategoryScores = {};
  for (const [key, value] of Object.entries(raw ?? {})) {
    const score = Number(value);
    if (!Number.isFinite(score)) continue;
    out[key.replace(/\//g, "_").replace(/-/g, "_").toLowerCase()] = score;
  }
  if (out.sexual_minors === undefined && out.sexual_minor !== undefined) {
    out.sexual_minors = out.sexual_minor;
  }
  return out;
}

function getCategory(categories: CategoryScores, name: string): number {
  return Number(categories[name]) || 0;
}

function decide(
  categories: CategoryScores,
  audience: string,
  providerError?: string,
): PolicyDecision {
  const reasons: string[] = [];
  const matchedRules: string[] = [];

  const sexual = getCategory(categories, "sexual");
  const sexualMinors = getCategory(categories, "sexual_minors");
  const violence = getCategory(categories, "violence");

  if (providerError) {
    return {
      action: "hold",
      score: 1,
      providerScore: 0,
      reasons: ["provider_error"],
      matchedRules: ["provider_error"],
      provider: "provider_error",
      audience,
    };
  }

  if (sexualMinors >= 0.3 || violence >= 0.8) {
    matchedRules.push("critical_block");
    reasons.push("critical_image_signal");
    return {
      action: "block",
      score: 1,
      providerScore: Math.max(sexualMinors, violence),
      reasons: [...reasons, "critical_block"],
      matchedRules: [...matchedRules, "critical_block"],
      provider: "policy",
      audience,
    };
  }

  const isStudent = audience === "student";
  const isStaff = ["teacher", "head_teacher", "principal", "school_admin", "platform_owner"].includes(audience);

  if (isStudent) {
    if (sexual >= 0.3 || violence >= 0.6) {
      matchedRules.push("student_block");
      reasons.push("student_high_risk_image");
      return {
        action: "block",
        score: Math.max(sexual, violence),
        providerScore: Math.max(sexual, violence),
        reasons: [...reasons, "student_block"],
        matchedRules: [...matchedRules, "student_block"],
        provider: "policy",
        audience,
      };
    }
    if (sexual >= 0.15 || violence >= 0.3) {
      matchedRules.push("student_hold");
      reasons.push("student_moderate_risk_image");
      return {
        action: "hold",
        score: Math.max(sexual, violence),
        providerScore: Math.max(sexual, violence),
        reasons: [...reasons, "student_hold"],
        matchedRules: [...matchedRules, "student_hold"],
        provider: "policy",
        audience,
      };
    }
  }

  if (isStaff) {
    if (sexualMinors >= 0.5 || violence >= 0.7) {
      matchedRules.push("staff_block");
      reasons.push("staff_high_risk_image");
      return {
        action: "block",
        score: Math.max(sexualMinors, violence),
        providerScore: Math.max(sexualMinors, violence),
        reasons: [...reasons, "staff_block"],
        matchedRules: [...matchedRules, "staff_block"],
        provider: "policy",
        audience,
      };
    }
    if (sexual >= 0.5 || violence >= 0.7) {
      matchedRules.push("staff_hold");
      reasons.push("staff_moderate_risk_image");
      return {
        action: "hold",
        score: Math.max(sexual, violence),
        providerScore: Math.max(sexual, violence),
        reasons: [...reasons, "staff_hold"],
        matchedRules: [...matchedRules, "staff_hold"],
        provider: "policy",
        audience,
      };
    }
  }

  if (audience === "unknown") {
    const max = Math.max(sexual, sexualMinors, violence);
    if (max >= 0.4) {
      matchedRules.push("unknown_hold");
      reasons.push("unknown_audience_hold");
      return {
        action: "hold",
        score: max,
        providerScore: max,
        reasons: [...reasons, "unknown_hold"],
        matchedRules: [...matchedRules, "unknown_hold"],
        provider: "policy",
        audience,
      };
    }
  }

  return {
    action: "approve",
    score: Math.max(sexual, sexualMinors, violence),
    providerScore: Math.max(sexual, sexualMinors, violence),
    reasons: [],
    matchedRules: [],
    provider: "policy",
    audience,
  };
}

serve(async (req: Request) => {
  const secret = req.headers.get("x-webhook-secret");
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
    let decision: PolicyDecision | undefined;

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
        if (vision.categories && Object.keys(vision.categories).length > 0) {
          categories = vision.categories;
          provider = vision.provider;
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
              providerError = result.error;
            } else {
              categories = result.categories ?? {};
              provider = "openai_omni";
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

    decision = decide(categories, audience, providerError);

    const verdict = verdictFor(decision.action);

    const scanResult = {
      provider,
      categories,
      policy_version: "v1",
      action: decision.action,
      policy_score: decision.score,
      raw_max_score: decision.providerScore,
      matched_rules: decision.matchedRules,
      reasons: decision.reasons,
      explanation: decision.reasons.join("; "),
      signals: categories,
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

    const attachmentStatus = attachmentStatusFor(decision.action);

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

    return { categories: normaliseCategories(result.category_scores ?? {}) };
  } catch (e) {
    return { categories: {}, error: String((e as Error)?.message ?? e) };
  }
}
