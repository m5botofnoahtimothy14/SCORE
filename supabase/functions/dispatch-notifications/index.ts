// ============================================================
// Edge Function: dispatch-notifications
// Sends queued school-announcement notifications through FCM.
// Uses a service credential to obtain a real Google OAuth token.
// ============================================================
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
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

function jsonError(code: string, status = 400) {
  return new Response(JSON.stringify({ success: false, error: code }), {
    status,
    headers: CORS_HEADERS,
  });
}

function jsonOk(data: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify({ success: true, ...data }), {
    status,
    headers: CORS_HEADERS,
  });
}

function base64Url(value: string | Uint8Array): string {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : value;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

let cachedAccessToken: { token: string; expiresAt: number } | null = null;

async function getFCMAccessToken(): Promise<string> {
  if (cachedAccessToken && cachedAccessToken.expiresAt > Date.now() + 60_000) {
    return cachedAccessToken.token;
  }
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

  const pem = FCM_PRIVATE_KEY.replace(/\\n/g, "\n")
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const der = Uint8Array.from(atob(pem), (character) => character.charCodeAt(0));
  const privateKey = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    privateKey,
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
  const payload = await response.json();
  if (!response.ok || typeof payload.access_token !== "string") {
    throw new Error("fcm_oauth_exchange_failed");
  }

  cachedAccessToken = {
    token: payload.access_token,
    expiresAt: Date.now() + Math.max(60, Number(payload.expires_in) || 3600) * 1000,
  };
  return cachedAccessToken.token;
}

async function sendFCM(
  accessToken: string,
  token: string,
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<{ ok: boolean; invalidToken: boolean }> {
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${FCM_PROJECT_ID}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
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

  if (response.ok) return { ok: true, invalidToken: false };
  const detail = await response.text().catch(() => "");
  return {
    ok: false,
    invalidToken: detail.includes("UNREGISTERED"),
  };
}

async function resolveRecipientIds(
  supabase: ReturnType<typeof createClient>,
  announcement: Record<string, unknown>,
): Promise<string[]> {
  const schoolId = String(announcement.school_id);
  const audience = String(announcement.audience_type);
  let ids: string[] = [];

  if (audience === "custom") {
    const { data } = await supabase
      .from("announcement_recipients")
      .select("user_id")
      .eq("announcement_id", announcement.id);
    ids = (data ?? []).map((row: { user_id: string }) => row.user_id);
  } else if (audience === "class") {
    if (typeof announcement.class_id !== "string" || !announcement.class_id) return [];
    const { data, error } = await supabase
      .from("class_enrollments")
      .select("students!inner(user_id)")
      .eq("school_id", schoolId)
      .eq("class_id", announcement.class_id)
      .is("unenrolled_at", null);
    if (error) throw new Error("class_recipient_lookup_failed");
    ids = (data ?? [])
      .map((row: any) => row.students?.user_id)
      .filter((value: unknown): value is string => typeof value === "string");
  } else {
    let query = supabase
      .from("school_memberships")
      .select("user_id, role")
      .eq("school_id", schoolId)
      .eq("is_active", true);

    if (audience === "staff") {
      query = query.in("role", ["teacher", "head_teacher", "school_admin", "principal", "platform_owner"]);
    } else if (audience === "leadership") {
      query = query.in("role", ["school_admin", "principal", "platform_owner"]);
    } else if (audience !== "school_wide") {
      return [];
    }

    const { data, error } = await query;
    if (error) throw new Error("school_recipient_lookup_failed");
    ids = (data ?? []).map((row: { user_id: string }) => row.user_id);
  }

  return [...new Set(ids)];
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") return jsonError("method_not_allowed", 405);

  const authHeader = req.headers.get("Authorization");
  if (!INTERNAL_WEBHOOK_SECRET || authHeader !== `Bearer ${INTERNAL_WEBHOOK_SECRET}`) {
    return jsonError("unauthorized", 401);
  }

  let body: { school_id?: string } = {};
  try {
    body = await req.json();
  } catch {
    return jsonError("invalid_body", 400);
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  let query = supabase
    .from("background_jobs")
    .select("id, school_id, payload, attempts")
    .eq("type", "dispatch-notifications")
    .eq("status", "queued")
    .lte("scheduled_for", new Date().toISOString())
    .order("scheduled_for", { ascending: true })
    .limit(50);

  if (body.school_id) query = query.eq("school_id", body.school_id);

  const { data: jobs, error: jobsError } = await query;
  if (jobsError) return jsonError("queue_read_failed", 500);
  if (!jobs?.length) return jsonOk({ processed: 0, sent: 0, failed: 0 });

  let processed = 0;
  let sent = 0;
  let failed = 0;

  for (const job of jobs) {
    try {
      const payload = typeof job.payload === "string" ? JSON.parse(job.payload) : job.payload;
      const announcementId = payload?.announcement_id;
      if (typeof announcementId !== "string") throw new Error("announcement_id_missing");

      const { data: announcement, error: announcementError } = await supabase
        .from("announcements")
        .select("id, school_id, title, body, audience_type, class_id, is_published")
        .eq("id", announcementId)
        .eq("school_id", job.school_id)
        .maybeSingle();

      if (announcementError || !announcement || announcement.is_published !== true) {
        throw new Error("announcement_unavailable");
      }

      const recipientIds = await resolveRecipientIds(supabase, announcement);
      if (recipientIds.length > 0) {
        const recipientRows = recipientIds.map((userId) => ({
          announcement_id: announcement.id,
          user_id: userId,
        }));
        const { error: recipientWriteError } = await supabase
          .from("announcement_recipients")
          .upsert(recipientRows, {
            onConflict: "announcement_id,user_id",
            ignoreDuplicates: true,
          });
        if (recipientWriteError) throw new Error("recipient_write_failed");
      }

      const { data: devices, error: deviceError } = recipientIds.length
        ? await supabase
            .from("notification_devices")
            .select("id, user_id, fcm_token")
            .eq("school_id", job.school_id)
            .eq("is_active", true)
            .in("user_id", recipientIds)
        : { data: [], error: null };

      if (deviceError) throw new Error("device_lookup_failed");

      let accessToken: string | null = null;
      if ((devices ?? []).length > 0) accessToken = await getFCMAccessToken();

      const successUsers = new Set<string>();

      for (const device of devices ?? []) {
        const result = await sendFCM(
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

        const status = result.ok ? "sent" : "failed";
        const { error: logError } = await supabase.from("notification_jobs").insert({
          school_id: job.school_id,
          recipient_id: device.user_id,
          device_id: device.id,
          type: "announcement",
          title: announcement.title,
          body: announcement.body.slice(0, 180),
          data: { announcement_id: announcement.id, route: `announcement:${announcement.id}` },
          status,
          sent_at: result.ok ? new Date().toISOString() : null,
          failed_at: result.ok ? null : new Date().toISOString(),
          failure_reason: result.ok ? null : "fcm_delivery_failed",
          idempotency_key: idempotencyKey,
        };
        const logWrite = existingLog
          ? await supabase.from("notification_jobs").update(logValues).eq("id", existingLog.id)
          : await supabase.from("notification_jobs").insert(logValues);
        if (logWrite.error) throw new Error("notification_log_failed");

        if (result.invalidToken) {
          await supabase.from("notification_devices").update({ is_active: false }).eq("id", device.id);
        }
        if (result.ok) {
          successUsers.add(device.user_id);
          sent += 1;
        } else {
          failed += 1;
        }
      }

      const noDeviceUsers = recipientIds.filter((id) => !devices?.some((device) => device.user_id === id));
      if (noDeviceUsers.length > 0) {
        // Recipients without a registered device remain unnotified.
      }

      for (const userId of recipientIds) {
        const delivered = successUsers.has(userId);
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
        .update({
          status: "completed",
          completed_at: new Date().toISOString(),
          last_error: null,
        })
        .eq("id", job.id);

      processed += 1;
    } catch (error) {
      failed += 1;
      await supabase
        .from("background_jobs")
        .update({
          status: "failed",
          last_error: error instanceof Error ? error.message : "dispatch_failed",
          attempts: (job.attempts ?? 0) + 1,
        })
        .eq("id", job.id);
    }
  }

  return jsonOk({ processed, sent, failed });
});
