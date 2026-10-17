// ============================================================
// Edge Function: moderate-image
// Server-side image safety classifier — APILayer Nudity Detection
// (https://marketplace.apilayer.com/nudity_detection-api).
//
// The classifier returns a 1–5 score (5 = most likely nude). We fail
// closed: any provider error => quarantined, never approved.
// ============================================================
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const INTERNAL_WEBHOOK_SECRET = Deno.env.get("INTERNAL_WEBHOOK_SECRET")!;

const APILAYER_API_KEY = Deno.env.get("APILAYER_API_KEY");
const APILAYER_BASE = Deno.env.get("APILAYER_NUDITY_URL") ?? "https://api.apilayer.com/nudity_detection";

// Score thresholds (1..5). School context => stricter.
const REJECT_AT = 4;      // >= 4 : reject outright
const QUARANTINE_AT = 3;  // == 3 : hold for human review

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

    if (!APILAYER_API_KEY) {
      verdict = "quarantined";
      scanResult = { error: "APILAYER_API_KEY not configured — image quarantined" };
      console.error("IMAGE SAFETY PROVIDER NOT CONFIGURED. Quarantining:", attachment_id);
    } else {
      const { data: signedUrlData } = await supabase.storage
        .from("attachments")
        .createSignedUrl(attachment.storage_path, 120);

      if (!signedUrlData?.signedUrl) {
        verdict = "quarantined";
        scanResult = { error: "Could not generate signed URL for scanning" };
      } else {
        const result = await classifyImage(signedUrlData.signedUrl);

        if (result.error) {
          verdict = "quarantined";
          scanResult = { error: result.error };
          console.error("Nudity scan failed — quarantining:", attachment_id, result.error);
        } else {
          scanResult = { description: result.description, score: result.value };
          const v = result.value ?? 5;
          if (v >= REJECT_AT) verdict = "rejected";
          else if (v >= QUARANTINE_AT) verdict = "quarantined";
          else verdict = "approved";
        }
      }
    }

    const modVerdict = verdict === "approved" ? "approved" : verdict === "rejected" ? "blocked" : "held";

    await supabase.from("moderation_results").insert({
      school_id,
      attachment_id,
      provider: APILAYER_API_KEY ? "apilayer_nudity" : "none",
      verdict: modVerdict,
      categories: scanResult,
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
      JSON.stringify({ verdict, attachment_status: attachmentStatus }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error("moderate-image error:", err);
    return new Response("Server error", { status: 500 });
  }
});

async function classifyImage(imageUrl: string): Promise<{
  value: number;
  description: string;
  details: Record<string, unknown>;
  error?: string;
}> {
  const base = APILAYER_BASE.replace(/\/$/, "");
  const headers = { apikey: Deno.env.get("APILAYER_API_KEY")! };
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
        return { value: 5, description: "unparseable response", details: data, error: "Unexpected response shape" };
      }
      return { value, description: String(data.description ?? ""), details: data };
    } catch (e) {
      lastError = String((e as Error)?.message ?? e);
    }
  }
  // All attempts failed — fail closed.
  return { value: 5, description: "provider failure", details: {}, error: `Nudity API unavailable: ${lastError}` };
}
