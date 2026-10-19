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

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const INTERNAL_WEBHOOK_SECRET = Deno.env.get("INTERNAL_WEBHOOK_SECRET")!;

const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");

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
    } else if (!OPENAI_API_KEY) {
      provider = "none";
      providerError = "OPENAI_API_KEY not configured — held for review";
    } else {
      const result = await classifyWithOpenAI(supabase, attachment.storage_path, attachment.mime_type);
      if (result.error) {
        provider = "openai";
        providerError = result.error;
      } else {
        categories = result.categories ?? {};
        provider = "openai_omni";
      }
    }

    // Determine audience from the message this attachment belongs to
    let audience = "unknown";
    if (attachment.message_id) {
      const { data: msg } = await supabase
        .from("messages")
        .select("sender_id")
        .eq("id", attachment.message_id)
        .single();
      if (msg) {
        const { data: membership } = await supabase
          .from("conversation_members")
          .select("role")
          .eq("conversation_id", msg.sender_id ? null : null)
          .eq("user_id", msg.sender_id)
          .is("removed_at", null)
          .maybeSingle();
        // Fall back to unknown if we can't resolve conversation
        audience = (membership?.role as string) ?? "unknown";
      }
    }

    decision = decide(categories, audience, providerError);

    const verdict = decision.action === "approved" ? "approved"
      : decision.action === "blocked"
      ? "blocked"
      : "held_for_review";

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

    await supabase.from("moderation_results").insert({
      school_id,
      attachment_id,
      provider,
      verdict: decision.action === "approved" ? "approved"
        : decision.action === "blocked"
        : "held_for_review",
      confidence: decision.score,
      categories: scanResult,
      provider_error: providerError,
      raw_response: scanResult,
      processed_at: new Date().toISOString(),
    });

    const attachmentStatus = decision.action === "approved" ? "approved"
      : decision.action === "blocked"
      ? "rejected"
      : "quarantined";

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
      JSON.stringify({ verdict, attachment_status: attachmentStatus, provider, score: decision.score }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error("moderate-image error:", err);
    return new Response("Server error", { status: 500 });
  }
});

async function classifyWithOpenAI(
  supabase: ReturnType<typeof createClient>,
  storagePath: string,
  mimeType: string,
): Promise<CategoryScores & { error?: string }> {
  const provider = "openai_omni";
  try {
    const { data: blob, error: dlError } = await supabase.storage
      .from("attachments")
      .download(storagePath);
    if (dlError || !blob) {
      return { categories: {}, error: `download failed: ${dlError?.message ?? "no data"}` };
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
      return { categories: {}, error: `OpenAI HTTP ${res.status}: ${(await res.text()).slice(0, 200)}` };
    }

    const data = await res.json();
    const result = data.results?.[0];
    if (!result) {
      return { categories: {}, error: "no moderation result" };
    }

    return { categories: result.category_scores ?? {} };
  } catch (e) {
    return { categories: {}, error: String((e as Error)?.message ?? e) };
  }
}
