// Google Workspace OAuth connection for a school.
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const GOOGLE_CLIENT_ID = Deno.env.get("GOOGLE_CLIENT_ID") ?? "";
const GOOGLE_CLIENT_SECRET = Deno.env.get("GOOGLE_CLIENT_SECRET") ?? "";
const GOOGLE_REDIRECT_URI = Deno.env.get("GOOGLE_REDIRECT_URI") ?? "";
const GOOGLE_OAUTH_STATE_SECRET = Deno.env.get("GOOGLE_OAUTH_STATE_SECRET") ?? "";
const SCORE_ADMIN_URL = Deno.env.get("SCORE_ADMIN_URL") ?? "";

const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
  "Content-Type": "application/json",
};

function json(data: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(data), { status, headers });
}

function b64url(bytes: Uint8Array | string): string {
  const value = typeof bytes === "string" ? new TextEncoder().encode(bytes) : bytes;
  let binary = "";
  for (const byte of value) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function fromB64url(value: string): Uint8Array {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized + "=".repeat((4 - normalized.length % 4) % 4);
  return Uint8Array.from(atob(padded), (character) => character.charCodeAt(0));
}

async function sign(value: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(GOOGLE_OAUTH_STATE_SECRET),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return b64url(new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(value))));
}

async function verifyState(state: string): Promise<{ school_id: string; actor_id: string; exp: number } | null> {
  const [payload, signature] = state.split(".");
  if (!payload || !signature || !GOOGLE_OAUTH_STATE_SECRET) return null;
  const expected = await sign(payload);
  if (expected !== signature) return null;
  try {
    const value = JSON.parse(new TextDecoder().decode(fromB64url(payload)));
    if (!value.school_id || !value.actor_id || Number(value.exp) < Math.floor(Date.now() / 1000)) return null;
    return value;
  } catch {
    return null;
  }
}

function adminRedirect(result: string): Response {
  const base = SCORE_ADMIN_URL.replace(/\/$/, "");
  if (!base.startsWith("https://") && !base.startsWith("http://localhost")) {
    return new Response("Google Workspace connection could not be completed. Contact your SCORE+ administrator.", { status: 500 });
  }
  return Response.redirect(`${base}/dashboard/mentor-desk/google-workspace?${result}`, 303);
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers });
  if (!GOOGLE_CLIENT_ID || !GOOGLE_CLIENT_SECRET || !GOOGLE_REDIRECT_URI || !GOOGLE_OAUTH_STATE_SECRET) {
    return req.method === "GET"
      ? adminRedirect("error=google_oauth_not_configured")
      : json({ success: false, error: "google_oauth_not_configured" }, 503);
  }

  if (req.method === "POST") {
    const authorization = req.headers.get("Authorization");
    if (!authorization) return json({ success: false, error: "unauthorized" }, 401);
    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authorization } },
    });
    const { data: { user }, error } = await userClient.auth.getUser();
    if (error || !user) return json({ success: false, error: "unauthorized" }, 401);

    let body: { action?: string; school_id?: string } = {};
    try { body = await req.json(); } catch { return json({ success: false, error: "invalid_body" }, 400); }
    if (body.action !== "start" || !body.school_id) {
      return json({ success: false, error: "invalid_request" }, 400);
    }

    const { data: membership, error: membershipError } = await userClient
      .from("school_memberships")
      .select("id")
      .eq("school_id", body.school_id)
      .eq("user_id", user.id)
      .eq("is_active", true)
      .in("role", ["school_admin", "principal", "platform_owner"])
      .maybeSingle();
    if (membershipError || !membership) return json({ success: false, error: "school_admin_access_required" }, 403);

    const statePayload = b64url(JSON.stringify({
      school_id: body.school_id,
      actor_id: user.id,
      exp: Math.floor(Date.now() / 1000) + 600,
      nonce: crypto.randomUUID(),
    }));
    const state = `${statePayload}.${await sign(statePayload)}`;
    const authUrl = new URL("https://accounts.google.com/o/oauth2/v2/auth");
    authUrl.searchParams.set("client_id", GOOGLE_CLIENT_ID);
    authUrl.searchParams.set("redirect_uri", GOOGLE_REDIRECT_URI);
    authUrl.searchParams.set("response_type", "code");
    authUrl.searchParams.set("scope", [
      "openid",
      "email",
      "https://www.googleapis.com/auth/calendar.events",
      "https://www.googleapis.com/auth/meetings.space.created",
    ].join(" "));
    authUrl.searchParams.set("access_type", "offline");
    authUrl.searchParams.set("prompt", "consent");
    authUrl.searchParams.set("include_granted_scopes", "true");
    authUrl.searchParams.set("state", state);
    return json({ success: true, authorization_url: authUrl.toString() });
  }

  if (req.method === "GET") {
    const url = new URL(req.url);
    const code = url.searchParams.get("code");
    const state = url.searchParams.get("state");
    if (url.searchParams.get("error")) return adminRedirect("error=google_consent_declined");
    if (!code || !state) return adminRedirect("error=invalid_oauth_callback");
    const verified = await verifyState(state);
    if (!verified) return adminRedirect("error=invalid_oauth_state");

    try {
      const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({
          code,
          client_id: GOOGLE_CLIENT_ID,
          client_secret: GOOGLE_CLIENT_SECRET,
          redirect_uri: GOOGLE_REDIRECT_URI,
          grant_type: "authorization_code",
        }),
      });
      if (!tokenResponse.ok) return adminRedirect("error=google_token_exchange_failed");
      const tokenData = await tokenResponse.json();
      if (!tokenData.refresh_token) return adminRedirect("error=google_refresh_token_missing");

      const profileResponse = await fetch("https://openidconnect.googleapis.com/v1/userinfo", {
        headers: { Authorization: `Bearer ${tokenData.access_token}` },
      });
      if (!profileResponse.ok) return adminRedirect("error=google_identity_check_failed");
      const profile = await profileResponse.json();
      if (profile.email_verified !== true || !profile.email) {
        return adminRedirect("error=google_email_not_verified");
      }

      const serviceClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
      const { data, error } = await serviceClient.rpc("store_google_meet_credentials", {
        p_school_id: verified.school_id,
        p_actor_id: verified.actor_id,
        p_organizer_email: profile.email,
        p_refresh_token: tokenData.refresh_token,
      });
      if (error || data?.success !== true) {
        console.error("Google Workspace credential storage failed:", error?.message ?? data?.error);
        return adminRedirect("error=workspace_credentials_not_saved");
      }
      return adminRedirect("connected=1");
    } catch (error) {
      console.error("Google Workspace OAuth callback failed:", error instanceof Error ? error.message : "unknown_error");
      return adminRedirect("error=google_oauth_callback_failed");
    }
  }

  return json({ success: false, error: "method_not_allowed" }, 405);
});
