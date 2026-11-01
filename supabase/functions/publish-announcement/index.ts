import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

function json(body: Record<string, unknown>, status = 200) {
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

  let body: {
    school_id?: string;
    title?: string;
    body?: string;
    category?: string;
    audience_type?: string;
    class_id?: string;
    requires_ack?: boolean;
  };
  try {
    body = await req.json();
  } catch {
    return json({ success: false, error: "invalid_body" }, 400);
  }

  const schoolId = body.school_id?.trim();
  const title = body.title?.trim();
  const bodyText = body.body?.trim();
  const category = body.category;
  const audienceType = body.audience_type;
  const classId = body.class_id?.trim() || null;

  if (!schoolId || !title || !bodyText || !category || !audienceType) {
    return json({ success: false, error: "invalid_body" }, 400);
  }
  if (title.length > 160 || bodyText.length > 12000) {
    return json({ success: false, error: "content_too_long" }, 400);
  }
  if (!["general", "academic", "event", "safety", "priority_alert"].includes(category)) {
    return json({ success: false, error: "invalid_category" }, 400);
  }
  if (!["school_wide", "class", "staff", "leadership", "custom"].includes(audienceType)) {
    return json({ success: false, error: "invalid_audience" }, 400);
  }
  if (audienceType === "class" && !classId) {
    return json({ success: false, error: "class_required" }, 400);
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const { data: membership, error: membershipError } = await supabase
    .from("school_memberships")
    .select("role")
    .eq("user_id", user.id)
    .eq("school_id", schoolId)
    .eq("is_active", true)
    .maybeSingle();

  if (membershipError || !membership ||
      !["platform_owner", "school_admin", "principal"].includes(membership.role)) {
    return json({ success: false, error: "forbidden" }, 403);
  }

  if (classId) {
    const { data: schoolClass, error: classError } = await supabase
      .from("classes")
      .select("id")
      .eq("id", classId)
      .eq("school_id", schoolId)
      .eq("is_active", true)
      .maybeSingle();
    if (classError || !schoolClass) return json({ success: false, error: "class_not_found" }, 404);
  }

  const now = new Date().toISOString();
  const { data: announcement, error: insertError } = await supabase
    .from("announcements")
    .insert({
      school_id: schoolId,
      author_id: user.id,
      title,
      body: bodyText,
      category,
      audience_type: audienceType,
      class_id: classId,
      requires_ack: body.requires_ack === true,
      is_published: true,
      published_at: now,
      created_at: now,
      updated_at: now,
    })
    .select("id")
    .single();

  if (insertError || !announcement) return json({ success: false, error: "publish_failed" }, 500);

  const { error: queueError } = await supabase.from("background_jobs").insert({
    type: "dispatch-notifications",
    status: "queued",
    payload: {
      announcement_id: announcement.id,
      school_id: schoolId,
      type: "announcement",
    },
    scheduled_for: now,
    created_at: now,
  });

  return json({
    success: true,
    announcement_id: announcement.id,
    recipient_count: null,
    dispatch_status: queueError ? "queue_failed" : "queued",
  }, 200);
});
