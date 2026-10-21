// ============================================================
// Edge Function: verify-otp
// Verifies OTP for teacher enrollment
// ============================================================
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const MAX_OTP_ATTEMPTS = 5;
const LOCKOUT_MINUTES = 30;

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
    const { phone, otp, school_id, staff_id_no } = body;

    if (!phone || !otp || !school_id || !staff_id_no) return jsonError("missing_fields", 400);

    // Get authenticated user
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return jsonError("unauthorized", 401);

    const userClient = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: authError } = await userClient.auth.getUser();
    if (authError || !user) return jsonError("unauthorized", 401);

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Get teacher record
    const { data: teacher } = await supabase
      .from("teachers")
      .select("id")
      .eq("school_id", school_id)
      .eq("staff_id_no", staff_id_no)
      .eq("is_active", true)
      .single();

    if (!teacher) return jsonError("invalid_credentials", 401);

    // Get activation record
    const { data: record } = await supabase
      .from("staff_activation_records")
      .select("*")
      .eq("teacher_id", teacher.id)
      .single();

    if (!record) return jsonError("no_otp_sent", 400);

    // Check lockout
    if (record.locked_until && new Date(record.locked_until) > new Date()) {
      return jsonError("account_locked", 423);
    }

    // Check expiry
    if (new Date(record.otp_expires_at) < new Date()) {
      return jsonError("otp_expired", 400);
    }

    // Check already verified
    if (record.otp_verified_at) {
      return jsonError("otp_already_used", 400);
    }

    // Verify OTP
    const encoder = new TextEncoder();
    const data = encoder.encode(otp.trim());
    const hashBuffer = await crypto.subtle.digest("SHA-256", data);
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    const otpHash = hashArray.map(b => b.toString(16).padStart(2, "0")).join("");

    if (otpHash !== record.otp_hash) {
      // Increment attempt count
      const newAttempts = record.attempt_count + 1;
      const updates: Record<string, unknown> = { attempt_count: newAttempts };

      if (newAttempts >= MAX_OTP_ATTEMPTS) {
        updates.locked_until = new Date(Date.now() + LOCKOUT_MINUTES * 60 * 1000).toISOString();
      }

      await supabase
        .from("staff_activation_records")
        .update(updates)
        .eq("teacher_id", teacher.id);

      await supabase.from("audit_events").insert({
        school_id,
        action: "teacher.otp.failed",
        target_type: "teacher",
        target_id: teacher.id,
        outcome: "failure",
        ip_address: ip,
        metadata: { attempts: newAttempts },
      });

      return jsonError("invalid_otp", 401);
    }

    // OTP valid — mark as verified
    await supabase
      .from("staff_activation_records")
      .update({ otp_verified_at: new Date().toISOString(), attempt_count: 0 })
      .eq("teacher_id", teacher.id);

    // Activate teacher account via DB function
    const { data: activationResult } = await supabase.rpc("activate_teacher", {
      p_school_id: school_id,
      p_staff_id_no: staff_id_no,
      p_auth_user_id: user.id,
      p_phone: phone,
    });

    if (!activationResult?.success) {
      return jsonError("activation_failed", 500);
    }

    await supabase.from("audit_events").insert({
      school_id,
      actor_id: user.id,
      action: "teacher.activate",
      target_type: "teacher",
      target_id: teacher.id,
      outcome: "success",
      ip_address: ip,
    });

    // Turn the anonymous session into a permanent account so the teacher's
    // session survives past the anonymous-session lifetime.
    let email: string | null = null;
    const deviceSecret = typeof body.device_secret === "string" ? body.device_secret : "";
    if (deviceSecret.length >= 16) {
      email = await upgradeToPermanentAccount(
        supabase,
        user.id,
        "t",
        staff_id_no,
        school_id,
        deviceSecret,
      );
    }

    return new Response(
      JSON.stringify({ success: true, teacher_id: activationResult.teacher_id, email }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error("verify-otp error:", err);
    return jsonError("server_error", 500);
  }
});

/**
 * Gives the freshly activated account a permanent credential.
 * The synthetic address is derived from the school code and the staff id.
 */
async function upgradeToPermanentAccount(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  prefix: "s" | "t",
  rosterId: string,
  schoolId: string,
  secret: string,
): Promise<string | null> {
  try {
    const { data: school } = await supabase
      .from("schools")
      .select("code")
      .eq("id", schoolId)
      .maybeSingle();
    const schoolCode = String(school?.code ?? "school")
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-");
    const local = rosterId.toLowerCase().replace(/[^a-z0-9]+/g, "-");
    const email = `${prefix}-${local}@${schoolCode}.teachcross.app`;

    const { error } = await supabase.auth.admin.updateUserById(userId, {
      email,
      password: secret,
      email_confirm: true,
    });
    if (error) {
      console.error("could not upgrade the account to a permanent one:", error.message);
      return null;
    }
    return email;
  } catch (e) {
    console.error("upgradeToPermanentAccount failed:", e);
    return null;
  }
}

function jsonError(error: string, status: number) {
  return new Response(JSON.stringify({ success: false, error }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
