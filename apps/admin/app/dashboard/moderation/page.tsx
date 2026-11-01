'use client'

import { useEffect, useMemo, useState } from 'react'
import { ShieldAlert, Image, MessageSquare, RefreshCw } from 'lucide-react'
import { createClient } from '@/lib/supabase/client'
import { PageHeader, Card, StatusBadge, LoadingState, ErrorState } from '@/components/ui'

type ModerationEvent = {
  id: string
  verdict: string
  provider: string
  confidence: number | null
  categories: Record<string, unknown> | null
  message_id: string | null
  attachment_id: string | null
  reviewed_by: string | null
  reviewed_at: string | null
  created_at: string
}

export default function ModerationPage() {
  const [events, setEvents] = useState<ModerationEvent[]>([])
  const [filter, setFilter] = useState<'all' | 'held' | 'blocked'>('held')
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)

  async function load() {
    setLoading(true)
    setError(null)
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('Not signed in.')
      const { data: membership } = await supabase
        .from('school_memberships')
        .select('school_id')
        .eq('user_id', user.id)
        .eq('is_active', true)
        .in('role', ['platform_owner', 'school_admin', 'principal'])
        .order('joined_at', { ascending: false })
        .limit(1)
        .maybeSingle()
      if (!membership) throw new Error('No administrator access.')
      const { data, error: queryError } = await supabase
        .from('moderation_events')
        .select('id, verdict, provider, confidence, categories, message_id, attachment_id, reviewed_by, reviewed_at, created_at')
        .eq('school_id', membership.school_id)
        .order('created_at', { ascending: false })
        .limit(200)
      if (queryError) throw queryError
      setEvents((data ?? []) as ModerationEvent[])
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not load moderation events.')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { load() }, [])

  const filtered = useMemo(() => {
    if (filter === 'all') return events
    return events.filter((event) => event.verdict === filter)
  }, [events, filter])

  if (loading) return <LoadingState message="Loading moderation events…" />
  if (error) return <ErrorState message={error} onRetry={load} />

  return (
    <div>
      <PageHeader
        title="Moderation review"
        subtitle="Held and blocked content events for your school."
        action={<button onClick={load} className="btn-secondary"><RefreshCw className="h-4 w-4" /> Refresh</button>}
      />
      <div className="mb-5 flex flex-wrap gap-2">
        {(['held', 'blocked', 'all'] as const).map((value) => (
          <button key={value} onClick={() => setFilter(value)} className={filter === value ? 'btn-primary' : 'btn-secondary'}>
            {value === 'all' ? 'All events' : value === 'held' ? 'Held for review' : 'Blocked'}
          </button>
        ))}
      </div>
      <Card>
        <div className="flex items-center justify-between border-b border-ink-200/70 px-5 py-4">
          <div>
            <h2 className="text-sm font-semibold text-ink-900">Moderation event log</h2>
            <p className="mt-1 text-xs text-ink-500">{filtered.length} events in the latest 200 records</p>
          </div>
          <ShieldAlert className="h-5 w-5 text-amber-600" />
        </div>
        {filtered.length === 0 ? (
          <p className="px-5 py-10 text-center text-sm text-ink-500">No events match this filter.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="data-table">
              <thead><tr><th>Verdict</th><th>Content reference</th><th>Provider</th><th>Confidence</th><th>Reviewed</th><th>Created</th></tr></thead>
              <tbody>
                {filtered.map((event) => (
                  <tr key={event.id}>
                    <td><StatusBadge value={event.verdict} /></td>
                    <td>
                      <span className="inline-flex items-center gap-2 font-mono text-[11px] text-ink-600">
                        {event.message_id ? <MessageSquare className="h-3.5 w-3.5" /> : <Image className="h-3.5 w-3.5" />}
                        {(event.message_id ?? event.attachment_id ?? event.id).slice(0, 12)}
                      </span>
                    </td>
                    <td className="text-xs text-ink-600">{event.provider}</td>
                    <td className="text-xs tabular-nums text-ink-600">{event.confidence == null ? '—' : String(Math.round(event.confidence * 100)) + '%'}</td>
                    <td className="text-xs text-ink-500">{event.reviewed_at ? new Date(event.reviewed_at).toLocaleString() : 'Not reviewed'}</td>
                    <td className="text-xs text-ink-500">{new Date(event.created_at).toLocaleString()}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>
      <p className="mt-4 text-xs leading-5 text-ink-500">
        This page is a read-only event log. Review and override actions are not available until the server-side moderation workflow is implemented and secured.
      </p>
    </div>
  )
}
