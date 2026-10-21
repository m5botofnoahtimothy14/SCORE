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
import {
  applyPolicy,
  explainDecision,
  toTextVerdict,
} from "../_shared/moderation_policy.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
const INTERNAL_WEBHOOK_SECRET = Deno.env.get("INTERNAL_WEBHOOK_SECRET")!;

// The policy engine now lives in the shared module (see the import above).
// The thresholds, the allowlist and the fail-closed rule are evaluated
// there, against the same labelled dataset the test suite uses.

// Audience types mirroring the school_role enum.
type SenderRole =
  | "student"
  | "teacher"
  | "head_teacher"
  | "principal"
  | "school_admin"
  | "platform_owner"
  | "unknown";

// Category score keys the vendor returns (OpenAI omni-moderation).
type CategoryScores = Record<string, number>;

/** Map a policy action onto the `messages.status` enum. */
function messageStatusFor(action: string): "approved" | "blocked" | "held_for_review" {
  switch (action) {
    case "approve": return "approved";
    case "block": return "blocked";
    default: return "held_for_review";
  }
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
    // The shared policy module owns the thresholds, the allowlist and the
    // fail-closed rule. This function only supplies the signals.
    const audience = await resolveSenderAudience(
      supabase,
      message.conversation_id,
      message.sender_id,
    );
    const decision = applyPolicy({
      categories,
      text: message.body ?? "",
      context: {
        media: "text",
        audience: "unknown",
        senderRole: audience,
        provider,
        providerError: providerError ?? null,
      },
    });

    const verdict = toTextVerdict(decision);
    const messageStatus = messageStatusFor(decision.action);

    // ── Persist scoring event (ML data pipeline) ──────────────
    const scoringEvent = {
      school_id,
      message_id,
      provider,
      verdict,
      // Confidence = how sure we are of the verdict. For an approval that
      // is the inverse of the risk score; for a hold/block it is the score.
      confidence: verdict === "approved" ? 1 - decision.score : decision.score,
      categories,
      provider_error: providerError,
      raw_response: {
        policy_version: "v1",
        action: decision.action,
        policy_score: decision.score,
        audience: decision.audience,
        matched_rules: decision.matchedRules,
        reasons: decision.reasons,
        explanation: explainDecision(decision),
        escalate: decision.escalate,
        signals: decision.signals,
        allowlist: decision.allowlistMatches,
      },
    };

    const { data: modResult, error: modErr } = await supabase
      .from("moderation_results")
      .insert(scoringEvent)
      .select("id")
      .single();
    if (modErr) {
      // The verdict must still be applied even if provenance could not be
      // stored — but the review case would be unlinkable, so log loudly.
      console.error("moderation_results insert failed:", modErr.message);
    }

    // ── Update message status ─────────────────────────────────
    const { error: msgErr } = await supabase
      .from("messages")
      .update({ status: messageStatus })
      .eq("id", message_id);
    if (msgErr) console.error("message status update failed:", msgErr.message);

    // ── Review queue ──────────────────────────────────────────
    // An allowlist approval ("warned") is deliverable, so it does not
    // reach a human. A hold or a block always does.
    if (decision.action !== "approve") {
      const { error: caseErr } = await supabase.from("moderation_review_cases").insert({
        school_id,
        moderation_result_id: modResult?.id ?? null,
        status: "pending",
        reason_code: verdict,
      });
      if (caseErr) console.error("moderation_review_cases insert failed:", caseErr.message);
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

    // The RAW vendor vector is stored, exactly as the vendor produced it.
    // The policy module owns the mapping from these keys onto its own
    // categories, and the scoring pipeline reads the same shape.
    const categories = (result.category_scores ?? {}) as CategoryScores;
    const maxScore = Math.max(...Object.values(categories), 0);

    return { categories, maxScore, flagged: Boolean(result.flagged) };
  } catch (err) {
    return { categories: {}, maxScore: 0, flagged: false, error: String(err) };
  }
}

/**
 * Resolve the audience tier of the SENDER so the policy engine can apply the
 * right thresholds (students are held to stricter limits than staff).
 *
 * The conversation *type* is not an audience — "student_teacher" is a channel
 * shape, not a role — so the tier is taken from the sender's school
 * membership role, falling back to the conversation member role.
 */
async function resolveSenderAudience(
  supabase: ReturnType<typeof createClient>,
  conversationId: string | null,
  senderId: string,
): Promise<SenderRole> {
  try {
    const { data: membership } = await supabase
      .from("school_memberships")
      .select("role")
      .eq("user_id", senderId)
      .eq("is_active", true)
      .order("joined_at", { ascending: true })
      .limit(1)
      .maybeSingle();

    const role = membership?.role as SenderRole | undefined;
    if (role && role !== "unknown") return role;

    if (!conversationId) return "unknown";
    const { data: member } = await supabase
      .from("conversation_members")
      .select("role")
      .eq("conversation_id", conversationId)
      .eq("user_id", senderId)
      .is("removed_at", null)
      .maybeSingle();

    const memberRole = member?.role as SenderRole | undefined;
    return memberRole && memberRole !== "unknown" ? memberRole : "unknown";
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
