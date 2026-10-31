// ============================================================
// Edge Function: send-otp
// Sends OTP via SMS provider (TextBee) for teacher activation
// ============================================================
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const TEXTBEE_API_KEY = Deno.env.get("TEXTBEE_API_KEY")!;
const TEXTBEE_DEVICE_ID = Deno.env.get("TEXTBEE_DEVICE_ID");
const TEXTBEE_BASE_URL = Deno.env.get("TEXTBEE_BASE_URL") ?? "https://api.textbee.dev/api/v1";
const DEMO_OTP = Deno.env.get("DEMO_OTP");
const DEMO_OTP_STAFF_ID = Deno.env.get("DEMO_OTP_STAFF_ID");
const DEMO_OTP_VALUE = Deno.env.get("DEMO_OTP_VALUE");

function jsonError(code: string, status = 400) {
  return new Response(JSON.stringify({ success: false, error: code }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function generateOTP(): string {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

async function sendOTPviaTextBee(phone: string, otp: string): Promise<boolean> {
  if (!TEXTBEE_API_KEY) return false;
  try {
    const resp = await fetch(`${TEXTBEE_BASE_URL}/gateway/devices/${TEXTBEE_DEVICE_ID}/send`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-access-key": TEXTBEE_API_KEY,
      },
      body: JSON.stringify({
        phoneNumber: phone,
        message: `Your TeachCross verification code is: ${otp}`,
      }),
    });
    return resp.ok;
  } catch {
    return false;
  }
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, content-type",
      },
    });
  }

  if (req.method !== "POST") {
    return jsonError("method_not_allowed", 405);
  }

  const authHeader = req.headers.get("Authorization");
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader || "" } },
  });

  let body: { phone?: string; school_id?: string; staff_id_no?: string } = {};
  try { body = await req.json(); } catch { return jsonError("invalid_body", 400); }

  const phone = body.phone;
  const school_id = body.school_id;
  const staff_id_no = body.staff_id_no;

  if (!phone) return jsonError("invalid_phone", 400);

  // Demo OTP mode
  if (DEMO_OTP && DEMO_OTP_STAFF_ID && staff_id_no === DEMO_OTP_STAFF_ID) {
    const supabaseService = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const otpHash = await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode(DEMO_OTP_VALUE + ":" + staff_id_no + ":" + phone)
    );
    const otpHashHex = Array.from(new Uint8Array(otpHash))
      .map(b => b.toString(16).padStart(2, "0"))
      .join("");

    await supabaseService
      .from("staff_activation_records")
      .upsert({
        school_id,
        teacher_id: staff_id_no,
        otp_hash: otpHashHex,
        otp_expires_at: new Date(Date.now() + 10 * 60000).toISOString(),
        otp_verified_at: null,
        attempt_count: 0,
        locked_until: null,
      }, { onConflict: "teacher_id" });

    return new Response(JSON.stringify({
      success: true,
      expires_in_minutes: 10,
      demo: true,
    }), { status: 200, headers: { "Content-Type": "application/json" } });
  }

  // Real OTP via SMS
  const otp = generateOTP();
  const otpHash = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(otp + ":" + staff_id_no + ":" + phone)
  );
  const otpHashHex = Array.from(new Uint8Array(otpHash))
    .map(b => b.toString(16).padStart(2, "0"))
    .join("");

  const supabaseService = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  await supabaseService
    .from("staff_activation_records")
    .upsert({
      school_id,
      teacher_id: staff_id_no,
      otp_hash: otpHashHex,
      otp_salt: phone,
      otp_expires_at: new Date(Date.now() + 10 * 60000).toISOString(),
      otp_verified_at: null,
      attempt_count: 0,
      locked_until: null,
    }, { onConflict: "teacher_id" });

  const smsSent = await sendOTPviaTextBee(phone, otp);
  if (!smsSent) {
    return jsonError("sms_provider_unavailable", 503);
  }

  return new Response(JSON.stringify({
    success: true,
    expires_in_minutes: 10,
  }), { status: 200, headers: { "Content-Type": "application/json" } });
});