import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const FCM_PROJECT_ID = Deno.env.get("FCM_PROJECT_ID") ?? "";
const FCM_CLIENT_EMAIL = Deno.env.get("FCM_CLIENT_EMAIL") ?? "";
const FCM_PRIVATE_KEY = Deno.env.get("FCM_PRIVATE_KEY") ?? "";
const INTERNAL_WEBHOOK_SECRET = Deno.env.get("INTERNAL_WEBHOOK_SECRET") ?? "";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-webhook-secret, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: CORS_HEADERS });
}

function base64Url(value: string | Uint8Array): string {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : value;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("=", "").replaceAll("+", "-").replaceAll("/", "_");
}

let tokenCache: { value: string; expiresAt: number } | null = null;

async function getAccessToken(): Promise<string> {
  if (tokenCache && tokenCache.expiresAt > Date.now() + 60_000) return tokenCache.value;
  if (!FCM_PROJECT_ID || !FCM_CLIENT_EMAIL || !FCM_PRIVATE_KEY) {
    throw new Error("fcm_credentials_not_configured");
  }

  const now = Math.floor(Date.now() / 1000);
  const header = base64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64Url(JSON.stringify({
    iss: FCM_CLIENT_EMAIL,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const unsigned = header + "." + claims;
  const pem = FCM_PRIVATE_KEY.replaceAll("\\n", "\n")
    .replaceAll("-----BEGIN PRIVATE KEY-----", "")
    .replaceAll("-----END PRIVATE KEY-----", "")
    .replaceAll("\r", "")
    .replaceAll(" ", "")
    .replaceAll("\n", "");
  const der = Uint8Array.from(atob(pem), (character) => character.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  ));
  const assertion = unsigned + "." + base64Url(signature);

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const result = await response.json();
  if (!response.ok || typeof result.access_token !== "string") {
    throw new Error("fcm_oauth_exchange_failed");
  }
  tokenCache = {
    value: result.access_token,
    expiresAt: Date.now() + Math.max(60, Number(result.expires_in) || 3600) * 1000,
  };
  return tokenCache.value;
}

async function sendPush(accessToken: string, token: string, title: string, body: string, data: Record<string, string>) {
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${FCM_PROJECT_ID}/messages:send`,
    {
      method: "POST",
      headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          data,
          android: { priority: "high" },
          apns: { payload: { aps: { sound: "default" } } },
        },
      }),
    },
  );
  const detail = response.ok ? "" : await response.text().catch(() => "");
  return { ok: response.ok, invalidToken: detail.includes("UNREGISTERED") };
}

async function getRecipients(supabase: ReturnType<typeof createClient>, announcement: any): Promise<string[]> {
  const schoolId = String(announcement.school_id);
  if (announcement.audience_type === "custom") {
    const { data, error } = await supabase
      .from("announcement_recipients")
      .select("user_id")
      .eq("announcement_id", announcement.id);
    if (error) throw new Error("custom_recipient_lookup_failed");
    return [...new Set((data ?? []).map((row: any) => row.user_id))];
  }

  if (announcement.audience_type === "class") {
    if (!announcement.class_id) return [];
    const { data, error } = await supabase
      .from("class_enrollments")
      .select("students!inner(user_id)")
      .eq("school_id", schoolId)
      .eq("class_id", announcement.class_id)
      .is("unenrolled_at", null);
    if (error) throw new Error("class_recipient_lookup_failed");
    return [...new Set((data ?? []).map((row: any) => row.students?.user_id).filter((id: unknown) => typeof id === "string"))];
  }

  let query = supabase
    .from("school_memberships")
    .select("user_id, role")
    .eq("school_id", schoolId)
    .eq("is_active", true);

  if (announcement.audience_type === "staff") {
    query = query.in("role", ["teacher", "head_teacher", "school_admin", "principal", "platform_owner"]);
  } else if (announcement.audience_type === "leadership") {
    query = query.in("role", ["school_admin", "principal", "platform_owner"]);
  } else if (announcement.audience_type !== "school_wide") {
    return [];
  }

  const { data, error } = await query;
  if (error) throw new Error("school_recipient_lookup_failed");
  return [...new Set((data ?? []).map((row: any) => row.user_id))];
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ success: false, error: "method_not_allowed" }, 405);

  const authorization = req.headers.get("Authorization") ?? "";
  const bearerSecret = authorization.replace(/^Bearer\\s+/i, "");
  const webhookSecret = req.headers.get("x-webhook-secret") ?? "";
  if (!INTERNAL_WEBHOOK_SECRET ||
      (bearerSecret !== INTERNAL_WEBHOOK_SECRET && webhookSecret !== INTERNAL_WEBHOOK_SECRET)) {
    return json({ success: false, error: "unauthorized" }, 401);
  }

  let requestBody: { school_id?: string } = {};
  try {
    requestBody = await req.json();
  } catch {
    return json({ success: false, error: "invalid_body" }, 400);
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  let jobsQuery = supabase
    .from("background_jobs")
    .select("id, payload, attempts, max_attempts")
    .eq("type", "dispatch-notifications")
    .in("status", ["queued", "retrying"])
    .lte("scheduled_for", new Date().toISOString())
    .order("scheduled_for", { ascending: true })
    .limit(50);
  if (requestBody.school_id) jobsQuery = jobsQuery.eq("payload->>school_id", requestBody.school_id);

  const { data: jobs, error: jobsError } = await jobsQuery;
  if (jobsError) return json({ success: false, error: "queue_read_failed" }, 500);
  if (!jobs?.length) return json({ success: true, processed: 0, sent: 0, failed: 0 });

  let processed = 0;
  let sent = 0;
  let failed = 0;

  for (const job of jobs) {
    const { data: claimed, error: claimError } = await supabase
      .from('background_jobs')
      .update({ status: 'running', started_at: new Date().toISOString() })
      .eq('id', job.id)
      .in('status', ['queued', 'retrying'])
      .select('id')
      .maybeSingle();
    if (claimError) {
      failed += 1;
      continue;
    }
    if (!claimed) continue;

    try {
      const payload = typeof job.payload === "string" ? JSON.parse(job.payload) : job.payload;
      const announcementId = payload?.announcement_id;
      const schoolId = payload?.school_id;
      if (typeof announcementId !== "string") throw new Error("announcement_id_missing");
      if (typeof schoolId !== "string") throw new Error("school_id_missing");

      const { data: announcement, error: announcementError } = await supabase
        .from("announcements")
        .select("id, school_id, title, body, audience_type, class_id, is_published")
        .eq("id", announcementId)
        .eq("school_id", schoolId)
        .maybeSingle();
      if (announcementError || !announcement || announcement.is_published !== true) {
        throw new Error("announcement_unavailable");
      }

      const recipientIds = await getRecipients(supabase, announcement);
      if (recipientIds.length) {
        const { error } = await supabase.from("announcement_recipients").upsert(
          recipientIds.map((userId) => ({ announcement_id: announcement.id, user_id: userId })),
          { onConflict: "announcement_id,user_id", ignoreDuplicates: true },
        );
        if (error) throw new Error("recipient_write_failed");
      }

      const { data: devices, error: devicesError } = recipientIds.length
        ? await supabase
            .from("notification_devices")
            .select("id, user_id, fcm_token")
            .eq("school_id", schoolId)
            .eq("is_active", true)
            .in("user_id", recipientIds)
        : { data: [], error: null };
      if (devicesError) throw new Error("device_lookup_failed");

      const accessToken = devices?.length ? await getAccessToken() : null;
      const successfulUsers = new Set<string>();

      const deviceList = devices ?? [];
      for (let offset = 0; offset < deviceList.length; offset += 20) {
        const batch = deviceList.slice(offset, offset + 20);
        await Promise.all(batch.map(async (device) => {
          try {
            const idempotencyKey = `${announcement.id}:${device.id}`;
            const { data: existing } = await supabase
              .from("notification_jobs")
              .select("id, status")
              .eq("idempotency_key", idempotencyKey)
              .maybeSingle();

            if (existing?.status === "sent") {
              successfulUsers.add(device.user_id);
              return;
            }

            const result = await sendPush(
              accessToken!,
              device.fcm_token,
              announcement.title,
              announcement.body.slice(0, 180),
              {
                type: "announcement",
                announcement_id: announcement.id,
                route: `announcement:${announcement.id}`,
              },
            );

            const values = {
              school_id: schoolId,
              recipient_id: device.user_id,
              device_id: device.id,
              type: "announcement",
              title: announcement.title,
              body: announcement.body.slice(0, 180),
              data: { announcement_id: announcement.id, route: `announcement:${announcement.id}` },
              status: result.ok ? "sent" : "failed",
              sent_at: result.ok ? new Date().toISOString() : null,
              failed_at: result.ok ? null : new Date().toISOString(),
              failure_reason: result.ok ? null : "fcm_delivery_failed",
              idempotency_key: idempotencyKey,
            };
            const write = existing
              ? await supabase.from("notification_jobs").update(values).eq("id", existing.id)
              : await supabase.from("notification_jobs").insert(values);
            if (write.error) throw new Error("notification_log_failed");

            if (result.invalidToken) {
              await supabase.from("notification_devices").update({ is_active: false }).eq("id", device.id);
            }
            if (result.ok) {
              successfulUsers.add(device.user_id);
              sent += 1;
            } else {
              failed += 1;
            }
          } catch (error) {
            failed += 1;
            console.error("Notification device delivery failed:", error);
          }
        }));
      }

      for (const userId of recipientIds) {
        const delivered = successfulUsers.has(userId);
        await supabase
          .from("announcement_recipients")
          .update({
            notified_at: delivered ? new Date().toISOString() : null,
            notification_failed: !delivered,
          })
          .eq("announcement_id", announcement.id)
          .eq("user_id", userId);
      }

      await supabase
        .from("background_jobs")
        .update({ status: "completed", completed_at: new Date().toISOString(), last_error: null })
        .eq("id", job.id);
      processed += 1;
    } catch (error) {
      failed += 1;
      const attempts = (job.attempts ?? 0) + 1;
      const retry = attempts < (job.max_attempts ?? 3);
      await supabase
        .from("background_jobs")
        .update({
          status: retry ? "retrying" : "failed",
          last_error: error instanceof Error ? error.message : "dispatch_failed",
          attempts,
          scheduled_for: new Date(Date.now() + (retry ? 60_000 : 0)).toISOString(),
        })
        .eq("id", job.id);
    }
  }

  return json({ success: true, processed, sent, failed });
});
