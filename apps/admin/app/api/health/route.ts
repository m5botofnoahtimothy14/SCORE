import { NextResponse } from 'next/server'
import { createClient, createServiceClient } from '@/lib/supabase/server'
import { APP_VERSION } from '@/lib/version'

// GET /api/health — real operational status, no fabricated metrics.
// Secrets are never returned; only configured/not-configured booleans.
export async function GET() {
  const started = Date.now()
  try {
    const supabase = await createClient()
    const {
      data: { user },
    } = await supabase.auth.getUser()
    if (!user) return NextResponse.json({ error: 'unauthorized' }, { status: 401 })

    // Caller must be an admin (any school) — details stay school-scoped elsewhere.
    const { data: membership } = await supabase
      .from('school_memberships')
      .select('role')
      .eq('user_id', user.id)
      .eq('is_active', true)
      .in('role', ['platform_owner', 'school_admin', 'principal'])
      .limit(1)
      .maybeSingle()
    if (!membership) return NextResponse.json({ error: 'forbidden' }, { status: 403 })

    const admin = createServiceClient()
    const tables = [
      'schools',
      'students',
      'teachers',
      'classes',
      'conversations',
      'messages',
      'announcements',
      'moderation_review_cases',
      'safeguarding_incidents',
      'audit_events',
      'notification_jobs',
      'background_jobs',
    ]
    const tableStatus: Record<string, { ok: boolean; error?: string }> = {}
    for (const t of tables) {
      const { error } = await admin.from(t).select('id').limit(1)
      tableStatus[t] = error ? { ok: false, error: error.message } : { ok: true }
    }

    const { data: failedJobs } = await admin
      .from('notification_jobs')
      .select('id')
      .eq('status', 'failed')
      .limit(100)
    const { data: retryable } = await admin
      .from('background_jobs')
      .select('id')
      .in('status', ['failed', 'retrying'])
      .limit(100)
    const { data: pendingModeration } = await admin
      .from('moderation_review_cases')
      .select('id')
      .in('status', ['pending', 'under_review'])
      .limit(1)
    const { data: lastMessage } = await admin
      .from('messages')
      .select('created_at')
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle()

    const openAi = Boolean(process.env.OPENAI_API_KEY)
    const apilayer = Boolean(process.env.APILAYER_API_KEY)
    const vision = Boolean(process.env.GOOGLE_CLOUD_VISION_API_KEY)

    return NextResponse.json({
      db: { ok: Object.values(tableStatus).every((t) => t.ok) },
      tables: tableStatus,
      providers: {
        // Presence only — values stay server-side.
        // Both the text and image moderation paths run on OpenAI
        // (omni-moderation for images); APILayer is a fallback.
        fcmConfigured: Boolean(process.env.FCM_PROJECT_ID && process.env.FCM_CLIENT_EMAIL),
        textModerationConfigured: openAi || apilayer,
        imageSafetyConfigured: openAi || apilayer || vision,
        moderationPrimary: openAi ? 'openai' : apilayer ? 'apilayer' : null,
        imageSafetyPrimary: vision
          ? 'google_vision'
          : openAi
            ? 'openai-omni'
            : apilayer
              ? 'apilayer'
              : null,
        // Google Cloud Vision SafeSearch is the primary image classifier
        // once it is configured; OpenAI omni-moderation covers the rest.
        cloudVisionConfigured: vision,
        aiInsightsConfigured: Boolean(process.env.GOOGLE_API_KEY || openAi),
        smsConfigured: Boolean(process.env.TEXTBEE_API_KEY),
      },
      queues: {
        failedNotificationJobs: failedJobs?.length ?? 0,
        retryableBackgroundJobs: retryable?.length ?? 0,
        pendingModerationCases: (pendingModeration?.length ?? 0) > 0,
      },
      activity: { lastMessageAt: (lastMessage as { created_at?: string } | null)?.created_at ?? null },
      version: APP_VERSION,
      latencyMs: Date.now() - started,
    })
  } catch (e) {
    return NextResponse.json(
      { error: 'health_check_failed', detail: e instanceof Error ? e.message : 'unknown error' },
      { status: 500 },
    )
  }
}
