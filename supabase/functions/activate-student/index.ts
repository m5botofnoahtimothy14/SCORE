// ============================================================
// Edge Function: activate-student
// Authenticates the device session, then delegates code verification,
// single-use consumption and roster linking to one atomic database RPC.
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

  let body: { student_id_no?: string; activation_code?: string };
  try {
    body = await req.json();
  } catch {
    return json({ success: false, error: "invalid_body" }, 400);
  }

  const studentIdNo = body.student_id_no?.trim();
  const activationCode = body.activation_code?.trim();
  if (!studentIdNo || !activationCode || activationCode.length > 128) {
    return json({ success: false, error: "invalid_credentials" }, 400);
  }

  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const { data, error } = await adminClient.rpc("activate_student_verified", {
    p_student_id_no: studentIdNo,
    p_activation_code: activationCode,
    p_user_id: user.id,
  });

  if (error) {
    console.error("Student activation RPC failed:", error);
    return json({ success: false, error: "activation_failed" }, 400);
  }
  if (!data || data.success !== true) {
    const code = data?.error?.toString() ?? "activation_failed";
    const status = code === "student_not_found" ? 404 : code === "forbidden" ? 403 : 400;
    return json({ success: false, error: code }, status);
  }

  return json({
    success: true,
    student_id: data.student_id,
    class_id: data.class_id,
    school_id: data.school_id,
  });
});
