// ============================================================
// Edge Function: moderate-image
// Moderates images via AI provider
// ============================================================
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY")!;
const GOOGLE_CLOUD_VISION_API_KEY = Deno.env.get("GOOGLE_CLOUD_VISION_API_KEY")!;
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

  let body: { attachment_id?: string; school_id?: string } = {};
  try { body = await req.json(); } catch { return jsonError("invalid_body", 400); }

  const { attachment_id, school_id } = body;
  if (!attachment_id) return jsonError("missing_attachment_id", 400);

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  const { data: attachment } = await supabase
    .from("attachments")
    .select("storage_path, school_id, mime_type")
    .eq("id", attachment_id)
    .single();

  if (!attachment) return jsonError("attachment_not_found", 404);

  if (school_id && attachment.school_id !== school_id) {
    return jsonError("forbidden", 403);
  }

  let verdict: "approved" | "warned" | "held" | "blocked" | "escalated" = "approved";
  let confidence = 1.0;

  // Moderate via OpenAI Vision or Google Cloud Vision
  if (OPENAI_API_KEY) {
    try {
      // Get the signed URL for the image
      const { data: signedUrl } = await supabase.storage
        .from("attachments")
        .createSignedUrl(attachment.storage_path, 300);

      if (signedUrl) {
        const resp = await fetch("https://api.openai.com/v1/moderations", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "Authorization": `Bearer ${OPENAI_API_KEY}`,
          },
          body: JSON.stringify({
            input: [{ type: "image_url", image_url: { url: signedUrl } }],
            model: "omni-moderation-latest",
          }),
        });
        if (resp.ok) {
          const result = await resp.json();
          const result0 = result.results?.[0];
          if (result0 && result0.flagged) {
            verdict = result0.category_scores.sexual > 0.7 || result0.category_scores.violence > 0.7
              ? "blocked"
              : "held";
          }
          confidence = Math.max(
            result0.category_scores.sexual,
            result0.category_scores.violence,
            result0.category_scores.harassment,
            result0.category_scores.hate
          );
        }
      }
    } catch {
      verdict = "held";
    }
  } else if (GOOGLE_CLOUD_VISION_API_KEY) {
    try {
      const { data: signedUrl } = await supabase.storage
        .from("attachments")
        .createSignedUrl(attachment.storage_path, 300);

      if (signedUrl) {
        const resp = await fetch(`https://vision.googleapis.com/v1/images:annotate?key=${GOOGLE_CLOUD_VISION_API_KEY}`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            requests: [{
              image: { source: { image_uri: signedUrl } },
              features: [{ type: "SAFE_SEARCH_DETECTION" }],
            }],
          }),
        });
        if (resp.ok) {
          const result = await resp.json();
          const annotation = result.responses?.[0]?.safeSearchAnnotation;
          if (annotation) {
            const adult = (annotation.adult || "UNKNOWN").toUpperCase();
            const violence = (annotation.violence || "UNKNOWN").toUpperACE();
            const racy = (annotation.racy || "UNKNOWN").toUpperACE();
            if (adult === "VERY_LIKELY" || violence === "VERY_LIKELY" || racy === "VERY_LIKELY") {
              verdict = "blocked";
            } else if (adult === "LIKELY" || violence === "LIKELY" || racy === "LIKELY") {
              verdict = "held";
            }
            confidence = 0.8;
          }
        }
      }
    } catch {
      verdict = "held";
    }
  }

  // Update attachment status
  const newStatus = verdict === "blocked" ? "rejected" : verdict === "held" ? "quarantined" : "approved";
  const { error: updateError } = await supabase
    .from("attachments")
    .update({ status: newStatus, updated_at: new Date().toISOString() })
    .eq("id", attachment_id);

  if (updateError) {
    return jsonError("update_failed", 500);
  }

  // Log moderation event
  await supabase.from("moderation_events").insert({
    school_id: attachment.school_id,
    attachment_id,
    verdict,
    provider: OPENAI_API_KEY ? "openai" : "google_vision",
    confidence,
    categories: {},
    created_at: new Date().toISOString(),
  });

  return new Response(JSON.stringify({
    success: true,
    verdict,
    confidence,
    provider: OPENAI_API_KEY ? "openai" : "google_vision",
  }), { status: 200, headers: { "Content-Type": "application/json" } });
});