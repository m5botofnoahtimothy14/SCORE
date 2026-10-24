'use client'

import { useEffect, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { logAudit } from '@/lib/audit'
import { PageHeader, Card, StatusBadge, LoadingState, ErrorState, btnSecondary, useToast } from '@/components/ui'

interface Health {
  db: { ok: boolean }
  tables: Record<string, { ok: boolean; error?: string }>
  providers: { fcmConfigured: boolean; textModerationConfigured: boolean; imageSafetyConfigured: boolean; smsConfigured: boolean }
  queues: { failedNotificationJobs: number; retryableBackgroundJobs: number; pendingModerationCases: boolean }
  activity: { lastMessageAt: string | null }
  version: string
  latencyMs: number
}

// System health: ONLY real data from /api/health. Nothing is fabricated.
// Unreachable services report as errors, not as healthy.
export default function HealthPage() {
  const [health, setHealth] = useState<Health | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [schoolId, setSchoolId] = useState<string | null>(null)
  const [userId, setUserId] = useState<string | null>(null)
  const [isOwner, setIsOwner] = useState(false)
  const { show, node } = useToast()

  async function load() {
    setError(null)
    try {
      const res = await fetch('/api/health')
      if (!res.ok) throw new Error(`Health endpoint returned ${res.status}.`)
      const data = await res.json()
      setHealth(data as Health)
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('Not signed in.')
      setUserId(user.id)
      const { data: membership } = await supabase.from('school_memberships').select('school_id, role')
        .eq('user_id', user.id).eq('is_active', true)
        .in('role', ['platform_owner', 'school_admin', 'principal'])
        .order('joined_at', { ascending: true }).limit(1).maybeSingle()
      setSchoolId((membership as { school_id: string } | null)?.school_id ?? null)
      setIsOwner((membership as { role: string } | null)?.role === 'platform_owner')
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Health check failed.')
    }
  }

  useEffect(() => { load() }, [])

  async function retryBackgroundJobs() {
    if (!isOwner) {
      show(false, 'Only a Super Admin can re-queue background jobs.')
      return
    }
    try {
      const supabase = createClient()
      const { data: updated, error } = await supabase.from('background_jobs')
        .update({ status: 'queued', attempts: 0, last_error: null })
        .in('status', ['failed', 'retrying'])
        .select('id')
      if (error) throw error
      if (!updated?.length) {
        show(false, 'No failed background jobs to re-queue.')
        return
      }
      await logAudit(supabase, userId!, { schoolId, action: 'jobs.retry', targetType: 'background_jobs', outcome: 'success' })
      show(true, `${updated.length} job(s) re-queued.`)
      load()
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'Retry failed.')
    }
  }

  if (error) return <ErrorState message={error} onRetry={load} />
  if (!health) return <LoadingState message="Checking systems..." />

  const ok = (v: boolean) => <StatusBadge value={v ? 'approved' : 'blocked'} />

  return (
    <div>
      {node}
      <PageHeader
        title="System Health"
        subtitle={`v${health.version} · checked in ${health.latencyMs}ms · last message ${health.activity.lastMessageAt ? new Date(health.activity.lastMessageAt).toLocaleString() : 'never'}`}
      />
      <div className="mb-4 rounded-2xl border border-slate-200 bg-slate-50/80 p-3 text-sm text-slate-700 shadow-soft">
        <div className="flex items-center justify-between gap-3">
          <span className="font-semibold text-slate-900">Threat and service log</span>
          <span className="text-xs text-slate-500">{new Date().toLocaleString()}</span>
        </div>
        <p className="mt-1 text-sm text-slate-600">
          {health.db.ok ? 'Database health is stable.' : 'Database connectivity is degraded and needs attention.'}
        </p>
      </div>
      <div className="grid md:grid-cols-2 gap-4">
        <Card className="p-4">
          <h2 className="font-semibold mb-3">Database {ok(health.db.ok)}</h2>
          <table className="w-full text-sm">
            <tbody>
              {Object.entries(health.tables).map(([t, s]) => (
                <tr key={t} className="border-b border-ink-200 last:border-0">
                  <td className="py-1.5 font-mono text-xs">{t}</td>
                  <td className="text-right">{ok(s.ok)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </Card>
        <div className="space-y-4">
          <Card className="p-4">
            <h2 className="font-semibold mb-3">Providers</h2>
            <div className="space-y-2 text-sm">
              <div className="flex justify-between"><span>FCM push</span>{ok(health.providers.fcmConfigured)}</div>
              <div className="flex justify-between"><span>Text moderation</span>{ok(health.providers.textModerationConfigured)}</div>
              <div className="flex justify-between"><span>Image safety</span>{ok(health.providers.imageSafetyConfigured)}</div>
              <div className="flex justify-between"><span>SMS (OTP)</span>{ok(health.providers.smsConfigured)}</div>
            </div>
            <p className="mt-3 text-xs text-ink-600">
              Unconfigured providers fail closed: messages are held for review, uploads are quarantined, and OTP requests are rejected with an explicit error.
            </p>
          </Card>
          <Card className="p-4">
            <h2 className="font-semibold mb-3">Queues</h2>
            <div className="space-y-2 text-sm">
              <div className="flex justify-between"><span>Failed notification jobs</span><b>{health.queues.failedNotificationJobs}</b></div>
              <div className="flex justify-between"><span>Retryable background jobs</span><b>{health.queues.retryableBackgroundJobs}</b></div>
              <div className="flex justify-between"><span>Pending moderation cases</span><b>{health.queues.pendingModerationCases ? 'yes' : 'no'}</b></div>
            </div>
            <div className="flex gap-2 mt-3">
              {isOwner && <button onClick={retryBackgroundJobs} className={btnSecondary}>Re-queue failed jobs</button>}
              <button onClick={load} className={btnSecondary}>Refresh</button>
            </div>
            <p className="mt-3 text-xs text-ink-600">
              Realtime liveness is not directly measurable from here. Verify delivery in the mobile app and check the Supabase Dashboard → Realtime inspector for live data.
            </p>
          </Card>
        </div>
      </div>
    </div>
  )
}
