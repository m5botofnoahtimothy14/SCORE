// ============================================================
// Edge Function: publish-announcement
// Server-side announcement publishing with audience resolution
// ============================================================
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, content-type",
      },
    });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return jsonError("unauthorized", 401);

    // Get requesting user
    const userClient = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: authError } = await userClient.auth.getUser();
    if (authError || !user) return jsonError("unauthorized", 401);

    const body = await req.json();
    const { school_id, title, body: bodyText, category, audience_type, class_id, requires_ack } = body;

    if (!school_id || !title || !bodyText || !audience_type) return jsonError("missing_fields", 400);

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Verify author permissions
    const { data: membership } = await supabase
      .from("school_memberships")
      .select("role")
      .eq("user_id", user.id)
      .eq("school_id", school_id)
      .eq("is_active", true)
      .single();

    if (!membership) return jsonError("forbidden", 403);

    const adminRoles = ["platform_owner", "school_admin", "principal"];
    const teacherRoles = ["teacher", "head_teacher"];

    // Role-based audience permission check
    if (audience_type === "school_wide" && !adminRoles.includes(membership.role)) {
      // Log unauthorized attempt
      await supabase.from("audit_events").insert({
        school_id,
        actor_id: user.id,
        action: "announcement.publish.unauthorized",
        target_type: "announcement",
        outcome: "rejected",
        reason: "insufficient_role_for_school_wide",
        metadata: { attempted_audience: audience_type, role: membership.role },
      });
      return jsonError("insufficient_permissions_for_audience", 403);
    }

    if (category === "priority_alert" && !adminRoles.includes(membership.role)) {
      return jsonError("priority_alerts_require_admin", 403);
    }

    if (!adminRoles.includes(membership.role) && !teacherRoles.includes(membership.role)) {
      return jsonError("forbidden", 403);
    }

    // Teachers can only target their assigned classes
    if (teacherRoles.includes(membership.role) && audience_type === "class" && class_id) {
      const { data: assignment } = await supabase
        .from("teaching_assignments")
        .select("id")
        .eq("class_id", class_id)
        .eq("school_id", school_id)
        .in("teacher_id", [
          supabase.from("teachers").select("id").eq("user_id", user.id).eq("school_id", school_id),
        ]);

      if (!assignment) return jsonError("not_assigned_to_class", 403);
    }

    // Create announcement
    const { data: announcement, error: annError } = await supabase
      .from("announcements")
      .insert({
        school_id,
        author_id: user.id,
        title,
        body: bodyText,
        category: category ?? "general",
        audience_type,
        class_id: class_id ?? null,
        requires_ack: requires_ack ?? false,
        is_published: true,
        published_at: new Date().toISOString(),
      })
      .select("id")
      .single();

    if (annError || !announcement) {
      return jsonError("failed_to_create", 500);
    }

    // Resolve audience recipients
    const recipientIds = await resolveAudience(supabase, school_id, audience_type, class_id);

    if (recipientIds.length > 0) {
      // Insert recipients in batches
      const BATCH = 500;
      for (let i = 0; i < recipientIds.length; i += BATCH) {
        const chunk = recipientIds.slice(i, i + BATCH).map(uid => ({
          announcement_id: announcement.id,
          user_id: uid,
        }));
        await supabase.from("announcement_recipients").insert(chunk);
      }

      // Queue notification jobs
      const notifJobs = recipientIds.map(uid => ({
        school_id,
        recipient_id: uid,
        type: category === "priority_alert" ? "alert" : "announcement",
        title: category === "priority_alert" ? `🚨 ${title}` : title,
        body: "Tap to read the announcement",
        data: { type: "announcement", announcement_id: announcement.id, school_id },
        idempotency_key: `ann_notif:${announcement.id}:${uid}`,
      }));

      for (let i = 0; i < notifJobs.length; i += BATCH) {
        await supabase.from("notification_jobs").insert(notifJobs.slice(i, i + BATCH));
      }

      // Dispatch notifications
      supabase.functions.invoke("dispatch-notifications", { body: { school_id } });
    }

    await supabase.from("audit_events").insert({
      school_id,
      actor_id: user.id,
      action: "announcement.publish",
      target_type: "announcement",
      target_id: announcement.id,
      outcome: "success",
      metadata: { audience_type, recipient_count: recipientIds.length },
    });

    return new Response(
      JSON.stringify({ success: true, announcement_id: announcement.id, recipient_count: recipientIds.length }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error("publish-announcement error:", err);
    return jsonError("server_error", 500);
  }
});

async function resolveAudience(
  supabase: ReturnType<typeof createClient>,
  schoolId: string,
  audienceType: string,
  classId?: string
): Promise<string[]> {
  let query = supabase
    .from("school_memberships")
    .select("user_id")
    .eq("school_id", schoolId)
    .eq("is_active", true);

  switch (audienceType) {
    case "school_wide":
      // Everyone in the school
      break;

    case "class":
      if (!classId) return [];
      // Students enrolled in the class + teachers assigned to it
      const { data: enrollments } = await supabase
        .from("class_enrollments")
        .select("students!inner(user_id)")
        .eq("class_id", classId)
        .is("unenrolled_at", null);

      const { data: assignments } = await supabase
        .from("teaching_assignments")
        .select("teachers!inner(user_id)")
        .eq("class_id", classId);

      const studentIds = (enrollments ?? [])
        .map((e: any) => e.students?.user_id)
        .filter(Boolean);

      const teacherIds = (assignments ?? [])
        .map((a: any) => a.teachers?.user_id)
        .filter(Boolean);

      return [...new Set([...studentIds, ...teacherIds])];

    case "staff":
      query = query.in("role", ["teacher", "head_teacher", "principal", "school_admin"]);
      break;

    case "leadership":
      query = query.in("role", ["principal", "head_teacher"]);
      break;

    default:
      return [];
  }

  const { data } = await query;
  return (data ?? []).map((m: any) => m.user_id).filter(Boolean);
}

function jsonError(error: string, status: number) {
  return new Response(JSON.stringify({ success: false, error }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
