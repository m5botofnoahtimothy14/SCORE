// ============================================================
// Edge Function: create-google-meet
// Creates Google Calendar event with Meet link for session booking
// ============================================================
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const GOOGLE_CLIENT_ID = Deno.env.get("GOOGLE_CLIENT_ID") ?? "";
const GOOGLE_CLIENT_SECRET = Deno.env.get("GOOGLE_CLIENT_SECRET") ?? "";
const GOOGLE_REFRESH_TOKEN = Deno.env.get("GOOGLE_REFRESH_TOKEN") ?? "";
const GOOGLE_CALENDAR_ID = Deno.env.get("GOOGLE_CALENDAR_ID") ?? "primary";

function jsonError(code: string, status = 400) {
  return new Response(JSON.stringify({ success: false, error: code }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function jsonOk(data: unknown, status = 200) {
  return new Response(JSON.stringify({ success: true, ...(data as object) }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

let cachedAccessToken: { token: string; expiresAt: number } | null = null;

async function getGoogleAccessToken(): Promise<string> {
  if (GOOGLE_CLIENT_ID && GOOGLE_CLIENT_SECRET && GOOGLE_REFRESH_TOKEN) {
    const now = Date.now();
    if (cachedAccessToken && cachedAccessToken.expiresAt > now + 60000) {
      return cachedAccessToken.token;
    }
    const resp = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: GOOGLE_CLIENT_ID,
        client_secret: GOOGLE_CLIENT_SECRET,
        refresh_token: GOOGLE_REFRESH_TOKEN,
        grant_type: "refresh_token",
      }),
    });
    if (!resp.ok) {
      throw new Error("google_token_refresh_failed");
    }
    const data = await resp.json();
    cachedAccessToken = {
      token: data.access_token as string,
      expiresAt: now + ((data.expires_in as number ?? 3600) * 1000),
    };
    return cachedAccessToken.token;
  }
  throw new Error("google_credentials_not_configured");
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, content-type",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
      },
    });
  }

  if (req.method !== "POST") {
    return jsonError("method_not_allowed", 405);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return jsonError("unauthorized", 401);

  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) return jsonError("unauthorized", 401);

  let body: { booking_id?: string } = {};
  try { body = await req.json(); } catch { return jsonError("invalid_body", 400); }
  const bookingId = body.booking_id;
  if (!bookingId) return jsonError("missing_booking_id", 400);

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const { data: booking, error: bErr } = await supabase
    .from("session_bookings")
    .select("id, school_id, student_id, mentor_id, status, scheduled_at, duration_minutes, topic, google_meet_link, google_calendar_event_id")
    .eq("id", bookingId)
    .maybeSingle();
  if (bErr || !booking) return jsonError("booking_not_found", 404);

  if (user.id !== booking.student_id && user.id !== booking.mentor_id) {
    return jsonError("not_a_participant", 403);
  }
  if (booking.status !== "confirmed") {
    return jsonError("booking_not_confirmed", 409);
  }

  // Idempotent: return existing Meet link
  if (booking.google_calendar_event_id && booking.google_meet_link) {
    return jsonOk({
      meet_link: booking.google_meet_link,
      calendar_event_id: booking.google_calendar_event_id,
      created: false,
    });
  }

  if (!GOOGLE_CLIENT_ID || !GOOGLE_CLIENT_SECRET || !GOOGLE_REFRESH_TOKEN) {
    return jsonError("google_credentials_not_configured", 503);
  }

  try {
    const accessToken = await getGoogleAccessToken();
    const calendarId = GOOGLE_CALENDAR_ID || "primary";
    const tz = "Asia/Kolkata";
    const start = booking.scheduled_at || new Date().toISOString();
    const startDate = new Date(start);
    const endDate = new Date(startDate.getTime() + (booking.duration_minutes ?? 30) * 60000);

    const event = {
      summary: `Mentor Desk Session — ${booking.topic || "Session"}`,
      description: `TeachCross Mentor Desk session\nBooking ID: ${bookingId}\nSubject: ${booking.subject_id ?? "—"}\nDuration: ${booking.duration_minutes ?? 30} minutes`,
      start: { dateTime: startDate.toISOString(), timeZone: tz },
      end: { dateTime: endDate.toISOString(), timeZone: tz },
      conferenceData: {
        createRequest: {
          requestId: `teachcross-${bookingId}`,
          conferenceSolutionKey: { type: "hangoutsMeet" },
        },
      },
    };

    const calResp = await fetch(
      `https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(calendarId)}/events?conferenceDataVersion=1&sendUpdates=none`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(event),
      }
    );

    if (!calResp.ok) {
      const errBody = await calResp.text().catch(() => "");
      console.error("Google Calendar API error:", calResp.status, errBody);
      return jsonError("google_calendar_api_failed", 502);
    }

    const calData = await calResp.json();
    const meetLink =
      calData.conferenceData?.entryPoints?.find((e: any) => e.entryPointType === "video")
        ?.uri ??
      calData.hangoutLink ??
      null;
    const eventId = calData.id;

    if (!meetLink) {
      return jsonError("google_meet_link_not_created", 502);
    }

    const { error: uErr } = await supabase
      .from("session_bookings")
      .update({
        google_meet_link: meetLink,
        google_calendar_event_id: eventId,
        google_meet_created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq("id", bookingId);

    if (uErr) {
      console.error("DB update error:", uErr);
      return jsonError("db_update_failed", 500);
    }

    return jsonOk({
      meet_link: meetLink,
      calendar_event_id: eventId,
      created: true,
    });
  } catch (err) {
    console.error("create-google-meet error:", err);
    return jsonError(
      err instanceof Error ? err.message : "create_google_meet_failed",
      500
    );
  }
});