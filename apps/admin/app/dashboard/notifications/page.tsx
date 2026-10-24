'use client'

import { useEffect, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { logAudit } from '@/lib/audit'
import { PageHeader, Card, StatusBadge, LoadingState, ErrorState, btnSecondary, useToast, EmptyState } from '@/components/ui'

interface Job {
  id: string
  type: string
  title: string
  created_at: string
  status: string
  failure_reason: string | null
}

// Notification diagnostics: real job rows, retry for failed, test ping to
// self. Truthful FCM status comes from /api/health (never fake success).
export default function NotificationsPage() {
  const [jobs, setJobs] = useState<Job[]>([])
  const [statusFilter, setStatusFilter] = useState('failed')
  const [fcmConfigured, setFcmConfigured] = useState<boolean | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [schoolId, setSchoolId] = useState<string | null>(null)
  const [userId, setUserId] = useState<string | null>(null)
  const { show, node } = useToast()

  async function load() {
    setLoading(true)
    setError(null)
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('Not signed in.')
      setUserId(user.id)
      const { data: membership } = await supabase.from('school_memberships').select('school_id')
        .eq('user_id', user.id).eq('is_active', true)
        .in('role', ['platform_owner', 'school_admin', 'principal'])
        .order('joined_at', { ascending: true }).limit(1).maybeSingle()
      const sid = (membership as { school_id: string } | null)?.school_id
      if (!sid) throw new Error('No school scope.')
      setSchoolId(sid)
      const { data, error } = await supabase.from('notification_jobs')
        .select('id, type, title, created_at, status, failure_reason')
        .eq('school_id', sid).eq('status', statusFilter)
        .order('created_at', { ascending: false }).limit(100)
      if (error) throw error
      setJobs((data ?? []) as Job[])
      const health = await fetch('/api/health').then((r) => (r.ok ? r.json() : null)).catch(() => null)
      setFcmConfigured(health ? Boolean(health.providers?.fcmConfigured) : false)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load notification jobs.')
    } finally {
      setLoading(false)
    }
  }

  // Re-query whenever the status tab changes (was only loading once).
  useEffect(() => { load() }, [statusFilter]) // eslint-disable-line react-hooks/exhaustive-deps

  // Drain pending jobs through the server route; returns the real send result.
  async function dispatch(): Promise<{ sent: number; failed: number }> {
    const res = await fetch('/api/notifications/dispatch', { method: 'POST' })
    const data = await res.json().catch(() => ({}))
    if (!res.ok) throw new Error(data.detail || data.error || 'Dispatch failed.')
    return { sent: data?.result?.sent ?? 0, failed: data?.result?.failed ?? 0 }
  }

  async function retry(id: string) {
    try {
      const supabase = createClient()
      const { error } = await supabase.from('notification_jobs')
        .update({ status: 'pending', failure_reason: null, failed_at: null })
        .eq('id', id)
      if (error) throw error
      await logAudit(supabase, userId!, { schoolId, action: 'notification.retry', targetType: 'notification_job', targetId: id, outcome: 'success' })
      const { sent } = await dispatch()
      show(true, `Job re-queued — ${sent} sent.`)
      load()
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'Retry failed.')
    }
  }

  async function testPing() {
    if (!fcmConfigured) {
      show(false, 'FCM is not configured — set the Firebase service-account secrets (FCM_PROJECT_ID / FCM_CLIENT_EMAIL / FCM_PRIVATE_KEY) first. No test was sent.')
      return
    }
    try {
      const supabase = createClient()
      const { error } = await supabase.from('notification_jobs').insert({
        school_id: schoolId, recipient_id: userId, type: 'announcement',
        title: 'Test notification', body: 'This is a connectivity test from the DMS.',
        data: { type: 'announcement', school_id: schoolId },
        idempotency_key: `test:${userId}:${Date.now()}`,
      })
      if (error) throw error
      const { sent } = await dispatch()
      show(sent > 0, sent > 0 ? 'Test notification sent.' : 'Queued, but no active device received it (register a device first).')
      load()
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'Test failed.')
    }
  }

  if (loading) return <LoadingState />
  if (error) return <ErrorState message={error} onRetry={load} />

  return (
    <div>
      {node}
      <PageHeader
        title="Notifications"
        subtitle={fcmConfigured === false ? 'FCM is NOT configured — push dispatch is disabled.' : 'Dispatch diagnostics and retry'}
        action={<button onClick={testPing} className={btnSecondary}>Send test to self</button>}
      />
      <div className="flex gap-2 mb-4">
        {['failed', 'pending', 'sent', 'skipped'].map((s) => (
          <button key={s} onClick={() => { setStatusFilter(s); }} className={s === statusFilter ? 'px-4 py-2 bg-brand-600 text-white text-sm rounded-lg' : btnSecondary}>
            {s}
          </button>
        ))}
        <button onClick={load} className={btnSecondary}>Refresh</button>
      </div>
      <Card>
        {jobs.length === 0 ? <EmptyState title={`No ${statusFilter} jobs`} /> : (
          <table className="w-full text-sm">
            <thead><tr className="text-left text-ink-600 text-xs border-b">
              <th className="p-3">Title</th><th>Type</th><th>Status</th><th>Reason</th><th>Queued</th><th className="text-right pr-3">Retry</th>
            </tr></thead>
            <tbody>
              {jobs.map((j) => (
                <tr key={j.id} className="border-b border-ink-200 last:border-0">
                  <td className="p-3 max-w-xs truncate">{j.title}</td>
                  <td className="text-xs">{j.type}</td>
                  <td><StatusBadge value={j.status} /></td>
                  <td className="text-xs text-ink-600 max-w-xs truncate">{j.failure_reason ?? '—'}</td>
                  <td className="text-xs text-ink-600">{new Date(j.created_at).toLocaleString()}</td>
                  <td className="text-right pr-3">
                    {j.status === 'failed' && <button onClick={() => retry(j.id)} className="text-brand-600 text-xs hover:underline">Re-queue</button>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </Card>
    </div>
  )
}
