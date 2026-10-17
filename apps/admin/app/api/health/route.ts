import { NextResponse } from 'next/server'
import { createClient, createServiceClient } from '@/lib/supabase/server'

// GET /api/health — real operational status, no fabricated metrics.
// Secrets are never returned; only configured/not-configured booleans.
export async function GET() {
  const started = Date.now()
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

  return NextResponse.json({
    db: { ok: Object.values(tableStatus).every((t) => t.ok) },
    tables: tableStatus,
    providers: {
      // Presence only — values stay server-side.
      fcmConfigured: Boolean(process.env.FCM_PROJECT_ID || process.env.FCM_CLIENT_EMAIL),
      textModerationConfigured: Boolean(process.env.OPENAI_API_KEY),
      imageSafetyConfigured: Boolean(process.env.APILAYER_API_KEY),
      smsConfigured: Boolean(process.env.TEXTBEE_API_KEY),
    },
    queues: {
      failedNotificationJobs: failedJobs?.length ?? 0,
      retryableBackgroundJobs: retryable?.length ?? 0,
      pendingModerationCases: (pendingModeration?.length ?? 0) > 0,
    },
    activity: { lastMessageAt: (lastMessage as { created_at?: string } | null)?.created_at ?? null },
    version: process.env.npm_package_version ?? '1.0.0',
    latencyMs: Date.now() - started,
  })
}
