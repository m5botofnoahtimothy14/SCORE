import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

function jsonError(code: string, status = 400) {
  return new Response(JSON.stringify({ success: false, error: code }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function sha256Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hash)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function verifyCode(input: string, stored: string): Promise<boolean> {
  // bcrypt codes start with $2a$ or $2b$
  if (stored.startsWith("$2a$") || stored.startsWith("$2b$")) {
    // Deno doesn't have bcrypt built-in; compare via SHA-256 of the input
    // as a fallback when bcrypt verification isn't available in the edge.
    // The RPC (activate_student) handles bcrypt via crypt(); the edge
    // function accepts SHA-256 hex codes issued by the DMS API.
    return false;
  }
  // SHA-256 hex comparison (DMS-issued codes)
  const inputHash = await sha256Hex(input);
  return inputHash === stored;
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

  if (req.method !== "POST") return jsonError("method_not_allowed", 405);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return jsonError("unauthorized", 401);

  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) return jsonError("unauthorized", 401);

  let body: { student_id_no?: string; activation_code?: string; device_secret?: string } = {};
  try { body = await req.json(); } catch { return jsonError("invalid_body", 400); }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  const { data: student, error: sErr } = await supabase
    .from("students")
    .select("id, school_id, first_name, last_name, is_active")
    .eq("student_id_no", (body.student_id_no ?? "").trim())
    .eq("is_active", true)
    .maybeSingle();

  if (sErr || !student) return jsonError("student_not_found", 404);

  const { data: cred, error: cErr } = await supabase
    .from("student_activation_credentials")
    .select("id, code, code_hash, expires_at, used_at")
    .eq("student_id", student.id)
    .maybeSingle();

  if (cErr || !cred) return jsonError("no_activation_code", 404);

  const inputCode = (body.activation_code ?? "").trim().toUpperCase();
  const stored = cred.code_hash ?? cred.code;
  if (!stored || !(await verifyCode(inputCode, stored))) return jsonError("invalid_credentials", 400);

  // Support returning students: mark code as used (idempotent)
  if (!cred.used_at) {
    // Check expiry only for first-time activation
    if (new Date(cred.expires_at) <= new Date()) return jsonError("code_expired", 400);
    await supabase.from("student_activation_credentials").update({ used_at: new Date().toISOString() }).eq("id", cred.id);
  }

  await supabase.from("students").update({ user_id: user.id, updated_at: new Date().toISOString() }).eq("id", student.id);

  await supabase.from("user_profiles").upsert({
    id: user.id,
    display_name: `${student.first_name} ${student.last_name}`,
    is_active: true,
    updated_at: new Date().toISOString(),
  }, { onConflict: "id" });

  await supabase.from("school_memberships").upsert({
    user_id: user.id,
    school_id: student.school_id,
    role: "student",
    is_active: true,
    joined_at: new Date().toISOString(),
  }, { onConflict: "user_id,school_id,role" });

  // class id
  const { data: enroll } = await supabase
    .from("class_enrollments")
    .select("class_id")
    .eq("student_id", student.id)
    .is("unenrolled_at", null)
    .limit(1)
    .maybeSingle();

  return new Response(JSON.stringify({
    success: true,
    student_id: student.id,
    class_id: enroll?.class_id ?? null,
    school_id: student.school_id,
    email: user.email,
  }), { status: 200, headers: { "Content-Type": "application/json" } });
});