// ============================================================
// Edge Function: send-otp
// Sends OTP to teacher's phone for enrollment verification
// Uses TextBee (self-hosted Android SMS gateway)
// ============================================================
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// TextBee SMS gateway (https://textbee.dev) — sends through your own Android phone.
const TEXTBEE_API_KEY = Deno.env.get("TEXTBEE_API_KEY");
const TEXTBEE_DEVICE_ID = Deno.env.get("TEXTBEE_DEVICE_ID"); // optional; uses default device if unset
const TEXTBEE_BASE_URL = Deno.env.get("TEXTBEE_BASE_URL") ?? "https://api.textbee.dev/api/v1";

// Demo/pre-prod only: when set, every teacher OTP is this fixed value and
// SMS delivery is skipped. MUST be unset (or empty) in production.
const DEMO_OTP = Deno.env.get("DEMO_OTP");

const OTP_LENGTH = 6;
const OTP_EXPIRY_MINUTES = 10;
const RATE_LIMIT_MAX_OTP = 3; // max OTPs per phone per hour

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, content-type",
      },
    });
  }

  const ip = req.headers.get("x-forwarded-for") ?? "unknown";

  try {
    const body = await req.json();
    const { phone, school_id, staff_id_no } = body;

    if (!phone || !school_id || !staff_id_no) return jsonError("missing_fields", 400);

    // Validate phone format (India: +91XXXXXXXXXX)
    const phoneRegex = /^\+[1-9]\d{6,14}$/;
    if (!phoneRegex.test(phone)) return jsonError("invalid_phone", 400);

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Rate limiting
    const rateKey = `otp:${phone}`;
    const since = new Date(Date.now() - 60 * 60 * 1000).toISOString();
    const { count } = await supabase
      .from("rate_limit_events")
      .select("*", { count: "exact", head: true })
      .eq("key", rateKey)
      .gte("created_at", since);

    if ((count ?? 0) >= RATE_LIMIT_MAX_OTP) {
      return jsonError("rate_limited", 429);
    }

    // Verify teacher exists and phone matches
    const { data: teacher, error: teacherError } = await supabase
      .from("teachers")
      .select("id, phone, is_active")
      .eq("school_id", school_id)
      .eq("staff_id_no", staff_id_no)
      .eq("is_active", true)
      .single();

    if (teacherError || !teacher) {
      // Generic error to prevent staff ID enumeration
      await new Promise(r => setTimeout(r, 300)); // timing-safe delay
      return jsonError("invalid_credentials", 401);
    }

    if (teacher.phone !== phone) {
      return jsonError("invalid_credentials", 401);
    }

    // Generate OTP (fixed value in demo mode)
    const otp = DEMO_OTP ? DEMO_OTP : generateOtp(OTP_LENGTH);
    const otpHash = await hashOtp(otp);
    const expiresAt = new Date(Date.now() + OTP_EXPIRY_MINUTES * 60 * 1000).toISOString();

    // Store hashed OTP
    await supabase.from("staff_activation_records").upsert({
      school_id,
      teacher_id: teacher.id,
      otp_hash: otpHash,
      otp_expires_at: expiresAt,
      otp_verified_at: null,
      attempt_count: 0,
      locked_until: null,
    }, { onConflict: "teacher_id" });

    // Record rate limit event
    await supabase.from("rate_limit_events").insert({ key: rateKey, action: "send_otp" });

    // Send OTP via configured provider (skipped in demo mode)
    const sent = DEMO_OTP ? true : await sendOtp(phone, otp);

    if (!sent) {
      // If SMS fails, we cannot claim OTP was sent
      return jsonError("sms_provider_unavailable", 503);
    }

    await supabase.from("audit_events").insert({
      school_id,
      action: "teacher.otp.sent",
      target_type: "teacher",
      target_id: teacher.id,
      outcome: "success",
      ip_address: ip,
    });

    return new Response(
      JSON.stringify({ success: true, expires_in_minutes: OTP_EXPIRY_MINUTES, demo: DEMO_OTP ? true : undefined }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error("send-otp error:", err);
    return jsonError("server_error", 500);
  }
});

function generateOtp(length: number): string {
  const digits = "0123456789";
  let otp = "";
  const randomValues = new Uint8Array(length);
  crypto.getRandomValues(randomValues);
  for (const v of randomValues) {
    otp += digits[v % 10];
  }
  return otp;
}

async function hashOtp(otp: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(otp);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map(b => b.toString(16).padStart(2, "0")).join("");
}

async function sendOtp(phone: string, otp: string): Promise<boolean> {
  if (!TEXTBEE_API_KEY) {
    console.error("CRITICAL: TEXTBEE_API_KEY not configured. Cannot send OTP.");
    return false;
  }
  return await sendViaTextbee(phone, otp);
}

async function sendViaTextbee(phone: string, otp: string): Promise<boolean> {
  try {
    const message = `Your TeachCross verification code is ${otp}. It expires in ${OTP_EXPIRY_MINUTES} minutes. Do not share it.`;
    const payload: Record<string, unknown> = { recipients: [phone], message };
    if (TEXTBEE_DEVICE_ID) payload.deviceId = TEXTBEE_DEVICE_ID;

    const response = await fetch(`${TEXTBEE_BASE_URL}/gateway/send-sms`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": TEXTBEE_API_KEY!,
      },
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      console.error("TextBee error:", response.status, await response.text());
      return false;
    }
    return true; // 200 = accepted by the gateway (queued to the phone)
  } catch (err) {
    console.error("TextBee error:", err);
    return false;
  }
}

function jsonError(error: string, status: number) {
  return new Response(JSON.stringify({ success: false, error }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
