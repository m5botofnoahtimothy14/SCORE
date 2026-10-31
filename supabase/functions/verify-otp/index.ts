// ============================================================
// Edge Function: verify-otp
// Verifies OTP for teacher activation
// ============================================================
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const DEMO_OTP = Deno.env.get("DEMO_OTP");
const DEMO_OTP_STAFF_ID = Deno.env.get("DEMO_OTP_STAFF_ID");
const DEMO_OTP_VALUE = Deno.env.get("DEMO_OTP_VALUE");

function jsonError(code: string, status = 400) {
  return new Response(JSON.stringify({ success: false, error: code }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
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
  if (!authHeader) return jsonError("unauthorized", 401);

  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) return jsonError("unauthorized", 401);

  let body: { phone?: string; otp?: string; school_id?: string; staff_id_no?: string } = {};
  try { body = await req.json(); } catch { return jsonError("invalid_body", 400); }

  const phone = body.phone;
  const otp = body.otp;
  const school_id = body.school_id;
  const staff_id_no = body.staff_id_no;

  if (!phone || !otp || !staff_id_no) {
    return jsonError("invalid_body", 400);
  }

  // Demo OTP mode
  if (DEMO_OTP && DEMO_OTP_STAFF_ID && staff_id_no === DEMO_OTP_STAFF_ID) {
    if (otp !== DEMO_OTP_VALUE) {
      return jsonError("invalid_otp", 400);
    }
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const { error } = await supabase
      .from("staff_activation_records")
      .update({ otp_verified_at: new Date().toISOString() })
      .eq("teacher_id", staff_id_no);

    if (error) return jsonError("activation_failed", 500);

    // Activate the teacher via RPC
    const { data: activateData, error: activateError } = await supabase.rpc("activate_teacher", {
      p_staff_id_no: staff_id_no,
      p_activation_code: "",
      p_device_secret: "",
    });

    if (activateError || !activateData?.success) {
      return jsonError(activateError?.message || "activation_failed", 400);
    }

    return new Response(JSON.stringify({
      success: true,
      teacher_id: activateData.teacher_id,
    }), { status: 200, headers: { "Content-Type": "application/json" } });
  }

  // Real OTP verification
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  const { data: record, error: recordError } = await supabase
    .from("staff_activation_records")
    .select("*")
    .eq("teacher_id", staff_id_no)
    .single();

  if (recordError || !record) {
    return jsonError("invalid_credentials", 400);
  }

  // Check locked
  if (record.locked_until && new Date(record.locked_until) > new Date()) {
    return jsonError("account_locked", 423);
  }

  // Check expired
  if (record.otp_expires_at && new Date(record.otp_expires_at) <= new Date()) {
    return jsonError("otp_expired", 400);
  }

  // Check already verified
  if (record.otp_verified_at) {
    return jsonError("otp_already_used", 400);
  }

  // Check attempt count
  if (record.attempt_count >= 5) {
    await supabase
      .from("staff_activation_records")
      .update({ locked_until: new Date(Date.now() + 30 * 60000).toISOString() })
      .eq("teacher_id", staff_id_no);
    return jsonError("account_locked", 423);
  }

  // Verify OTP hash
  const otpHash = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(otp + ":" + staff_id_no + ":" + phone)
  );
  const otpHashHex = Array.from(new Uint8Array(otpHash))
    .map(b => b.toString(16).padStart(2, "0"))
    .join("");

  if (otpHashHex !== record.otp_hash) {
    // Increment attempt count
    await supabase
      .from("staff_activation_records")
      .update({ attempt_count: record.attempt_count + 1 })
      .eq("teacher_id", staff_id_no);
    return jsonError("invalid_otp", 400);
  }

  // Mark as verified
  await supabase
    .from("staff_activation_records")
    .update({ otp_verified_at: new Date().toISOString() })
    .eq("teacher_id", staff_id_no);

  // Activate the teacher via RPC
  const { data: activateData, error: activateError } = await supabase.rpc("activate_teacher", {
    p_staff_id_no: staff_id_no,
    p_activation_code: "",
    p_device_secret: "",
  });

  if (activateError || !activateData?.success) {
    return jsonError(activateError?.message || "activation_failed", 500);
  }

  return new Response(JSON.stringify({
    success: true,
    teacher_id: activateData.teacher_id,
  }), { status: 200, headers: { "Content-Type": "application/json" } });
});