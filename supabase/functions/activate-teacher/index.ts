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

async function sha256Hex(input: string): Promise<string> {
  const hash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return Array.from(new Uint8Array(hash))
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");
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

  let body: { staff_id_no?: string; activation_code?: string; device_secret?: string };
  try {
    body = await req.json();
  } catch {
    return json({ success: false, error: "invalid_body" }, 400);
  }

  const staffIdNo = body.staff_id_no?.trim();
  const activationCode = body.activation_code?.trim();
  if (!staffIdNo || !activationCode || activationCode.length > 128) {
    return json({ success: false, error: "invalid_credentials" }, 400);
  }

  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const { data: teacher, error: teacherError } = await adminClient
    .from("teachers")
    .select("id, school_id, user_id, is_active")
    .eq("staff_id_no", staffIdNo)
    .eq("is_active", true)
    .maybeSingle();

  if (teacherError || !teacher) return json({ success: false, error: "teacher_not_found" }, 404);
  if (teacher.user_id && teacher.user_id !== user.id) {
    return json({ success: false, error: "teacher_already_linked" }, 409);
  }

  const { data: credential, error: credentialError } = await adminClient
    .from("teacher_activation_credentials")
    .select("id, code, expires_at, used_at")
    .eq("teacher_id", teacher.id)
    .maybeSingle();

  if (credentialError || !credential) return json({ success: false, error: "no_activation_code" }, 404);
  if (credential.used_at) return json({ success: false, error: "code_already_used" }, 400);
  if (new Date(credential.expires_at) <= new Date()) return json({ success: false, error: "code_expired" }, 400);

  const submittedHash = await sha256Hex(activationCode);
  if (submittedHash !== credential.code) return json({ success: false, error: "invalid_code" }, 400);

  // The RPC performs teacher linking, profile creation, membership creation
  // and audit logging in one database transaction.
  const { data: activation, error: activationError } = await userClient.rpc("activate_teacher", {
    p_staff_id_no: staffIdNo,
    p_activation_code: activationCode,
    p_device_secret: body.device_secret ?? "",
  });

  if (activationError || !activation || activation.success !== true) {
    return json({ success: false, error: activation?.error ?? "activation_failed" }, 400);
  }

  const { error: consumeError } = await adminClient
    .from("teacher_activation_credentials")
    .update({ used_at: new Date().toISOString() })
    .eq("id", credential.id)
    .is("used_at", null);

  if (consumeError) {
    console.error("Teacher activation succeeded but credential consumption failed:", consumeError);
  }

  return json({
    success: true,
    teacher_id: activation.teacher_id,
    school_id: activation.school_id,
    credential_consumed: !consumeError,
  });
});
