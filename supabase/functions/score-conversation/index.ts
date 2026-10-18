// ============================================================
// Edge Function: score-conversation
// ADditive AI analytics. Scores one conversation with Gemini and
// upserts the result into conversation_scores.
//
// This is NOT a safety control. OpenAI moderation
// (moderate-message / moderate-image) remains the safety authority
// and stays fail-closed. A score here never approves, blocks or
// moderates anything — it is reporting only.
//
// Auth: the caller's JWT. Caller must be a conversation member, a
// school admin, or a head teacher of that school.
// ============================================================
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  AiProviderError,
  AiUnavailableError,
  callGemini,
  clampScore,
  cleanLabel,
  isUuid,
  logAiError,
  parseLooseJson,
} from "../_shared/gemini.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const MAX_MESSAGES = 60;
const MAX_BODY_CHARS = 1000;
const MAX_SUMMARY_CHARS = 240;
const MAX_TOPICS = 8;
const MAX_TOPIC_CHARS = 30;
// Server-side floor: the model may suggest a flag, but it can never
// clear a high safety risk that it itself reported.
const SAFETY_FLAG_FLOOR = 70;

const SYSTEM_INSTRUCTION =
  `You are an analytics assistant for a school safeguarding messaging platform. ` +
  `You are given the transcript of ONE conversation between school staff and/or students, ` +
  `written as "[n] timestamp Participant X: text". ` +
  `Respond with STRICT JSON only: no markdown, no code fences, no prose before or after the JSON object. ` +
  `Do not copy message text verbatim into the summary; summarise in your own neutral words. ` +
  `Never invent facts, incidents, names or numbers that are not in the transcript. ` +
  `Scores are 0-100 integers: "sentiment" is tone positivity (0 = very negative, 100 = very positive), ` +
  `"safety_risk" is safeguarding/safety risk (0 = no concern, 100 = severe concern), ` +
  `"resolution" is how settled the matter appears (0 = unresolved, 100 = fully resolved), ` +
  `and "overall" is general conversation health.`;

