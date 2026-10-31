// ============================================================
// Edge Function: activate-student
// Validates activation code and links student to auth user
// ============================================================
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

  let body: { student_id_no?: string; activation_code?: string; device_secret?: string } = {};
  try { body = await req.json(); } catch { return jsonError("invalid_body", 400); }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  // Call the database RPC
  const { data, error } = await supabase.rpc("activate_student", {
    p_student_id_no: body.student_id_no,
    p_activation_code: body.activation_code,
    p_device_secret: body.device_secret,
  });

  if (error) {
    return jsonError(error.message || "activation_failed", 400);
  }

  if (!data || !data.success) {
    return jsonError(data?.error || "activation_failed", 400);
  }

  return new Response(JSON.stringify({
    success: true,
    student_id: data.student_id,
    class_id: data.class_id,
    school_id: data.school_id,
  }), { status: 200, headers: { "Content-Type": "application/json" } });
});