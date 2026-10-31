// ============================================================
// Edge Function: moderate-message
// Moderates text messages via AI provider
// ============================================================
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY")!;
const INTERNAL_WEBHOOK_SECRET = Deno.env.get("INTERNAL_WEBHOOK_SECRET")!;

function jsonError(code: string, status = 400) {
  return new Response(JSON.stringify({ success: false, error: code }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, content-type",
      },
    });
  }

  if (req.method !== "POST") {
    return jsonError("method_not_allowed", 405);
  }

  const authHeader = req.headers.get("Authorization");
  if (authHeader !== `Bearer ${INTERNAL_WEBHOOK_SECRET}`) {
    return jsonError("unauthorized", 401);
  }

  let body: { message_id?: string; school_id?: string } = {};
  try { body = await req.json(); } catch { return jsonError("invalid_body", 400); }

  const { message_id, school_id } = body;
  if (!message_id) return jsonError("missing_message_id", 400);

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  const { data: message } = await supabase
    .from("messages")
    .select("body, school_id")
    .eq("id", message_id)
    .single();

  if (!message) return jsonError("message_not_found", 404);

  if (school_id && message.school_id !== school_id) {
    return jsonError("forbidden", 403);
  }

  // Moderate via OpenAI
  let verdict: "approved" | "warned" | "held" | "blocked" | "escalated" = "approved";
  let confidence = 1.0;
  let categories: Record<string, number> = {};

  if (OPENAI_API_KEY && message.body) {
    try {
      const resp = await fetch("https://api.openai.com/v1/moderations", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${OPENAI_API_KEY}`,
        },
        body: JSON.stringify({
          input: message.body,
          model: "omni-moderation-latest",
        }),
      });
      if (resp.ok) {
        const result = await resp.json();
        const result0 = result.results?.[0];
        if (result0) {
          if (result0.flagged) {
            verdict = result0.category_scores.harassment > 0.7 || result0.category_scores.hate > 0.7 || result0.category_scores.violence > 0.7 || result0.category_scores.sexual > 0.7
              ? "blocked"
              : "held";
          }
          confidence = Math.max(
            result0.category_scores.harassment,
            result0.category_scores.hate,
            result0.category_scores.violence,
            result0.category_scores.sexual,
            result0.category_scores.self_harm
          );
          categories = result0.category_scores;
        }
      }
    } catch {
      verdict = "held";
    }
  }

  // Update message status
  const { error: updateError } = await supabase
    .from("messages")
    .update({ status: verdict, updated_at: new Date().toISOString() })
    .eq("id", message_id);

  if (updateError) {
    return jsonError("update_failed", 500);
  }

  // Log moderation event
  await supabase.from("moderation_events").insert({
    school_id: message.school_id,
    message_id,
    verdict,
    provider: "openai",
    confidence,
    categories,
    created_at: new Date().toISOString(),
  });

  return new Response(JSON.stringify({
    success: true,
    verdict,
    confidence,
    categories,
    provider: "openai",
  }), { status: 200, headers: { "Content-Type": "application/json" } });
});