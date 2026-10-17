// ============================================================
// Edge Function: moderate-image
// Server-side image safety classification — Google Cloud Vision
// ============================================================
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const GOOGLE_CLOUD_VISION_API_KEY = Deno.env.get("GOOGLE_CLOUD_VISION_API_KEY");
const INTERNAL_WEBHOOK_SECRET = Deno.env.get("INTERNAL_WEBHOOK_SECRET")!;

// Google Vision likelihood levels
const LIKELIHOOD_MAP: Record<string, number> = {
  "UNKNOWN": 0,
  "VERY_UNLIKELY": 0.05,
  "UNLIKELY": 0.2,
  "POSSIBLE": 0.5,
  "LIKELY": 0.8,
  "VERY_LIKELY": 0.95,
};

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

    // Get attachment record
    const { data: attachment } = await supabase
      .from("attachments")
      .select("*")
      .eq("id", attachment_id)
      .eq("status", "pending_scan")
      .single();

    if (!attachment) {
      return new Response("Attachment not found or not pending scan", { status: 200 });
    }

    // Only scan images
    if (attachment.type !== "image") {
      await supabase.from("attachments").update({ status: "approved", scanned_at: new Date().toISOString() }).eq("id", attachment_id);
      return new Response(JSON.stringify({ verdict: "approved" }), { headers: { "Content-Type": "application/json" } });
    }

    let verdict: string;
    let scanResult: Record<string, unknown> = {};

    if (!GOOGLE_CLOUD_VISION_API_KEY) {
      // CRITICAL: Image safety provider not configured
      // MUST quarantine — cannot approve unscanned images
      verdict = "quarantined";
      scanResult = { error: "GOOGLE_CLOUD_VISION_API_KEY not configured — image quarantined" };
      console.error("IMAGE SAFETY PROVIDER NOT CONFIGURED. Quarantining:", attachment_id);
    } else {
      // Get signed URL for the private image
      const { data: signedUrlData } = await supabase.storage
        .from("attachments")
        .createSignedUrl(attachment.storage_path, 60); // 60 second expiry

      if (!signedUrlData?.signedUrl) {
        verdict = "quarantined";
        scanResult = { error: "Could not generate signed URL for scanning" };
      } else {
        const result = await classifyImageWithVision(signedUrlData.signedUrl);

        if (result.error) {
          // Provider failed — quarantine, do NOT approve
          verdict = "quarantined";
          scanResult = { error: result.error };
          console.error("Google Vision failed — quarantining image:", attachment_id, result.error);
        } else {
          scanResult = result.details;

          // Decision logic
          const adultScore = result.adult;
          const violenceScore = result.violence;
          const racyScore = result.racy;

          if (adultScore >= 0.8 || violenceScore >= 0.8) {
            verdict = "rejected";
          } else if (adultScore >= 0.5 || violenceScore >= 0.5 || racyScore >= 0.8) {
            verdict = "quarantined";
          } else {
            verdict = "approved";
          }
        }
      }
    }

    // Save moderation result
    const modVerdict = verdict === "approved" ? "approved" : verdict === "rejected" ? "blocked" : "held";

    await supabase.from("moderation_results").insert({
      school_id,
      attachment_id,
      provider: GOOGLE_CLOUD_VISION_API_KEY ? "google_vision" : "none",
      verdict: modVerdict,
      categories: scanResult,
      processed_at: new Date().toISOString(),
    });

    // Update attachment status
    const attachmentStatus = verdict === "approved" ? "approved" :
      verdict === "rejected" ? "rejected" : "quarantined";

    await supabase.from("attachments")
      .update({
        status: attachmentStatus,
        scan_result: scanResult,
        scanned_at: new Date().toISOString(),
      })
      .eq("id", attachment_id);

    // Create review case for quarantined/rejected
    if (attachmentStatus !== "approved") {
      await supabase.from("moderation_review_cases").insert({
        school_id,
        status: "pending",
        reason_code: verdict,
      });
    }

    // If approved, notify message sender attachment is ready
    if (attachmentStatus === "approved" && attachment.message_id) {
      await supabase.from("messages")
        .update({ status: "approved" })
        .eq("id", attachment.message_id)
        .eq("status", "pending_moderation");
    }

    return new Response(
      JSON.stringify({ verdict, attachment_status: attachmentStatus }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error("moderate-image error:", err);
    return new Response("Server error", { status: 500 });
  }
});

async function classifyImageWithVision(imageUrl: string): Promise<{
  adult: number;
  violence: number;
  racy: number;
  details: Record<string, unknown>;
  error?: string;
}> {
  try {
    const response = await fetch(
      `https://vision.googleapis.com/v1/images:annotate?key=${GOOGLE_CLOUD_VISION_API_KEY}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          requests: [{
            image: { source: { imageUri: imageUrl } },
            features: [{ type: "SAFE_SEARCH_DETECTION" }],
          }],
        }),
      }
    );

    if (!response.ok) {
      return { adult: 1, violence: 1, racy: 1, details: {}, error: `Vision API error: ${response.status}` };
    }

    const data = await response.json();
    const safeSearch = data.responses?.[0]?.safeSearchAnnotation;

    if (!safeSearch) {
      return { adult: 1, violence: 1, racy: 1, details: {}, error: "No safe search result" };
    }

    return {
      adult: LIKELIHOOD_MAP[safeSearch.adult] ?? 1,
      violence: LIKELIHOOD_MAP[safeSearch.violence] ?? 1,
      racy: LIKELIHOOD_MAP[safeSearch.racy] ?? 1,
      details: safeSearch,
    };
  } catch (err) {
    return { adult: 1, violence: 1, racy: 1, details: {}, error: String(err) };
  }
}
