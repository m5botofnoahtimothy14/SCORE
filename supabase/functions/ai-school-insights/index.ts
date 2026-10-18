// ============================================================
// Edge Function: ai-school-insights
// ADditive AI analytics. Produces a leadership-level school-health
// summary from AGGREGATE NUMBERS ONLY.
//
// This is NOT a safety control. OpenAI moderation
// (moderate-message / moderate-image) remains the safety authority.
// Nothing here moderates, approves, blocks or escalates anything;
// safeguarding incidents are only ever COUNTED.
//
// Privacy: no raw message text, no conversation titles, no user ids
// and no student-identifying data are ever sent to the model.
//
// Auth: platform owner or school admin, or head_teacher for the
// limited leadership view.
// ============================================================
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  AiProviderError,
  AiUnavailableError,
  average,
  callGemini,
  cleanLabel,
  isUuid,
  logAiError,
  parseLooseJson,
} from "../_shared/gemini.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const RECENT_SCORES = 10;
const MAX_SUMMARY_CHARS = 400;
const ACTION_COUNT = 3;
const MAX_ACTION_CHARS = 160;
const MAX_TOPICS = 5;
const MAX_TOPIC_CHARS = 30;

// Anything not resolved is treated as still open for leadership reporting.
const OPEN_INCIDENT_STATUSES = ["open", "investigating", "escalated_external"];
const OPEN_REVIEW_STATUSES = ["pending", "under_review", "escalated"];

const SYSTEM_INSTRUCTION =
  `You are an analyst advising senior leadership at a school. You receive AGGREGATE METRICS ONLY ` +
  `(counts and averages — never message text, never names). ` +
  `Respond with STRICT JSON only: no markdown, no code fences, no prose outside the JSON object. ` +
  `Be concise, factual and non-alarming. Never invent incidents, never name individuals, ` +
  `never claim something happened that the metrics do not support, and never recommend contacting ` +
  `external services or authorities — recommend internal, proportionate next steps.`;

