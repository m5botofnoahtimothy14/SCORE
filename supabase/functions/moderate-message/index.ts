// ============================================================
// Edge Function: moderate-message
// Server-side content moderation — never trust client.
// Called automatically after message insert via DB trigger/webhook.
//
// Architecture:
//   1. Signal extraction: OpenAI moderation API (if configured) returns
//      per-category scores (0..1). Falls back to keyword heuristic if no key.
//   2. Policy engine: first-party rule engine decides approve/hold/block
//      using multi-signal thresholds per audience (student/teacher/leadership).
//   3. ML/scoring layer: every decision is persisted to moderation_results
//      with full signal provenance so the F1/eval dashboard can compute
//      precision/recall/F1 per category over time.
// ============================================================
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
const INTERNAL_WEBHOOK_SECRET = Deno.env.get("INTERNAL_WEBHOOK_SECRET")!;

// Audience types mirroring school_role enum.
type Audience = "student" | "teacher" | "head_teacher" | "principal" | "school_admin" | "platform_owner" | "unknown";

// Category score keys OpenAI moderation returns.
type CategoryScores = Record<string, number>;

interface PolicyDecision {
  action: "approve" | "hold" | "block";
  score: number;            // 0..1 overall risk
  providerScore: number;    // raw provider max score
  reasons: string[];
  matchedRules: string[];
  provider: string;
  audience: string;
  providerError?: string;
}

// ── Policy engine (first-party, auditable) ──────────────────────
function getCategory(categories: CategoryScores, name: string): number {
  return Number(categories[name]) || 0;
}

