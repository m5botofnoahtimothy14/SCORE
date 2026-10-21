// ============================================================
// Edge Function: activate-student
// Called by mobile app during student enrollment
// Uses service role — never trust client role claims
// ============================================================
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Rate limiting: max 5 attempts per student ID per 15 minutes
const RATE_LIMIT_WINDOW_MS = 15 * 60 * 1000;
const RATE_LIMIT_MAX = 5;

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
    const { school_id, student_id_no, activation_code } = body;

    if (!school_id || !student_id_no || !activation_code) {
      return jsonError("missing_fields", 400);
    }

    // Sanitize inputs
    if (typeof school_id !== "string" || typeof student_id_no !== "string" || typeof activation_code !== "string") {
      return jsonError("invalid_input", 400);
    }

    if (activation_code.length < 6 || activation_code.length > 20) {
      return jsonError("invalid_activation_code", 400);
    }

    // Use service role client for privileged operations
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Check rate limit for this student ID
    const rateKey = `student_activate:${school_id}:${student_id_no}`;
    const since = new Date(Date.now() - RATE_LIMIT_WINDOW_MS).toISOString();

    const { count } = await supabase
      .from("rate_limit_events")
      .select("*", { count: "exact", head: true })
      .eq("key", rateKey)
      .gte("created_at", since);

    if ((count ?? 0) >= RATE_LIMIT_MAX) {
      // Log the blocked attempt
      await supabase.from("audit_events").insert({
        school_id,
        action: "student.activate.rate_limited",
        target_type: "student",
        target_id: student_id_no,
        outcome: "rejected",
        ip_address: ip,
        metadata: { ip },
      });
      return jsonError("rate_limited", 429);
    }

    // Record this attempt
    await supabase.from("rate_limit_events").insert({ key: rateKey, action: "activate" });

    // Get the authenticated user from the Authorization header
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return jsonError("unauthorized", 401);

    // Verify the JWT to get the user
    const userClient = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: authError } = await userClient.auth.getUser();
    if (authError || !user) return jsonError("unauthorized", 401);

    // Call the secure DB function
    const { data, error } = await supabase.rpc("activate_student", {
      p_school_id: school_id,
      p_student_id_no: student_id_no,
      p_activation_code: activation_code,
      p_auth_user_id: user.id,
    });

    if (error) {
      console.error("activate_student RPC error:", error);
      return jsonError("server_error", 500);
    }

    if (!data.success) {
      await supabase.from("audit_events").insert({
        school_id,
        action: "student.activate.failed",
        target_type: "student",
        outcome: "failure",
        reason: data.error,
        ip_address: ip,
      });
      // Surface a small set of safe, helpful codes; keep everything else
      // generic to prevent student-ID enumeration.
      const safeErrors = ["code_expired", "no_activation_code", "code_already_used", "rate_limited"];
      const err = safeErrors.includes(data.error) ? data.error : "invalid_credentials";
      return jsonError(err, 401);
    }

    await supabase.from("audit_events").insert({
      school_id,
      actor_id: user.id,
      action: "student.activate",
      target_type: "student",
      target_id: data.student_id,
      outcome: "success",
      ip_address: ip,
    });

    // Turn the anonymous session into a permanent account.
    //
    // Supabase anonymous sessions expire after roughly an hour, which would
    // sign every student out mid-lesson. The device secret is generated on
    // the handset and becomes the account's credential, so the session
    // refreshes indefinitely.
    let email: string | null = null;
    const deviceSecret = typeof body.device_secret === "string" ? body.device_secret : "";
    if (deviceSecret.length >= 16) {
      // The synthetic address is built from the roster id, so it has to be
      // read back from the students table — the RPC does not return it.
      let rosterId = "";
      try {
        const { data: student } = await supabase
          .from("students")
          .select("student_id_no")
          .eq("id", data.student_id)
          .eq("school_id", school_id)
          .maybeSingle();
        rosterId = String(student?.student_id_no ?? "");
      } catch (e) {
        console.error("could not read the roster id:", e);
      }

      if (rosterId) {
        email = await upgradeToPermanentAccount(
          supabase,
          user.id,
          "s",
          rosterId,
          school_id,
          deviceSecret,
        );
      } else {
        console.error("no roster id — leaving the account anonymous");
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        student_id: data.student_id,
        class_id: data.class_id,
        email,
      }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error("activate-student error:", err);
    return jsonError("server_error", 500);
  }
});

/**
 * Gives the freshly activated account a permanent credential.
 *
 * The synthetic address is derived from the school code and the roster id,
 * so it is unique per school and never collides with a real mailbox.
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

    // Never take over an address that already belongs to somebody else.
    const { data: existing } = await supabase.auth.admin.listUsers({
      page: 1,
      perPage: 1000,
    });
    const clash = existing?.users?.find((u) => u.email === email);
    if (clash && clash.id !== userId) {
      console.error(`synthetic address ${email} is already in use — not upgrading`);
      return null;
    }

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