const PROMPT_CONTRACT =
  `Return EXACTLY one JSON object with these seven keys and no others:\n` +
  `{\n` +
  `  "overall": <integer 0-100>,\n` +
  `  "sentiment": <integer 0-100>,\n` +
  `  "safety_risk": <integer 0-100>,\n` +
  `  "resolution": <integer 0-100>,\n` +
  `  "flagged": <true|false>,\n` +
  `  "topics": [<string>, ...],\n` +
  `  "summary": "<string, at most ${MAX_SUMMARY_CHARS} characters, single line>"\n` +
  `}\n` +
  `Rules: all four numbers MUST be integers between 0 and 100 inclusive. ` +
  `"flagged" MUST be true when a human safeguarding or pastoral lead should review the thread. ` +
  `"topics" MUST contain 0 to 6 short lowercase labels, each at most ${MAX_TOPIC_CHARS} characters.`;

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, content-type",
      },
    });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return jsonError("unauthorized", 401);

    // User-scoped client so auth.uid() and RLS apply.
    const userClient = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: authError } = await userClient.auth.getUser();
    if (authError || !user) return jsonError("unauthorized", 401);

    let payload: { conversation_id?: unknown };
    try {
      payload = await req.json();
    } catch {
      return jsonError("invalid_json", 400);
    }

    const conversationId = payload.conversation_id;
    if (!isUuid(conversationId)) return jsonError("invalid_conversation_id", 400);

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    const { data: conversation } = await supabase
      .from("conversations")
      .select("id, school_id, type")
      .eq("id", conversationId)
      .maybeSingle();

    if (!conversation) return jsonError("conversation_not_found", 404);
    const schoolId: string = conversation.school_id;

    // Authorisation is resolved through the SECURITY DEFINER helpers on the
    // USER client, so the caller's own identity is what gets evaluated.
    const isMember = await rpcBool(userClient, "tc_is_conversation_member", {
      p_conversation_id: conversationId,
    });
    const isAdmin = await rpcBool(userClient, "tc_is_school_admin", { p_school_id: schoolId });
    const isLeadership = await rpcBool(userClient, "tc_has_school_role", {
      p_school_id: schoolId,
      p_role: "head_teacher",
    });

    if (!isMember && !isAdmin && !isLeadership) {
      console.error("score-conversation: forbidden", user.id, conversationId);
      return jsonError("forbidden", 403);
    }

    // Only APPROVED, non-deleted messages are ever sent to the model.
    const { data: rows, error: msgError } = await supabase
      .from("messages")
      .select("id, sender_id, body, created_at")
      .eq("conversation_id", conversationId)
      .eq("status", "approved")
      .eq("is_deleted", false)
      .not("body", "is", null)
      .order("created_at", { ascending: false })
      .limit(MAX_MESSAGES);

    if (msgError) {
      console.error("score-conversation: message query failed", msgError);
      return jsonError("server_error", 500);
    }

    // Newest first from the query; flip back to chronological for the model.
    const messages = (rows ?? [])
      .filter((m: any) => typeof m.body === "string" && m.body.trim().length > 0)
      .reverse();

    if (messages.length === 0) return jsonError("no_approved_messages", 422);

    // Pseudonymise senders: the model never sees raw user ids.
    const aliases = new Map<string, string>();
    const transcript = messages
      .map((m: any, i: number) => {
        let alias = aliases.get(m.sender_id);
        if (!alias) {
          alias = `Participant ${aliases.size + 1}`;
          aliases.set(m.sender_id, alias);
        }
        const body = String(m.body).slice(0, MAX_BODY_CHARS);
        return `[${i + 1}] ${m.created_at} ${alias}: ${body}`;
      })
      .join("\n");

    const prompt =
      `Conversation type: ${conversation.type}\n` +
      `Approved messages considered: ${messages.length}\n\n` +
      `--- TRANSCRIPT ---\n${transcript}\n--- END TRANSCRIPT ---\n\n${PROMPT_CONTRACT}`;

    const result = await callGemini({
      systemInstruction: SYSTEM_INSTRUCTION,
      prompt,
      responseMimeType: "application/json",
      temperature: 0.2,
      maxOutputTokens: 1024,
    });

    const parsed = parseLooseJson(result.text);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      throw new AiProviderError(result.provider, "model output was not a JSON object");
    }

    // Clamp before trusting anything.
    const overall = clampScore(parsed.overall, 0);
    const sentiment = clampScore(parsed.sentiment, 0);
    const safetyRisk = clampScore(parsed.safety_risk, 0);
    const resolution = clampScore(parsed.resolution, 0);
    const flagged = parsed.flagged === true || safetyRisk >= SAFETY_FLAG_FLOOR;

    const topics: string[] = [];
    if (Array.isArray(parsed.topics)) {
      for (const t of parsed.topics) {
        const label = cleanLabel(t, MAX_TOPIC_CHARS);
        if (label && !topics.includes(label)) topics.push(label);
        if (topics.length >= MAX_TOPICS) break;
      }
    }

    const summary = cleanLabel(parsed.summary, MAX_SUMMARY_CHARS);

    const modelLabel = `${result.model}@${result.provider}`;
    const now = new Date().toISOString();

    const { error: upsertError } = await supabase
      .from("conversation_scores")
      .upsert(
        {
          conversation_id: conversationId,
          school_id: schoolId,
          overall,
          sentiment,
          safety_risk: safetyRisk,
          resolution,
          flagged,
          topics,
          summary,
          model: modelLabel,
          scored_at: now,
        },
        { onConflict: "conversation_id" },
      );

    if (upsertError) {
      console.error("score-conversation: upsert failed", upsertError);
      return jsonError("server_error", 500);
    }

    return new Response(
      JSON.stringify({
        success: true,
        conversation_id: conversationId,
        score: {
          overall,
          sentiment,
          safety_risk: safetyRisk,
          resolution,
          flagged,
          topics,
          summary,
        },
        messages_considered: messages.length,
        model: modelLabel,
      }),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (err) {
    if (err instanceof AiUnavailableError) {
      logAiError("score-conversation", err);
      return jsonError("ai_unavailable", 503);
    }
    if (err instanceof AiProviderError) {
      logAiError("score-conversation", err);
      return jsonError("ai_provider_error", 502);
    }
    console.error("score-conversation error:", err);
    return jsonError("server_error", 500);
  }
});

/// Call a boolean SECURITY DEFINER helper through the caller's own JWT.
async function rpcBool(
  client: ReturnType<typeof createClient>,
  fn: string,
  args: Record<string, unknown>,
): Promise<boolean> {
  const { data, error } = await client.rpc(fn as any, args as any);
  if (error) {
    console.error(`score-conversation: rpc ${fn} failed`, error);
    return false;
  }
  return data === true;
}

function jsonError(error: string, status: number) {
  return new Response(JSON.stringify({ success: false, error }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}