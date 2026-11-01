// ============================================================
// Edge Function: activate-student
// Authenticates the device session, verifies the one-time code in
// an atomic service-role RPC, and converts the anonymous session into
// a persistent password-backed account.
// ============================================================
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: CORS_HEADERS });
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ success: false, error: "method_not_allowed" }, 405);

  const authorization = req.headers.get("Authorization");
  if (!authorization) return json({ success: false, error: "unauthorized" }, 401);

  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authorization } },
  });
  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) return json({ success: false, error: "unauthorized" }, 401);

  let body: { student_id_no?: string; activation_code?: string; device_secret?: string };
  try {
    body = await req.json();
  } catch {
    return json({ success: false, error: "invalid_body" }, 400);
  }

  const studentIdNo = body.student_id_no?.trim();
  const activationCode = body.activation_code?.trim();
  const deviceSecret = body.device_secret;
  if (!studentIdNo || !activationCode || activationCode.length > 128
      || !deviceSecret || deviceSecret.length < 24 || deviceSecret.length > 128) {
    return json({ success: false, error: "invalid_credentials" }, 400);
  }

  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const { data: rosterRows, error: rosterError } = await adminClient
    .from("students")
    .select("id, user_id")
    .eq("student_id_no", studentIdNo)
    .eq("is_active", true)
    .limit(2);

  if (rosterError) {
    console.error("Student roster lookup failed:", rosterError.message);
    return json({ success: false, error: "activation_failed" }, 500);
  }
  if (!rosterRows || rosterRows.length === 0) {
    return json({ success: false, error: "student_not_found" }, 404);
  }
  if (rosterRows.length > 1) {
    return json({ success: false, error: "school_resolution_required" }, 409);
  }

  const rosterUserId = rosterRows[0].user_id as string | null;
  if (rosterUserId && rosterUserId !== user.id) {
    return json({ success: false, error: "student_already_linked" }, 409);
  }
  if (!rosterUserId && user.is_anonymous !== true) {
    return json({ success: false, error: "activation_requires_new_session" }, 409);
  }

  const { data, error } = await adminClient.rpc("activate_student_verified", {
    p_student_id_no: studentIdNo,
    p_activation_code: activationCode,
    p_user_id: user.id,
  });

  if (error) {
    console.error("Student activation RPC failed:", error.message);
    return json({ success: false, error: "activation_failed" }, 500);
  }
  if (!data || data.success !== true) {
    const code = data?.error?.toString() ?? "activation_failed";
    const status = code === "student_not_found" ? 404
      : code === "forbidden" ? 403
      : code === "school_resolution_required" || code === "student_already_linked" ? 409 : 400;
    return json({ success: false, error: code }, status);
  }

  const email = `student.${data.student_id}@students.scoreplus.invalid`;
  const { error: accountError } = await adminClient.auth.admin.updateUserById(user.id, {
    email,
    password: deviceSecret,
    email_confirm: true,
    user_metadata: { scoreplus_role: "student", school_id: data.school_id },
  });
  if (accountError) {
    console.error("Student account credential setup failed:", accountError.message);
    return json({ success: false, error: "account_setup_failed" }, 503);
  }

  return json({
    success: true,
    student_id: data.student_id,
    class_id: data.class_id,
    school_id: data.school_id,
    email,
  });
});
