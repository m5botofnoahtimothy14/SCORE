'use client'

import { useEffect, useMemo, useState } from 'react'
import { ShieldAlert, RefreshCw } from 'lucide-react'
import { createClient } from '@/lib/supabase/client'
import { PageHeader, Card, StatusBadge, LoadingState, ErrorState } from '@/components/ui'

type ReviewCase = {
  id: string
  moderation_result_id: string
  status: string
  reason_code: string | null
  reviewer_notes: string | null
  disposition: string | null
  assigned_to: string | null
  closed_at: string | null
  created_at: string
}

type ModerationResult = {
  id: string
  verdict: string
  provider: string
  confidence: number | null
  categories: Record<string, unknown> | null
  message_id: string | null
  attachment_id: string | null
  processed_at: string
}

export default function ModerationPage() {
  const [cases, setCases] = useState<ReviewCase[]>([])
  const [results, setResults] = useState<Record<string, ModerationResult>>({})
  const [filter, setFilter] = useState<'pending' | 'under_review' | 'closed' | 'all'>('pending')
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
        .from('moderation_review_cases')
        .select('id, moderation_result_id, status, reason_code, reviewer_notes, disposition, assigned_to, closed_at, created_at')
        .eq('school_id', membership.school_id)
        .order('created_at', { ascending: false })
        .limit(200)
      if (queryError) throw queryError
      const rows = (data ?? []) as ReviewCase[]
      const ids = rows.map((row) => row.moderation_result_id).filter(Boolean)
      if (ids.length) {
        const { data: resultRows, error: resultError } = await supabase
          .from('moderation_results')
          .select('id, verdict, provider, confidence, categories, message_id, attachment_id, processed_at')
          .in('id', ids)
        if (resultError) throw resultError
        setResults(Object.fromEntries(((resultRows ?? []) as ModerationResult[]).map((row) => [row.id, row])))
      } else {
        setResults({})
      }
      setCases(rows)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not load moderation cases.')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { load() }, [])

  const filtered = useMemo(() => {
    if (filter === 'all') return cases
    return cases.filter((item) => item.status === filter)
  }, [cases, filter])

  if (loading) return <LoadingState message="Loading moderation cases…" />
  if (error) return <ErrorState message={error} onRetry={load} />

  return (
    <div>
      <PageHeader title="Moderation review" subtitle="Review cases raised by automated content safety checks." action={<button onClick={load} className="btn-secondary"><RefreshCw className="h-4 w-4" /> Refresh</button>} />
      <div className="mb-5 flex flex-wrap gap-2">
        {(['pending', 'under_review', 'closed', 'all'] as const).map((value) => (
          <button key={value} onClick={() => setFilter(value)} className={filter === value ? 'btn-primary' : 'btn-secondary'}>
            {value === 'all' ? 'All cases' : value.replace('_', ' ')}
          </button>
        ))}
      </div>
      <Card>
        <div className="flex items-center justify-between border-b border-ink-200/70 px-5 py-4">
          <div><h2 className="text-sm font-semibold text-ink-900">Review queue</h2><p className="mt-1 text-xs text-ink-500">{filtered.length} cases in the latest 200 records</p></div>
          <ShieldAlert className="h-5 w-5 text-amber-600" />
        </div>
        {filtered.length === 0 ? (
          <p className="px-5 py-10 text-center text-sm text-ink-500">No cases match this filter.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="data-table">
              <thead><tr><th>Case</th><th>Status</th><th>Reason</th><th>Verdict</th><th>Provider</th><th>Confidence</th><th>Assigned</th><th>Created</th></tr></thead>
              <tbody>
                {filtered.map((item) => {
                  const result = results[item.moderation_result_id]
                  return (
                    <tr key={item.id}>
                      <td className="font-mono text-[11px] text-ink-500">{item.id.slice(0, 10)}</td>
                      <td><StatusBadge value={item.status} /></td>
                      <td className="text-xs text-ink-600">{item.reason_code ?? '—'}</td>
                      <td>{result ? <StatusBadge value={result.verdict} /> : '—'}</td>
                      <td className="text-xs text-ink-600">{result?.provider ?? '—'}</td>
                      <td className="text-xs tabular-nums text-ink-600">{result?.confidence == null ? '—' : String(Math.round(result.confidence * 100)) + '%'}</td>
                      <td className="font-mono text-[10px] text-ink-500">{item.assigned_to?.slice(0, 8) ?? 'Unassigned'}</td>
                      <td className="text-xs text-ink-500">{new Date(item.created_at).toLocaleString()}</td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}
      </Card>
      <p className="mt-4 text-xs leading-5 text-ink-500">This screen displays the current review queue. Case assignment and disposition actions must use the secured review workflow; no client-side status override is exposed here.</p>
    </div>
  )
}
