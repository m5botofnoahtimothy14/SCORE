// ============================================================
// Edge Function: activate-student
// Validates a one-time activation code and links the student to
// the authenticated device session. The database RPC performs
// the final single-use activation mutation.
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

function jsonError(code: string, status = 400) {
  return new Response(JSON.stringify({ success: false, error: code }), {
    status,
    headers: CORS_HEADERS,
  });
}

async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return Array.from(new Uint8Array(digest))
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");
}

function safeEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return difference === 0;
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") return jsonError("method_not_allowed", 405);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return jsonError("unauthorized", 401);

  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) return jsonError("unauthorized", 401);

  let body: {
    student_id_no?: string;
    activation_code?: string;
    device_secret?: string;
  };
  try {
    body = await req.json();
  } catch {
    return jsonError("invalid_body", 400);
  }

  const studentIdNo = body.student_id_no?.trim();
  const activationCode = body.activation_code?.trim();
  if (!studentIdNo || !activationCode || activationCode.length > 128) {
    return jsonError("invalid_credentials", 400);
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  const { data: student, error: studentError } = await supabase
    .from("students")
    .select("id")
    .eq("student_id_no", studentIdNo)
    .eq("is_active", true)
    .maybeSingle();

  if (studentError || !student) return jsonError("student_not_found", 404);

  const { data: credential, error: credentialError } = await supabase
    .from("student_activation_credentials")
    .select("id, code_hash, code_salt, expires_at, used_at")
    .eq("student_id", student.id)
    .is("used_at", null)
    .gt("expires_at", new Date().toISOString())
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (credentialError || !credential) return jsonError("invalid_credentials", 400);
  if (!credential.code_hash || !credential.code_salt) {
    return jsonError("invalid_credentials", 400);
  }

  const submittedHash = await sha256Hex(`${activationCode}:${credential.code_salt}`);
  if (!safeEqual(submittedHash, credential.code_hash)) {
    return jsonError("invalid_credentials", 400);
  }

  // The RPC marks the selected unused code as used and creates the membership.
  // The RPC must also enforce this hash check before direct client execution is
  // disabled in the database hardening phase.
  const { data, error } = await supabase.rpc("activate_student", {
    p_student_id_no: studentIdNo,
    p_activation_code: activationCode,
    p_device_secret: body.device_secret ?? "",
  });

  if (error) return jsonError("activation_failed", 400);
  if (!data || data.success !== true) {
    return jsonError(data?.error || "activation_failed", 400);
  }

  return new Response(JSON.stringify({
    success: true,
    student_id: data.student_id,
    class_id: data.class_id,
    school_id: data.school_id,
  }), { status: 200, headers: CORS_HEADERS });
});
