// ============================================================
// Edge Function: dispatch-notifications
// Sends FCM push notifications for pending notification jobs
// Server-side only — FCM key never exposed to client
// ============================================================
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const FCM_SERVER_KEY = Deno.env.get("FCM_SERVER_KEY");
const FCM_PROJECT_ID = Deno.env.get("FCM_PROJECT_ID");
const INTERNAL_WEBHOOK_SECRET = Deno.env.get("INTERNAL_WEBHOOK_SECRET")!;

const BATCH_SIZE = 50;

serve(async (req: Request) => {
  // Allow both internal webhook calls and scheduled invocations
  const secret = req.headers.get("x-webhook-secret");
  const isInternal = secret === INTERNAL_WEBHOOK_SECRET;
  const isScheduled = req.headers.get("x-scheduled") === "true";

  if (!isInternal && !isScheduled) {
    return new Response("Unauthorized", { status: 401 });
  }

  if (!FCM_SERVER_KEY && !FCM_PROJECT_ID) {
    console.error("FCM not configured — notifications disabled");
    return new Response(
      JSON.stringify({ error: "FCM not configured", sent: 0 }),
      { status: 503, headers: { "Content-Type": "application/json" } }
    );
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  let body: { school_id?: string } = {};
  try { body = await req.json(); } catch { /* no body */ }

  // Get pending notification jobs
  const query = supabase
    .from("notification_jobs")
    .select("*, notification_devices!inner(fcm_token, is_active)")
    .eq("status", "pending")
    .order("created_at", { ascending: true })
    .limit(BATCH_SIZE);

  if (body.school_id) {
    query.eq("school_id", body.school_id);
  }

  const { data: jobs, error } = await query;

  if (error) {
    console.error("Failed to fetch notification jobs:", error);
    return new Response("DB error", { status: 500 });
  }

  let sent = 0;
  let failed = 0;

  for (const job of jobs ?? []) {
    // Get active FCM tokens for recipient
    const { data: devices } = await supabase
      .from("notification_devices")
      .select("id, fcm_token")
      .eq("user_id", job.recipient_id)
      .eq("is_active", true);

    if (!devices?.length) {
      // No active devices — mark skipped
      await supabase.from("notification_jobs")
        .update({ status: "skipped", sent_at: new Date().toISOString() })
        .eq("id", job.id);
      continue;
    }

    let jobSent = false;
    for (const device of devices) {
      const success = await sendFcmNotification(
        device.fcm_token,
        { title: job.title, body: job.body },
        job.data
      );

      if (success) {
        jobSent = true;
      } else {
        // Token may be stale — deactivate
        await supabase.from("notification_devices")
          .update({ is_active: false })
          .eq("id", device.id);
      }
    }

    if (jobSent) {
      await supabase.from("notification_jobs")
        .update({ status: "sent", sent_at: new Date().toISOString() })
        .eq("id", job.id);
      sent++;
    } else {
      await supabase.from("notification_jobs")
        .update({
          status: "failed",
          failed_at: new Date().toISOString(),
          failure_reason: "All device tokens failed or inactive",
        })
        .eq("id", job.id);
      failed++;
    }
  }

  return new Response(
    JSON.stringify({ success: true, sent, failed }),
    { headers: { "Content-Type": "application/json" } }
  );
});

async function sendFcmNotification(
  token: string,
  notification: { title: string; body: string },
  data: Record<string, unknown>
): Promise<boolean> {
  try {
    // Using FCM v1 API (HTTP v1)
    const payload = {
      message: {
        token,
        notification: {
          title: notification.title,
          body: notification.body,   // Generic — no sensitive content
        },
        data: Object.fromEntries(
          Object.entries(data).map(([k, v]) => [k, String(v)])
        ),
        android: {
          priority: "high",
          notification: {
            channel_id: data.type === "alert" ? "priority_alerts" :
              data.type === "announcement" ? "announcements" : "messages",
            sound: "default",
          },
        },
      },
    };

    const response = await fetch(
      `https://fcm.googleapis.com/v1/projects/${FCM_PROJECT_ID}/messages:send`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${FCM_SERVER_KEY}`,
        },
        body: JSON.stringify(payload),
      }
    );

    if (!response.ok) {
      const errBody = await response.text();
      console.error("FCM send error:", response.status, errBody);
      // Token invalid/expired
      if (response.status === 404 || errBody.includes("UNREGISTERED")) {
        return false; // Signal to deactivate token
      }
      return false;
    }

    return true;
  } catch (err) {
    console.error("FCM send exception:", err);
    return false;
  }
}
