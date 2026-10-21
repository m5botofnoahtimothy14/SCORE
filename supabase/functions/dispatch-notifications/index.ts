// ============================================================
// Edge Function: dispatch-notifications
// Sends FCM (HTTP v1) push notifications for pending notification jobs.
// Auth uses the Firebase service-account (FCM_PROJECT_ID / FCM_CLIENT_EMAIL /
// FCM_PRIVATE_KEY) — no legacy server key. Server-side only.
// ============================================================
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SUPABASE_SECRET_KEY = Deno.env.get("SUPABASE_SECRET_KEYS") ?? "";
const FCM_PROJECT_ID = Deno.env.get("FCM_PROJECT_ID");
const FCM_CLIENT_EMAIL = Deno.env.get("FCM_CLIENT_EMAIL");
const FCM_PRIVATE_KEY = Deno.env.get("FCM_PRIVATE_KEY");
const INTERNAL_WEBHOOK_SECRET = Deno.env.get("INTERNAL_WEBHOOK_SECRET")!;

const BATCH_SIZE = 50;
const TOKEN_URL = "https://oauth2.googleapis.com/token";
const SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

let cachedToken: string | null = null;
let cachedTokenExp = 0;

serve(async (req: Request) => {
  const secret = req.headers.get("x-webhook-secret");
  const isInternal = secret === INTERNAL_WEBHOOK_SECRET;
  const isScheduled = req.headers.get("x-scheduled") === "true";
  // Service-role callers (e.g. the DMS server) are trusted implicitly.
  // Supabase issues two shapes of service credential — the legacy
  // `role=service_role` JWT and the newer `sb_secret_…` key — so accept
  // whichever this project is configured with.
  const auth = req.headers.get("authorization") ?? "";
  const bearer = auth.startsWith("Bearer ") ? auth.slice(7) : "";
  const isServiceRole =
    bearer !== "" &&
    (bearer === SUPABASE_SERVICE_ROLE_KEY || bearer === SUPABASE_SECRET_KEY);

  if (!isInternal && !isScheduled && !isServiceRole) {
    return new Response("Unauthorized", { status: 401 });
  }

  if (!FCM_PROJECT_ID || !FCM_CLIENT_EMAIL || !FCM_PRIVATE_KEY) {
    console.error("FCM not configured — notifications disabled");
    return new Response(
      JSON.stringify({ error: "FCM not configured", sent: 0 }),
      { status: 503, headers: { "Content-Type": "application/json" } }
    );
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  let body: { school_id?: string } = {};
  try { body = await req.json(); } catch { /* no body */ }

  const query = supabase
    .from("notification_jobs")
    .select("*")
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

  let accessToken = "";
  try {
    accessToken = await getAccessToken();
  } catch (e) {
    const detail = e instanceof Error ? e.message : String(e);
    console.error("FCM token error:", detail);
    return new Response(
      JSON.stringify({ error: "FCM auth failed", detail, sent: 0 }),
      { status: 502, headers: { "Content-Type": "application/json" } }
    );
  }

  let sent = 0;
  let failed = 0;

  for (const job of jobs ?? []) {
    const { data: devices } = await supabase
      .from("notification_devices")
      .select("id, fcm_token")
      .eq("user_id", job.recipient_id)
      .eq("is_active", true);

    if (!devices?.length) {
      await supabase.from("notification_jobs")
        .update({ status: "skipped", sent_at: new Date().toISOString() })
        .eq("id", job.id);
      continue;
    }

    let jobSent = false;
    let lastError = "All device tokens failed or inactive";
    for (const device of devices) {
      const result = await sendFcmNotification(
        accessToken,
        device.fcm_token,
        { title: job.title, body: job.body },
        job.data
      );

      if (result.ok) {
        jobSent = true;
      } else {
        lastError = result.error;
        // An invalid/unregistered token will never work again — retire it.
        // Transient failures keep the device so it can receive later pushes.
        if (result.permanent) {
          await supabase.from("notification_devices")
            .update({ is_active: false })
            .eq("id", device.id);
        }
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
          failure_reason: lastError,
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
  accessToken: string,
  token: string,
  notification: { title: string; body: string },
  data: Record<string, unknown>
): Promise<{ ok: boolean; error: string; permanent: boolean }> {
  try {
    const payload = {
      message: {
        token,
        notification: {
          title: notification.title,
          body: notification.body,   // Generic — no sensitive content
        },
        data: Object.fromEntries(
          Object.entries(data ?? {}).map(([k, v]) => [k, String(v)])
        ),
        android: {
          priority: "high",
          notification: {
            channel_id: data?.type === "alert" ? "priority_alerts" :
              data?.type === "announcement" ? "announcements" : "messages",
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
          "Authorization": `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(payload),
      }
    );

    if (response.status === 401) {
      // Token may have expired mid-batch — refresh once.
      cachedToken = null;
      console.error("FCM 401 — access token rejected; will refresh on next run.");
      return { ok: false, error: "FCM auth failed (401)", permanent: false };
    }
    if (!response.ok) {
      const body = await response.text();
      console.error(`FCM HTTP ${response.status}: ${body.slice(0, 300)}`);
      // 404/403 UNREGISTERED means the token is dead for good.
      const permanent = response.status === 404 ||
        body.includes('UNREGISTERED') ||
        body.includes('INVALID_ARGUMENT');
      return {
        ok: false,
        error: `FCM ${response.status}: ${body.slice(0, 200)}`,
        permanent,
      };
    }
    return { ok: true, error: '', permanent: false };
  } catch (err) {
    console.error("FCM send error:", err);
    return { ok: false, error: `FCM network error: ${String(err)}`, permanent: false };
  }
}

// ---- OAuth2 access token from the service account (RS256 JWT) ----

async function getAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedTokenExp > now + 60) return cachedToken;

  const header = { alg: "RS256", typ: "JWT" };
  const claims = {
    iss: FCM_CLIENT_EMAIL,
    scope: SCOPE,
    aud: TOKEN_URL,
    iat: now,
    exp: now + 3600,
  };
  const signingInput = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(claims))}`;

  const key = await importPrivateKey(FCM_PRIVATE_KEY!);
  const signature = await crypto.subtle.sign(
    { name: "RSASSA-PKCS1-v1_5" },
    key,
    new TextEncoder().encode(signingInput)
  );
  const jwt = `${signingInput}.${b64urlBytes(new Uint8Array(signature))}`;

  const res = await fetch(TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!res.ok) throw new Error(`token endpoint ${res.status}: ${await res.text()}`);
  const data = await res.json();
  cachedToken = data.access_token;
  cachedTokenExp = now + (data.expires_in ?? 3600);
  return cachedToken!;
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const normalized = pem.replace(/\\n/g, "\n");
  const body = normalized
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );
}

function b64url(s: string): string {
  return b64urlBytes(new TextEncoder().encode(s));
}
function b64urlBytes(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