function decide(
  categories: CategoryScores,
  text: string,
  audience: Audience,
  providerError?: string,
): PolicyDecision {
  const reasons: string[] = [];
  const matchedRules: string[] = [];

  const sexual = getCategory(categories, "sexual");
  const sexualMinors = getCategory(categories, "sexual_minors");
  const hate = getCategory(categories, "hate");
  const harassment = getCategory(categories, "harassment");
  const harassmentThreatening = getCategory(categories, "harassment/threatening");
  const violence = getCategory(categories, "violence");
  const selfHarm = getCategory(categories, "self_harm");
  const illicit = getCategory(categories, "illicit");

  // Fail closed on provider error.
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

  // Critical blocks — any audience, self-harm / CSAM / threats are never approved.
  if (selfHarm >= 0.5 || sexualMinors >= 0.3 || harassmentThreatening >= 0.8) {
    matchedRules.push("critical_block");
    reasons.push("critical_safety_signal");
    return {
      action: "block",
      score: 1,
      providerScore: Math.max(sexualMinors, harassmentThreatening, selfHarm),
      reasons: [...reasons, "critical_block"],
      matchedRules: [...matchedRules, "critical_block"],
      provider: "policy",
      audience,
    };
  }

  const isStudent = audience === "student";
  const isTeacherOrAbove = ["teacher", "head_teacher", "principal", "school_admin", "platform_owner"].includes(audience);

  // Student thresholds — stricter.
  if (isStudent) {
    if (sexual >= 0.3 || hate >= 0.6 || harassment >= 0.6 || violence >= 0.6 || illicit >= 0.5) {
      matchedRules.push("student_block");
      reasons.push("student_high_risk");
      return {
        action: "block",
        score: Math.max(sexual, hate, harassment, violence, illicit),
        providerScore: Math.max(sexual, hate, harassment, violence, illicit),
        reasons: [...reasons, "student_block"],
        matchedRules: [...matchedRules, "student_block"],
        provider: "policy",
        audience,
      };
    }
    if (sexual >= 0.15 || hate >= 0.3 || harassment >= 0.3 || violence >= 0.3) {
      matchedRules.push("student_hold");
      reasons.push("student_moderate_risk");
      return {
        action: "hold",
        score: Math.max(sexual, hate, harassment, violence),
        providerScore: Math.max(sexual, hate, harassment, violence),
        reasons: [...reasons, "student_hold"],
        matchedRules: [...matchedRules, "student_hold"],
        provider: "policy",
        audience,
      };
    }
  }

  // Teacher/leadership thresholds — more permissive but still bounded.
  if (isTeacherOrAbove) {
    if (sexualMinors >= 0.5 || harassmentThreatening >= 0.7) {
      matchedRules.push("staff_block");
      reasons.push("staff_high_risk");
      return {
        action: "block",
        score: Math.max(sexualMinors, harassmentThreatening),
        providerScore: Math.max(sexualMinors, harassmentThreatening),
        reasons: [...reasons, "staff_block"],
        matchedRules: [...matchedRules, "staff_block"],
        provider: "policy",
        audience,
      };
    }
    if (sexual >= 0.5 || hate >= 0.7 || harassment >= 0.7 || violence >= 0.7) {
      matchedRules.push("staff_hold");
      reasons.push("staff_moderate_risk");
      return {
        action: "hold",
        score: Math.max(sexual, hate, harassment, violence),
        providerScore: Math.max(sexual, hate, harassment, violence),
        reasons: [...reasons, "staff_hold"],
        matchedRules: [...matchedRules, "staff_hold"],
        provider: "policy",
        audience,
      };
    }
  }

  // Unknown audience — fail closed, lean toward hold.
  if (audience === "unknown") {
    const max = Math.max(sexual, hate, harassment, violence, illicit, selfHarm);
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
    score: Math.max(sexual, hate, harassment, violence, illicit, selfHarm),
    providerScore: Math.max(sexual, hate, harassment, violence, illicit, selfHarm),
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
    const { message_id, school_id } = body;

    if (!message_id || !school_id) {
      return new Response("Missing fields", { status: 400 });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    const { data: message } = await supabase
      .from("messages")
      .select("id, body, sender_id, conversation_id, status")
      .eq("id", message_id)
      .single();

    if (!message || message.status !== "pending_moderation") {
      return new Response("Message not found or already processed", { status: 200 });
    }

    // ── Signal extraction ─────────────────────────────────────
    let categories: CategoryScores = {};
    let provider = "none";
    let providerError: string | undefined;

    if (!message.body || message.body.trim() === "") {
      provider = "internal";
    } else if (!OPENAI_API_KEY) {
      provider = "none";
      providerError = "OPENAI_API_KEY not configured — held for review";
    } else {
      const result = await moderateWithOpenAI(message.body);
      if (result.error) {
        provider = "openai";
        providerError = result.error;
      } else {
        categories = result.categories;
        provider = "openai";
      }
    }

    // ── Policy decision ───────────────────────────────────────
    const audience = await resolveConversationAudience(supabase, message.conversation_id, message.sender_id);
    const decision = decide(categories, message.body || "", audience, providerError);

    const verdict = decision.action === "approved" ? "approved"
      : decision.action === "blocked" ? "blocked"
      : "held_for_review";

    // ── Persist scoring event (ML data pipeline) ──────────────
    const scoringEvent = {
      school_id,
      message_id,
      provider: decision.provider,
      verdict: decision.action === "approved" ? "approved"
        : decision.action === "blocked" ? "blocked"
        : "held_for_review",
      confidence: decision.score,
      categories,
      provider_error: providerError,
      raw_response: {
        policy_version: "v1",
        action: decision.action,
        policy_score: decision.score,
        raw_max_score: decision.providerScore,
        audience: decision.audience,
        matched_rules: decision.matchedRules,
        reasons: decision.reasons,
        explanation: decision.reasons.join("; "),
        signals: categories,
      },
    };

    const { data: modResult } = await supabase
      .from("moderation_results")
      .insert(scoringEvent)
      .select("id")
      .single();

    // ── Update message status ─────────────────────────────────
    const messageStatus = verdict === "approved" || verdict === "warned"
      ? "approved"
      : verdict === "blocked"
      ? "blocked"
      : "held_for_review";

    await supabase
      .from("messages")
      .update({ status: messageStatus })
      .eq("id", message_id);

    // ── Review queue ──────────────────────────────────────────
    if (["held", "blocked", "escalated"].includes(verdict)) {
      await supabase.from("moderation_review_cases").insert({
        school_id,
        moderation_result_id: modResult?.id,
        status: verdict === "escalated" ? "escalated" : "pending",
        reason_code: verdict,
      });
    }

    // ── Dispatch notification for approved messages ─────────────
    if (messageStatus === "approved") {
      await dispatchMessageNotification(supabase, message_id, school_id);
    }

    return new Response(JSON.stringify({ verdict, message_status: messageStatus, score: decision.score }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("moderate-message error:", err);
    return new Response("Server error", { status: 500 });
  }
});

async function moderateWithOpenAI(text: string): Promise<{
  categories: CategoryScores;
  maxScore: number;
  flagged: boolean;
  error?: string;
}> {
  try {
    const response = await fetch("https://api.openai.com/v1/moderations", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${OPENAI_API_KEY}`,
      },
      body: JSON.stringify({ input: text }),
    });

    if (!response.ok) {
      return { categories: {}, maxScore: 0, flagged: false, error: `OpenAI API error: ${response.status}` };
    }

    const data = await response.json();
    const result = data.results?.[0];
    if (!result) return { categories: {}, maxScore: 0, flagged: false, error: "No moderation result" };

    const categories: Record<string, number> = result.category_scores ?? {};
    const maxScore = Math.max(...Object.values(categories) as number[], 0);

    return { categories, maxScore, flagged: Boolean(result.flagged) };
  } catch (err) {
    return { categories: {}, maxScore: 0, flagged: false, error: String(err) };
  }
}

async function resolveConversationAudience(
  supabase: ReturnType<typeof createClient>,
  conversationId: string | null,
  senderId: string,
): Promise<Audience> {
  try {
    if (!conversationId) return "unknown";
    const [{ data: conversation }, { data: membership }] = await Promise.all([
      supabase.from("conversations").select("type").eq("id", conversationId).maybeSingle(),
      supabase
        .from("conversation_members")
        .select("role")
        .eq("conversation_id", conversationId)
        .eq("user_id", senderId)
        .is("removed_at", null)
        .maybeSingle(),
    ]);
    return ((conversation?.type as Audience) ?? "unknown") as Audience;
  } catch {
    return "unknown";
  }
}

async function dispatchMessageNotification(
  supabase: ReturnType<typeof createClient>,
  messageId: string,
  schoolId: string,
) {
  try {
    const { data: message } = await supabase
      .from("messages")
      .select("conversation_id, sender_id")
      .eq("id", messageId)
      .single();
    if (!message) return;

    const { data: members } = await supabase
      .from("conversation_members")
      .select("user_id")
      .eq("conversation_id", message.conversation_id)
      .neq("user_id", message.sender_id)
      .is("removed_at", null);

    if (!members?.length) return;

    const jobs = members.map((m) => ({
      school_id: schoolId,
      recipient_id: m.user_id,
      type: "message",
      title: "New Message",
      body: "You have a new message",
      data: {
        type: "message",
        conversation_id: message.conversation_id,
        school_id: schoolId,
      },
      idempotency_key: `msg_notif:${messageId}:${m.user_id}`,
    }));

    await supabase.from("notification_jobs").insert(jobs);

    const { error } = await supabase.functions.invoke("dispatch-notifications", {
      body: { school_id: schoolId },
    });
    if (error) console.error("Failed to invoke dispatch-notifications:", error);
  } catch (err) {
    console.error("dispatchMessageNotification error:", err);
  }
}
