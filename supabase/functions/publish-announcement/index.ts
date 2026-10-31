// ============================================================
// Edge Function: publish-announcement
// Publishes an announcement to the school audience
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

  let body: {
    school_id?: string;
    title?: string;
    body?: string;
    category?: string;
    audience_type?: string;
    class_id?: string;
    requires_ack?: boolean;
  } = {};
  try { body = await req.json(); } catch { return jsonError("invalid_body", 400); }

  const { school_id, title, body: bodyText, category, audience_type, class_id, requires_ack } = body;

  if (!school_id || !title || !bodyText || !category || !audience_type) {
    return jsonError("invalid_body", 400);
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  // Verify admin role
  const { data: membership } = await supabase
    .from("school_memberships")
    .select("role")
    .eq("user_id", user.id)
    .eq("school_id", school_id)
    .eq("is_active", true)
    .single();

  if (!membership || !["platform_owner", "school_admin", "principal"].includes(membership.role)) {
    return jsonError("forbidden", 403);
  }

  const { data: announcement, error } = await supabase
    .from("announcements")
    .insert({
      school_id,
      author_id: user.id,
      title,
      body: bodyText,
      category,
      audience_type,
      class_id: class_id || null,
      requires_ack: requires_ack ?? false,
      is_published: true,
      published_at: new Date().toISOString(),
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    })
    .select()
    .single();

  if (error) {
    return jsonError("publish_failed", 500);
  }

  // Create notification job
  await supabase.from("background_jobs").insert({
    type: "dispatch-notifications",
    status: "queued",
    payload: JSON.stringify({
      announcement_id: announcement.id,
      school_id,
      type: "announcement",
    }),
    scheduled_for: new Date().toISOString(),
    created_at: new Date().toISOString(),
  });

  return new Response(JSON.stringify({
    success: true,
    announcement_id: announcement.id,
    recipient_count: 0,
  }), { status: 200, headers: { "Content-Type": "application/json" } });
});