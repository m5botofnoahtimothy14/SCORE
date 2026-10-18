// ============================================================
// Edge Function: moderate-image
// Server-side image safety classifier.
//
// Primary: OpenAI omni-moderation-latest (accepts image input), reusing the
//          same OPENAI_API_KEY as text moderation.
// Fallback: APILayer Nudity Detection (1–5 score, 5 = most likely nude),
//          used only when OpenAI is unavailable.
//
// The vendor is the SIGNAL SOURCE. The verdict is decided by the first-part
// policy in _shared/moderation_policy.ts, using the same threshold table and
// the same multi-signal rule as text. See docs/MODERATION.md.
//
// We fail closed: any provider error => quarantined, never approved.
// ============================================================
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { encode as base64Encode } from "https://deno.land/std@0.177.0/encoding/base64.ts";
import {
  applyPolicy,
  toImageVerdict,
  explainDecision,
  type PolicyDecision,
} from "../_shared/moderation_policy.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const INTERNAL_WEBHOOK_SECRET = Deno.env.get("INTERNAL_WEBHOOK_SECRET")!;

const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
const APILAYER_API_KEY = Deno.env.get("APILAYER_API_KEY");
const APILAYER_BASE = Deno.env.get("APILAYER_NUDITY_URL") ?? "https://api.apilayer.com/nudity_detection";

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

    let verdict: "approved" | "rejected" | "quarantined";
    let scanResult: Record<string, unknown> = {};
    let provider = "none";
    let decision: PolicyDecision | undefined;

    const classify = await classifyImage(supabase, attachment.storage_path, attachment.mime_type);

    if (classify.error) {
      // FAIL CLOSED: a provider failure is a quarantine, never an approval,
      // whatever score the failing provider reported on the way out.
      verdict = "quarantined";
      scanResult = { error: classify.error, provider: classify.provider };
      console.error("Image scan failed — quarantining:", attachment_id, classify.error);
    } else {
      provider = classify.provider;
      // The vendor's semantic categories are the signals; the nudity score
      // is a direct physical observation fed to the policy as well.
      const categoryScores = (classify.details?.category_scores as Record<string, number>) ?? {};
      decision = applyPolicy({
        categories: categoryScores,
        text: "",
        context: {
          media: "image",
          provider: classify.provider,
          providerError: null,
          nudityScore: classify.value,
          flagged: Boolean(classify.details?.flagged),
        },
      });
      verdict = toImageVerdict(decision);
      scanResult = {
        description: classify.description,
        score: classify.value,
        categories: classify.details,
        policy_version: decision.policyVersion,
        policy_action: decision.action,
        policy_reasons: decision.reasons,
        policy_rules: decision.matchedRules,
        policy_explanation: explainDecision(decision),
      };
      console.log(`image moderation ${attachment_id}: ${explainDecision(decision)}`);
    }

    const modVerdict = verdict === "approved" ? "approved" : verdict === "rejected" ? "blocked" : "held";

    await supabase.from("moderation_results").insert({
      school_id,
      attachment_id,
      provider,
      verdict: modVerdict,
      categories: scanResult,
      raw_response: decision
        ? {
          policy_version: decision.policyVersion,
          action: decision.action,
          policy_score: decision.score,
          raw_max_score: decision.rawMaxScore,
          matched_rules: decision.matchedRules,
          reasons: decision.reasons,
          explanation: explainDecision(decision),
          signals: decision.signals,
        }
        : { policy_version: "not_applied", reason: "provider failure — quarantined (fail-closed)" },
      processed_at: new Date().toISOString(),
    });

    const attachmentStatus = verdict === "approved" ? "approved" :
      verdict === "rejected" ? "rejected" : "quarantined";

    await supabase.from("attachments")
      .update({
        status: attachmentStatus,
        scan_result: scanResult,
        scanned_at: new Date().toISOString(),
      })
      .eq("id", attachment_id);

    if (attachmentStatus !== "approved") {
      await supabase.from("moderation_review_cases").insert({
        school_id,
        status: "pending",
        reason_code: verdict,
      });
    }

    if (attachmentStatus === "approved" && attachment.message_id) {
      await supabase.from("messages")
        .update({ status: "approved" })
        .eq("id", attachment.message_id)
        .eq("status", "pending_moderation");
    }

    return new Response(
      JSON.stringify({ verdict, attachment_status: attachmentStatus, provider }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error("moderate-image error:", err);
    return new Response("Server error", { status: 500 });
  }
});

type ClassifyResult = {
  value: number;
  description: string;
  details: Record<string, unknown>;
  provider: string;
  error?: string;
};