const PROMPT_CONTRACT =
  `Return EXACTLY one JSON object with these two keys and no others:\n` +
  `{\n` +
  `  "summary": "<string, at most ${MAX_SUMMARY_CHARS} characters, single line, plain text>",\n` +
  `  "actions": ["<string>", "<string>", "<string>"]\n` +
  `}\n` +
  `Rules: "summary" describes the school's current communication and safeguarding posture in one paragraph. ` +
  `"actions" MUST contain exactly ${ACTION_COUNT} strings ordered by priority, most important first; ` +
  `each at most ${MAX_ACTION_CHARS} characters, imperative and actionable.`;

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

    const userClient = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: authError } = await userClient.auth.getUser();
    if (authError || !user) return jsonError("unauthorized", 401);

    let payload: { school_id?: unknown };
    try {
      payload = await req.json();
    } catch {
      return jsonError("invalid_json", 400);
    }

    let schoolId = payload.school_id;
    if (!isUuid(schoolId)) {
      // Fall back to the caller's single active school membership.
      const { data: memberships } = await userClient
        .from("school_memberships")
        .select("school_id")
        .eq("user_id", user.id)
        .eq("is_active", true)
        .limit(2);
      const rows = memberships ?? [];
      if (rows.length !== 1) return jsonError("invalid_school_id", 400);
      schoolId = rows[0].school_id;
    }

    const sid: string = schoolId;

    // Authorisation via the caller's own JWT + SECURITY DEFINER helpers.
    const [isOwner, isAdmin, isLeadership] = await Promise.all([
      rpcBool(userClient, "tc_is_platform_owner", {}),
      rpcBool(userClient, "tc_is_school_admin", { p_school_id: sid }),
      rpcBool(userClient, "tc_has_school_role", { p_school_id: sid, p_role: "head_teacher" }),
    ]);

    if (!isOwner && !isAdmin && !isLeadership) {
      console.error("ai-school-insights: forbidden", user.id, sid);
      return jsonError("forbidden", 403);
    }
    const scope: "admin" | "leadership" = (isOwner || isAdmin) ? "admin" : "leadership";

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    const [
      students,
      teachers,
      classes,
      incidents,
      criticalIncidents,
      reviewCases,
      failedJobs,
      recentScores,
    ] = await Promise.all([
      countWhere(supabase, "students", { school_id: sid, is_active: true }),
      countWhere(supabase, "teachers", { school_id: sid, is_active: true }),
      countWhere(supabase, "classes", { school_id: sid, is_active: true }),
      countWhere(supabase, "safeguarding_incidents", {
        school_id: sid,
        status: OPEN_INCIDENT_STATUSES,
      }),
      countWhere(supabase, "safeguarding_incidents", {
        school_id: sid,
        status: OPEN_INCIDENT_STATUSES,
        severity: ["critical", "high"],
      }),
      countWhere(supabase, "moderation_review_cases", {
        school_id: sid,
        status: OPEN_REVIEW_STATUSES,
      }),
      countWhere(supabase, "notification_jobs", { school_id: sid, status: "failed" }),
      recentConversationScores(supabase, sid),
    ]);

    const scores = recentScores ?? [];
    const flaggedCount = scores.filter((s: any) => s.flagged === true).length;

    const topicCounts = new Map<string, number>();
    for (const s of scores) {
      if (!Array.isArray(s.topics)) continue;
      for (const t of s.topics) {
        const label = cleanLabel(t, MAX_TOPIC_CHARS);
        if (!label) continue;
        topicCounts.set(label.toLowerCase(), (topicCounts.get(label.toLowerCase()) ?? 0) + 1);
      }
    }
    const topTopics = [...topicCounts.entries()]
      .sort((a, b) => b[1] - a[1])
      .slice(0, MAX_TOPICS)
      .map(([label, count]) => `${label} (${count})`);

    const metrics = {
      students,
      teachers,
      classes,
      safeguarding_open: incidents,
      safeguarding_open_high_or_critical: criticalIncidents,
      moderation_cases_open: reviewCases,
      notification_jobs_failed: failedJobs,
      conversations_scored_recent: scores.length,
      conversation_flagged_recent: flaggedCount,
      avg_overall: average(scores.map((s: any) => s.overall)),
      avg_sentiment: average(scores.map((s: any) => s.sentiment)),
      avg_safety_risk: average(scores.map((s: any) => s.safety_risk)),
      avg_resolution: average(scores.map((s: any) => s.resolution)),
      top_topics: topTopics,
    };

    // ---- Only these numbers leave the building. No raw text. ----
    const facts: string[] = [
      `Active students: ${metrics.students}`,
      `Active teachers: ${metrics.teachers}`,
      `Active classes: ${metrics.classes}`,
      `Open safeguarding incidents (open/investigating/escalated): ${metrics.safeguarding_open}`,
      `Of those, high or critical severity: ${metrics.safeguarding_open_high_or_critical}`,
      `Moderation cases awaiting review: ${metrics.moderation_cases_open}`,
      `Failed notification jobs: ${metrics.notification_jobs_failed}`,
      `Recent conversations scored (last ${RECENT_SCORES}): ${metrics.conversations_scored_recent}`,
      `Of those flagged for human review: ${metrics.conversation_flagged_recent}`,
      `Average overall score: ${fmt(metrics.avg_overall)}`,
      `Average sentiment score: ${fmt(metrics.avg_sentiment)}`,
      `Average safety risk score: ${fmt(metrics.avg_safety_risk)}`,
      `Average resolution score: ${fmt(metrics.avg_resolution)}`,
    ];
    if (metrics.top_topics.length > 0) {
      facts.push(`Most common conversation topics (model-generated labels): ${metrics.top_topics.join(", ")}`);
    }

    const result = await callGemini({
      systemInstruction: SYSTEM_INSTRUCTION,
      prompt:
        `School metrics (aggregates only, ${scope} audience):\n${facts.map((f) => `- ${f}`).join("\n")}\n\n` +
        `${PROMPT_CONTRACT}\n` +
        `If the numbers are unremarkable, say so plainly and give routine, proportionate actions.`,
      responseMimeType: "application/json",
      temperature: 0.4,
      maxOutputTokens: 900,
    });

    const parsed = parseLooseJson(result.text);
    const obj = Array.isArray(parsed) ? null : parsed;
    if (!obj || typeof obj !== "object") {
      throw new AiProviderError(result.provider, "model output was not a JSON object");
    }

    const summary = cleanLabel((obj as any).summary, MAX_SUMMARY_CHARS);
    if (!summary) throw new AiProviderError(result.provider, "model returned no summary");

    const actions: string[] = [];
    if (Array.isArray((obj as any).actions)) {
      for (const a of (obj as any).actions) {
        const label = cleanLabel(a, MAX_ACTION_CHARS + 40);
        if (!label) continue;
        const stripped = label
          .replace(/^\s*(?:\d+[.)]\s*|[-*]\s*)/, "")
          .replace(/^["'`\[\]]+/, "")
          .replace(/["'`\]]+$/, "")
          .replace(/\s+/g, " ")
          .trim();
        if (!stripped || stripped.length > MAX_ACTION_CHARS) continue;
        if (actions.includes(stripped)) continue;
        actions.push(stripped);
        if (actions.length >= ACTION_COUNT) break;
      }
    }

    if (actions.length === 0) {
      throw new AiProviderError(result.provider, "no action survived validation");
    }

    return new Response(
      JSON.stringify({
        success: true,
        school_id: sid,
        scope,
        metrics,
        summary,
        actions,
        model: `${result.model}@${result.provider}`,
      }),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (err) {
    if (err instanceof AiUnavailableError) {
      logAiError("ai-school-insights", err);
      return jsonError("ai_unavailable", 503);
    }
    if (err instanceof AiProviderError) {
      logAiError("ai-school-insights", err);
      return jsonError("ai_provider_error", 502);
    }
    console.error("ai-school-insights error:", err);
    return jsonError("server_error", 500);
  }
});

async function rpcBool(
  client: ReturnType<typeof createClient>,
  fn: string,
  args: Record<string, unknown>,
): Promise<boolean> {
  const { data, error } = await client.rpc(fn as any, args as any);
  if (error) {
    console.error(`ai-school-insights: rpc ${fn} failed`, error);
    return false;
  }
  return data === true;
}

/// head:true COUNT against the service role — counts only, no rows returned.
async function countWhere(
  supabase: ReturnType<typeof createClient>,
  table: string,
  filters: Record<string, unknown>,
): Promise<number> {
  let q = supabase.from(table).select("*", { count: "exact", head: true });
  for (const [col, val] of Object.entries(filters)) {
    if (Array.isArray(val)) q = q.in(col, val as string[]);
    else q = q.eq(col, val);
  }
  const { count, error } = await q;
  if (error) {
    console.error(`ai-school-insights: count on ${table} failed`, error);
    return 0;
  }
  return count ?? 0;
}

async function recentConversationScores(supabase: ReturnType<typeof createClient>, schoolId: string) {
  const { data, error } = await supabase
    .from("conversation_scores")
    .select("overall, sentiment, safety_risk, resolution, flagged, topics")
    .eq("school_id", schoolId)
    .order("scored_at", { ascending: false })
    .limit(RECENT_SCORES);
  if (error) {
    console.error("ai-school-insights: conversation_scores query failed", error);
    return [];
  }
  return (data ?? []).map((r: any) => ({
    overall: r.overall === null ? null : Number(r.overall),
    sentiment: r.sentiment === null ? null : Number(r.sentiment),
    safety_risk: r.safety_risk === null ? null : Number(r.safety_risk),
    resolution: r.resolution === null ? null : Number(r.resolution),
    flagged: r.flagged,
    topics: r.topics ?? [],
  }));
}

function fmt(n: number | null): string {
  return n === null ? "no data" : String(n);
}

function jsonError(error: string, status: number) {
  return new Response(JSON.stringify({ success: false, error }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}