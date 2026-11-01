// ============================================================
// Edge Function: issue-video-token
// Validates a SCORE booking and issues a short-lived, room-scoped
// access token for the self-hosted LiveKit media server.
// No managed meeting provider is used.
// ============================================================
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const LIVEKIT_API_KEY = Deno.env.get("LIVEKIT_API_KEY") ?? "";
const LIVEKIT_API_SECRET = Deno.env.get("LIVEKIT_API_SECRET") ?? "";
const LIVEKIT_URL = Deno.env.get("LIVEKIT_URL") ?? "";
const MAX_TOKEN_TTL_SECONDS = 3600;
const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Content-Type': 'application/json',
};

function jsonError(code: string, status = 400) {
  return new Response(JSON.stringify({ success: false, error: code }), {
    status,
    headers: CORS_HEADERS,
  });
}

function base64url(data: Uint8Array | string) {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
  let str = "";
  for (const b of bytes) str += String.fromCharCode(b);
  return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function signJwt(payload: Record<string, unknown>) {
  const header = { alg: "HS256", typ: "JWT" };
  const enc = new TextEncoder();
  const headerB64 = base64url(JSON.stringify(header));
  const payloadB64 = base64url(JSON.stringify(payload));
  const signingInput = `${headerB64}.${payloadB64}`;
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(LIVEKIT_API_SECRET),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(signingInput));
  return `${signingInput}.${base64url(new Uint8Array(sig))}`;
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") return jsonError("method_not_allowed", 405);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return jsonError("unauthorized", 401);

  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) return jsonError("unauthorized", 401);

  let body: { booking_id?: string } = {};
  try { body = await req.json(); } catch { return jsonError("invalid_body", 400); }
  const bookingId = body.booking_id?.trim();
  if (!bookingId || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(bookingId)) {
    return jsonError("invalid_booking_id", 400);
  }

  if (!LIVEKIT_API_KEY || !LIVEKIT_API_SECRET || !LIVEKIT_URL || !LIVEKIT_URL.startsWith("wss://")) {
    return jsonError("video_not_configured", 503);
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const { data: booking, error: bErr } = await supabase
    .from("session_bookings")
    .select("id, school_id, student_id, mentor_id, status, started_at, reserved_minutes, video_room_name")
    .eq("id", bookingId)
    .maybeSingle();
  if (bErr || !booking) return jsonError("booking_not_found", 404);

  if (user.id !== booking.student_id && user.id !== booking.mentor_id) {
    return jsonError("not_a_participant", 403);
  }
  if (!["confirmed", "in_progress"].includes(booking.status)) {
    return jsonError("booking_not_confirmed", 409);
  }
  if (!booking.started_at) return jsonError("booking_not_started", 409);

  const durationMinutes = Number(booking.reserved_minutes);
  if (![15, 30].includes(durationMinutes)) return jsonError("invalid_session_duration", 409);

  const startedAtMs = new Date(booking.started_at).getTime();
  if (!Number.isFinite(startedAtMs)) return jsonError("invalid_session_start", 409);

  const now = Math.floor(Date.now() / 1000);
  const sessionDeadline = Math.floor((startedAtMs + durationMinutes * 60_000) / 1000);
  const expiresAt = Math.min(now + MAX_TOKEN_TTL_SECONDS, sessionDeadline);
  if (expiresAt <= now) return jsonError("session_time_elapsed", 409);

  // Provision room name if missing
  let roomName = booking.video_room_name;
  if (!roomName) {
    const { data: room, error: roomError } = await supabase
      .from("video_rooms")
      .select("room_name")
      .eq("booking_id", bookingId)
      .maybeSingle();
    if (roomError) return jsonError("video_room_lookup_failed", 500);
    roomName = room?.room_name ?? `md-${bookingId.replace(/-/g, "")}`;
    if (!room?.room_name) {
      const { error: roomWriteError } = await supabase.from("video_rooms").upsert({
        school_id: booking.school_id,
        booking_id: bookingId,
        room_name: roomName,
      }, { onConflict: "booking_id" });
      if (roomWriteError) return jsonError("video_room_create_failed", 500);
      const { error: bookingWriteError } = await supabase.from("session_bookings")
        .update({ video_room_name: roomName })
        .eq("id", bookingId);
      if (bookingWriteError) return jsonError("video_room_link_failed", 500);
    }
  }

  const { data: profile } = await supabase
    .from('user_profiles')
    .select('display_name')
    .eq('id', user.id)
    .maybeSingle();
  const participantName = profile?.display_name?.toString() || user.user_metadata?.display_name?.toString() || `SCORE+ participant ${user.id.slice(0, 8)}`;

  const token = await signJwt({
    iss: LIVEKIT_API_KEY,
    sub: user.id,
    name: participantName,
    iat: now,
    nbf: now,
    exp: expiresAt,
    video: {
      roomJoin: true,
      room: roomName,
      canPublish: true,
      canSubscribe: true,
    },
  });

  return new Response(JSON.stringify({
    success: true,
    url: LIVEKIT_URL,
    token,
    room_name: roomName,
    ttl_seconds: expiresAt - now,
    expires_at: new Date(expiresAt * 1000).toISOString(),
  }), { status: 200, headers: CORS_HEADERS });
});