/// Classify an attachment: OpenAI first (if configured), APILayer fallback.
async function classifyImage(
  supabase: ReturnType<typeof createClient>,
  storagePath: string,
  mimeType: string,
): Promise<ClassifyResult> {
  const errors: string[] = [];

  if (OPENAI_API_KEY) {
    const openai = await classifyWithOpenAI(supabase, storagePath, mimeType);
    if (!openai.error) return openai;
    errors.push(`openai: ${openai.error}`);
  } else {
    errors.push("openai: not configured");
  }

  if (APILAYER_API_KEY) {
    const { data: signed } = await supabase.storage
      .from("attachments")
      .createSignedUrl(storagePath, 120);
    if (signed?.signedUrl) {
      const apilayer = await classifyWithApilayer(signed.signedUrl);
      if (!apilayer.error) return apilayer;
      errors.push(`apilayer: ${apilayer.error}`);
    } else {
      errors.push("apilayer: could not sign URL");
    }
  } else {
    errors.push("apilayer: not configured");
  }

  // All providers failed — fail closed.
  return {
    value: 5,
    description: "provider failure",
    details: {},
    provider: "none",
    error: errors.join("; "),
  };
}

/// OpenAI omni-moderation-latest accepts inline base64 image input.
async function classifyWithOpenAI(
  supabase: ReturnType<typeof createClient>,
  storagePath: string,
  mimeType: string,
): Promise<ClassifyResult> {
  const provider = "openai_omni";
  try {
    const { data: blob, error: dlError } = await supabase.storage
      .from("attachments")
      .download(storagePath);
    if (dlError || !blob) {
      return { value: 5, description: "", details: {}, provider, error: `download failed: ${dlError?.message ?? "no data"}` };
    }
    const bytes = new Uint8Array(await blob.arrayBuffer());
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
      return { value: 5, description: "", details: {}, provider, error: `OpenAI HTTP ${res.status}: ${(await res.text()).slice(0, 200)}` };
    }

    const data = await res.json();
    const result = data.results?.[0];
    if (!result) {
      return { value: 5, description: "", details: {}, provider, error: "no moderation result" };
    }

    const scores: Record<string, number> = result.category_scores ?? {};
    const sexual = Math.max(scores["sexual"] ?? 0, scores["sexual/minors"] ?? 0);
    const violent = Math.max(scores["violence"] ?? 0, scores["violence/graphic"] ?? 0);
    const maxRelevant = Math.max(sexual, violent);

    let value: number;
    if ((scores["sexual/minors"] ?? 0) > 0.1) value = 5;
    else if (maxRelevant >= 0.8) value = 5;
    else if (maxRelevant >= 0.55) value = 4;
    else if (maxRelevant >= 0.35) value = 3;
    else if (maxRelevant >= 0.15) value = 2;
    else value = 1;

    return {
      value,
      description: result.flagged ? "flagged by OpenAI moderation" : "within OpenAI moderation thresholds",
      details: { category_scores: scores, flagged: result.flagged },
      provider,
    };
  } catch (e) {
    return { value: 5, description: "", details: {}, provider, error: String((e as Error)?.message ?? e) };
  }
}

/// APILayer Nudity Detection: returns a 1..5 score (5 = most likely nude).
async function classifyWithApilayer(imageUrl: string): Promise<ClassifyResult> {
  const provider = "apilayer_nudity";
  const base = APILAYER_BASE.replace(/\/$/, "");
  const headers = { apikey: APILAYER_API_KEY! };
  const attempts: Array<() => Promise<Response>> = [
    () => fetch(`${base}/url`, {
      method: "POST",
      headers: { ...headers, "Content-Type": "application/json" },
      body: JSON.stringify({ url: imageUrl }),
    }),
    () => fetch(`${base}?url=${encodeURIComponent(imageUrl)}`, { method: "POST", headers }),
    async () => {
      const img = await fetch(imageUrl);
      const bytes = new Uint8Array(await img.arrayBuffer());
      return await fetch(base, { method: "POST", headers, body: bytes });
    },
  ];

  let lastError = "unknown";
  for (const attempt of attempts) {
    try {
      const res = await attempt();
      if (!res || !res.ok) {
        if (res) lastError = `HTTP ${res.status}`;
        continue;
      }
      const data = await res.json();
      const value = Number(data.value);
      if (!Number.isFinite(value)) {
        return { value: 5, description: "unparseable response", details: data, provider, error: "Unexpected response shape" };
      }
      return { value, description: String(data.description ?? ""), details: data, provider };
    } catch (e) {
      lastError = String((e as Error)?.message ?? e);
    }
  }
  return { value: 5, description: "provider failure", details: {}, provider, error: `Nudity API unavailable: ${lastError}` };
}
