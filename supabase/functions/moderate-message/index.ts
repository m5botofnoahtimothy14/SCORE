// ============================================================
// Edge Function: moderate-message
// Server-side content moderation — never trust client
// Called automatically after message insert via DB trigger/webhook
//
// The vendor (OpenAI moderation) is the SIGNAL SOURCE. The verdict is
// decided by the first-part policy in _shared/moderation_policy.ts,
// which is what stops generic vendor thresholds from blocking real
// learning conversations. See docs/MODERATION.md.
// ============================================================
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  applyPolicy,
  toTextVerdict,
  explainDecision,
  type ConversationAudience,
  type PolicyDecision,
  type SenderRole,
} from "../_shared/moderation_policy.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
const INTERNAL_WEBHOOK_SECRET = Deno.env.get("INTERNAL_WEBHOOK_SECRET")!;

serve(async (req: Request) => {
  // Verify this is called from our internal webhook, not the public
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

    // Get message
    const { data: message } = await supabase
      .from("messages")
      .select("id, body, sender_id, conversation_id, status")
      .eq("id", message_id)
      .single();

    if (!message || message.status !== "pending_moderation") {
      return new Response("Message not found or already processed", { status: 200 });
    }

    // Policy context: conversation audience + sender role. Best effort —
    // a missing context must never weaken the policy, so any failure here
    // falls back to the neutral `unknown` profile.
    const context = await resolvePolicyContext(supabase, message);

    let verdict: string;
    let categories: Record<string, number> = {};
    let confidence = 0;
    let provider = "none";
    let providerError: string | undefined;
    let decision: PolicyDecision | undefined;

    if (!message.body || message.body.trim() === "") {
      // Attachment-only message — approve text, attachment moderated separately
      verdict = "approved";
      provider = "internal";
    } else if (!OPENAI_API_KEY) {
      // CRITICAL: Moderation provider not configured
      // MUST NOT approve — hold for manual review
      verdict = "held";
      provider = "none";
      providerError = "OPENAI_API_KEY not configured — message held for manual review";
      console.error("MODERATION PROVIDER NOT CONFIGURED. Message held:", message_id);
    } else {
      // Call OpenAI Moderation API
      const result = await moderateWithOpenAI(message.body);
      if (result.error) {
        // Provider failed — MUST NOT approve — hold for review
        verdict = "held";
        provider = "openai";
        providerError = result.error;
        console.error("OpenAI moderation failed — holding message:", message_id, result.error);
      } else {
        categories = result.categories;
        confidence = result.maxScore;
        provider = "openai";

        // The policy decides. Fail-closed behaviour is inside applyPolicy:
        // a missing provider or providerError can never return "approve".
        decision = applyPolicy({
          categories,
          text: message.body,
          context: {
            ...context,
            provider: "openai",
            providerError: null,
            flagged: result.flagged,
          },
        });
        verdict = toTextVerdict(decision);
        console.log(`moderation ${message_id}: ${explainDecision(decision)}`);
      }
    }

    // Save moderation result
    const { data: modResult } = await supabase
      .from("moderation_results")
      .insert({
        school_id,
        message_id,
        provider,
        verdict,
        confidence,
        categories,
        provider_error: providerError,
        // Full policy audit trail: what fired, why, with which thresholds.
        raw_response: decision
          ? {
            policy_version: decision.policyVersion,
            action: decision.action,
            policy_score: decision.score,
            raw_max_score: decision.rawMaxScore,
            audience: decision.audience,
            audience_scale: decision.audienceScale,
            matched_rules: decision.matchedRules,
            allowlist_matches: decision.allowlistMatches,
            reasons: decision.reasons,
            explanation: explainDecision(decision),
            signals: decision.signals,
          }
          : { policy_version: "not_applied", reason: providerError ?? "internal/attachment-only" },
      })
      .select("id")
      .single();

    // Update message status
    const messageStatus = verdict === "approved" || verdict === "warned"
      ? "approved"
      : verdict === "blocked"
      ? "blocked"
      : "held_for_review";

    await supabase
      .from("messages")
      .update({ status: messageStatus })
      .eq("id", message_id);

    // Create review case for held/blocked/escalated
    if (["held", "blocked", "escalated"].includes(verdict)) {
      await supabase.from("moderation_review_cases").insert({
        school_id,
        moderation_result_id: modResult?.id,
        status: verdict === "escalated" ? "escalated" : "pending",
        reason_code: verdict,
      });
    }

    // If approved or warned, dispatch notifications to conversation members
    if (messageStatus === "approved") {
      await dispatchMessageNotification(supabase, message_id, school_id);
    }

    return new Response(JSON.stringify({ verdict, message_status: messageStatus }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("moderate-message error:", err);
    return new Response("Server error", { status: 500 });
  }
});

async function moderateWithOpenAI(text: string): Promise<{
  categories: Record<string, number>;
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

/**
 * Build the policy context from the live conversation. Best effort: any
 * failure falls back to the neutral `unknown` audience, which can only make
 * the policy LESS strict, never more. A missing context must never be able
 * to approve something.
 */
async function resolvePolicyContext(
  supabase: ReturnType<typeof createClient>,
  message: { conversation_id: string | null; sender_id: string },
): Promise<{ audience: ConversationAudience; senderRole: SenderRole }> {
  try {
    const conversationId = message.conversation_id;
    if (!conversationId) return { audience: "unknown", senderRole: "unknown" };

    const [{ data: conversation }, { data: membership }] = await Promise.all([
      supabase.from("conversations").select("type").eq("id", conversationId).maybeSingle(),
      supabase
        .from("conversation_members")
        .select("role")
        .eq("conversation_id", conversationId)
        .eq("user_id", message.sender_id)
        .is("removed_at", null)
        .maybeSingle(),
    ]);

    return {
      audience: (conversation?.type as ConversationAudience) ?? "unknown",
      senderRole: (membership?.role as SenderRole) ?? "unknown",
    };
  } catch (err) {
    console.warn("resolvePolicyContext failed, using neutral profile:", err);
    return { audience: "unknown", senderRole: "unknown" };
  }
}

async function dispatchMessageNotification(
  supabase: ReturnType<typeof createClient>,
  messageId: string,
  schoolId: string
) {
  try {
    // Get conversation members who are NOT the sender
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

    // Queue notification jobs (do NOT include message body in notification payload)
    const jobs = members.map(m => ({
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

    // Trigger FCM dispatch
    const { error } = await supabase.functions.invoke("dispatch-notifications", {
      body: { school_id: schoolId },
    });

    if (error) console.error("Failed to invoke dispatch-notifications:", error);
  } catch (err) {
    console.error("dispatchMessageNotification error:", err);
  }
}
