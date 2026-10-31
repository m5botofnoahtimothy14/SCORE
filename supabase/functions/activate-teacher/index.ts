import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { createHash } from "https://deno.land/std@0.177.0/crypto/mod.ts";

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

  let body: { staff_id_no?: string; activation_code?: string; device_secret?: string } = {};
  try { body = await req.json(); } catch { return jsonError("invalid_body", 400); }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  const { data: teacher, error: tErr } = await supabase
    .from("teachers")
    .select("id, school_id, first_name, last_name, is_active")
    .eq("staff_id_no", (body.staff_id_no ?? "").trim())
    .eq("is_active", true)
    .maybeSingle();

  if (tErr || !teacher) return jsonError("teacher_not_found", 404);

  const { data: cred, error: cErr } = await supabase
    .from("teacher_activation_credentials")
    .select("id, code, expires_at, used_at")
    .eq("teacher_id", teacher.id)
    .maybeSingle();

  if (cErr || !cred) return jsonError("no_activation_code", 404);
  if (cred.used_at) return jsonError("code_already_used", 400);
  if (new Date(cred.expires_at) <= new Date()) return jsonError("code_expired", 400);

  const inputHash = await sha256Hex((body.activation_code ?? "").trim());
  if (inputHash !== cred.code) return jsonError("invalid_code", 400);

  await supabase.from("teacher_activation_credentials").update({ used_at: new Date().toISOString() }).eq("id", cred.id);

  await supabase.from("teachers").update({ user_id: user.id, updated_at: new Date().toISOString() }).eq("id", teacher.id).is("user_id", null);

  await supabase.from("user_profiles").upsert({
    id: user.id,
    display_name: `${teacher.first_name} ${teacher.last_name}`,
    is_active: true,
    updated_at: new Date().toISOString(),
  }, { onConflict: "id" });

  await supabase.from("school_memberships").upsert({
    user_id: user.id,
    school_id: teacher.school_id,
    role: "teacher",
    is_active: true,
    joined_at: new Date().toISOString(),
  }, { onConflict: "user_id,school_id,role" });

  return new Response(JSON.stringify({
    success: true,
    teacher_id: teacher.id,
    school_id: teacher.school_id,
  }), { status: 200, headers: { "Content-Type": "application/json" } });
});