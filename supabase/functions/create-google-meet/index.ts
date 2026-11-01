// Creates one school-scoped Google Meet space and Calendar event per confirmed booking.
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const GOOGLE_CLIENT_ID = Deno.env.get("GOOGLE_CLIENT_ID") ?? "";
const GOOGLE_CLIENT_SECRET = Deno.env.get("GOOGLE_CLIENT_SECRET") ?? "";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

function json(data: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: CORS });
}

async function googleAccessToken(refreshToken: string): Promise<string> {
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: GOOGLE_CLIENT_ID,
      client_secret: GOOGLE_CLIENT_SECRET,
      refresh_token: refreshToken,
      grant_type: "refresh_token",
    }),
  });
  if (!response.ok) throw new Error("google_token_refresh_failed");
  const data = await response.json();
  if (!data.access_token) throw new Error("google_access_token_missing");
  return data.access_token;
}

async function googleRequest(
  accessToken: string,
  url: string,
  method: string,
  body?: Record<string, unknown>,
): Promise<{ status: number; data: Record<string, any> }> {
  const response = await fetch(url, {
    method,
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  const data = await response.json().catch(() => ({}));
  return { status: response.status, data };
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
  if (req.method !== "POST") return json({ success: false, error: "method_not_allowed" }, 405);

  const authorization = req.headers.get("Authorization");
  if (!authorization) return json({ success: false, error: "unauthorized" }, 401);
  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authorization } },
  });
  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) return json({ success: false, error: "unauthorized" }, 401);

  let body: { booking_id?: string } = {};
  try { body = await req.json(); } catch { return json({ success: false, error: "invalid_body" }, 400); }
  const bookingId = body.booking_id?.trim() ?? "";
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(bookingId)) {
    return json({ success: false, error: "invalid_booking_id" }, 400);
  }
  if (!GOOGLE_CLIENT_ID || !GOOGLE_CLIENT_SECRET) {
    return json({ success: false, error: "google_oauth_not_configured" }, 503);
  }

  const serviceClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const { data: claim, error: claimError } = await serviceClient.rpc("claim_google_meet_creation", {
    p_booking_id: bookingId,
    p_actor_id: user.id,
  });
  if (claimError) {
    console.error("Google Meet booking claim failed:", claimError.message);
    return json({ success: false, error: "meeting_booking_validation_failed" }, 500);
  }
  if (!claim?.success) {
    const code = String(claim?.error ?? "meeting_creation_failed");
    const status = code === "not_a_participant" || code === "not_assigned_teacher" ? 403
      : code === "booking_not_found" ? 404
      : code === "creation_in_progress" ? 409
      : code === "google_workspace_not_connected" || code === "google_workspace_credentials_unavailable" ? 503
      : 409;
    return json({ success: false, error: code }, status);
  }
  if (claim.already_created) {
    return json({
      success: true,
      created: false,
      meet_link: claim.meet_link,
      calendar_event_id: claim.calendar_event_id,
      space_name: claim.space_name,
    });
  }

  const resetLease = async () => {
    await serviceClient.from("session_bookings")
      .update({ google_meet_creation_started_at: null, updated_at: new Date().toISOString() })
      .eq("id", bookingId);
  };

  try {
    const accessToken = await googleAccessToken(claim.refresh_token);
    let spaceName = claim.space_name as string | null;
    let meetLink = claim.meet_link as string | null;

    if (!spaceName || !meetLink) {
      const createdSpace = await googleRequest(
        accessToken,
        "https://meet.googleapis.com/v2/spaces",
        "POST",
        {
          config: {
            accessType: "RESTRICTED",
            moderation: "ON",
          },
        },
      );
      if (createdSpace.status < 200 || createdSpace.status >= 300 ||
          !createdSpace.data.name || !createdSpace.data.meetingUri) {
        console.error("Google Meet space creation failed:", createdSpace.status);
        await resetLease();
        return json({ success: false, error: "google_meet_space_creation_failed" }, 502);
      }
      spaceName = createdSpace.data.name;
      meetLink = createdSpace.data.meetingUri;
      const { error: spaceSaveError } = await serviceClient.from("session_google_meet_links")
        .upsert({
          booking_id: bookingId,
          school_id: claim.school_id,
          meet_link: meetLink,
          space_name: spaceName,
          host_email: claim.teacher_email,
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        }, { onConflict: "booking_id" });
      if (!spaceSaveError) {
        const { error: bookingSpaceError } = await serviceClient.from("session_bookings")
          .update({
            google_meet_space_name: spaceName,
            google_meet_host_email: claim.teacher_email,
            google_meet_created_at: new Date().toISOString(),
            updated_at: new Date().toISOString(),
          })
          .eq("id", bookingId);
        if (bookingSpaceError) {
          console.error("Google Meet booking metadata persistence failed:", bookingSpaceError.message);
          await resetLease();
          return json({ success: false, error: "google_meet_persist_failed" }, 500);
        }
      }
      if (spaceSaveError) {
        console.error("Google Meet space persistence failed:", spaceSaveError.message);
        await resetLease();
        return json({ success: false, error: "google_meet_persist_failed" }, 500);
      }
    }

    // The assigned teacher's verified roster email is the only additional meeting member.
    // Students have no Google account and are deliberately not invited as Calendar attendees.
    const memberUrl = `https://meet.googleapis.com/v2/${spaceName}/members`;
    const member = await googleRequest(accessToken, memberUrl, "POST", {
      email: claim.teacher_email,
      role: "COHOST",
    });
    if (member.status === 409) {
      const members = await googleRequest(accessToken, memberUrl, "GET");
      const existingMember = (members.data.members ?? []).find((entry: Record<string, string>) =>
        String(entry.email ?? "").toLowerCase() === String(claim.teacher_email).toLowerCase()
      );
      if (existingMember?.role !== "COHOST") {
        console.error("Teacher is already a Meet member but is not a co-host.");
        await resetLease();
        return json({ success: false, error: "google_meet_teacher_host_assignment_failed" }, 502);
      }
    } else if (member.status < 200 || member.status >= 300) {
      console.error("Google Meet co-host assignment failed:", member.status);
      await resetLease();
      return json({ success: false, error: "google_meet_teacher_host_assignment_failed" }, 502);
    }

    const eventId = `score${bookingId.replace(/-/g, "").toLowerCase()}`;
    const startAt = new Date(claim.scheduled_at);
    const duration = Number(claim.duration_minutes);
    if (!Number.isFinite(startAt.getTime()) || ![15, 30].includes(duration)) {
      await resetLease();
      return json({ success: false, error: "invalid_session_schedule" }, 409);
    }
    const endAt = new Date(startAt.getTime() + duration * 60_000);
    const calendarId = encodeURIComponent(claim.calendar_id || "primary");
    const eventUrl = `https://www.googleapis.com/calendar/v3/calendars/${calendarId}/events?sendUpdates=all`;
    const eventBody = {
      id: eventId,
      summary: `SCORE+ Mentor Desk — ${String(claim.topic || "Session").slice(0, 100)}`,
      description: [
        "SCORE+ Mentor Desk session.",
        `Join Google Meet: ${meetLink}`,
        `Booking reference: ${bookingId}`,
        `Duration: ${duration} minutes`,
        "The student joins through SCORE+ and is admitted by the assigned teacher.",
      ].join("\n"),
      location: meetLink,
      start: { dateTime: startAt.toISOString(), timeZone: claim.time_zone || "Asia/Kolkata" },
      end: { dateTime: endAt.toISOString(), timeZone: claim.time_zone || "Asia/Kolkata" },
      attendees: [{ email: claim.teacher_email }],
      extendedProperties: {
        private: {
          scoreplus_booking_id: bookingId,
          scoreplus_school_id: claim.school_id,
        },
      },
    };

    let event = await googleRequest(accessToken, eventUrl, "POST", eventBody);
    if (event.status === 409) {
      event = await googleRequest(accessToken, `${eventUrl}/${eventId}`, "GET");
      const storedBookingId = event.data.extendedProperties?.private?.scoreplus_booking_id;
      if (storedBookingId !== bookingId) {
        console.error("Calendar event ID collision or mismatched event.");
        await resetLease();
        return json({ success: false, error: "google_calendar_event_conflict" }, 409);
      }
    } else if (event.status < 200 || event.status >= 300) {
      console.error("Google Calendar event creation failed:", event.status);
      await resetLease();
      return json({ success: false, error: "google_calendar_event_creation_failed" }, 502);
    }

    const { error: linkSaveError } = await serviceClient.from("session_google_meet_links")
      .update({
        meet_link: meetLink,
        space_name: spaceName,
        calendar_event_id: event.data.id ?? eventId,
        host_email: claim.teacher_email,
        updated_at: new Date().toISOString(),
      })
      .eq("booking_id", bookingId);
    if (linkSaveError) {
      console.error("Google Meet link persistence failed:", linkSaveError.message);
      await resetLease();
      return json({ success: false, error: "google_meet_persist_failed" }, 500);
    }
    const { error: saveError } = await serviceClient.from("session_bookings")
      .update({
        google_meet_space_name: spaceName,
        google_meet_host_email: claim.teacher_email,
        google_calendar_event_id: event.data.id ?? eventId,
        google_meet_created_at: new Date().toISOString(),
        google_meet_creation_started_at: null,
        updated_at: new Date().toISOString(),
      })
      .eq("id", bookingId);
    if (saveError) {
      console.error("Google Meet event persistence failed:", saveError.message);
      await resetLease();
      return json({ success: false, error: "google_meet_persist_failed" }, 500);
    }

    return json({
      success: true,
      created: true,
      meet_link: meetLink,
      calendar_event_id: event.data.id ?? eventId,
      space_name: spaceName,
    });
  } catch (error) {
    console.error("Google Meet creation failed:", error instanceof Error ? error.message : "unknown_error");
    await resetLease();
    return json({ success: false, error: "google_meet_creation_failed" }, 502);
  }
});
