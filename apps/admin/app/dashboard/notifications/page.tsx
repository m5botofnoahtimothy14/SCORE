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
        .eq('user_id', user.id).eq('is_active', true).limit(1).maybeSingle()
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

  useEffect(() => { load() }, [])

  async function retry(id: string) {
    try {
      const supabase = createClient()
      const { error } = await supabase.from('notification_jobs')
        .update({ status: 'pending', failure_reason: null, failed_at: null })
        .eq('id', id)
      if (error) throw error
      await logAudit(supabase, userId!, { schoolId, action: 'notification.retry', targetType: 'notification_job', targetId: id, outcome: 'success' })
      show(true, 'Job re-queued for dispatch.')
      load()
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'Retry failed.')
    }
  }

  async function testPing() {
    if (!fcmConfigured) {
      show(false, 'FCM is not configured — set FCM_SERVER_KEY / FCM_PROJECT_ID first. No test was sent.')
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
      show(true, 'Test queued. Check your device — dispatch runs via the edge function.')
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
          <button key={s} onClick={() => { setStatusFilter(s); }} className={s === statusFilter ? 'px-4 py-2 bg-blue-600 text-white text-sm rounded-lg' : btnSecondary}>
            {s}
          </button>
        ))}
        <button onClick={load} className={btnSecondary}>Refresh</button>
      </div>
      <Card>
        {jobs.length === 0 ? <EmptyState title={`No ${statusFilter} jobs`} /> : (
          <table className="w-full text-sm">
            <thead><tr className="text-left text-gray-500 text-xs border-b">
              <th className="p-3">Title</th><th>Type</th><th>Status</th><th>Reason</th><th>Queued</th><th className="text-right pr-3">Retry</th>
            </tr></thead>
            <tbody>
              {jobs.map((j) => (
                <tr key={j.id} className="border-b border-gray-100 last:border-0">
                  <td className="p-3 max-w-xs truncate">{j.title}</td>
                  <td className="text-xs">{j.type}</td>
                  <td><StatusBadge value={j.status} /></td>
                  <td className="text-xs text-gray-500 max-w-xs truncate">{j.failure_reason ?? '—'}</td>
                  <td className="text-xs text-gray-500">{new Date(j.created_at).toLocaleString()}</td>
                  <td className="text-right pr-3">
                    {j.status === 'failed' && <button onClick={() => retry(j.id)} className="text-blue-600 text-xs hover:underline">Re-queue</button>}
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
