'use client'

import { useEffect, useMemo, useState } from 'react'
import { AlertTriangle, RefreshCw } from 'lucide-react'
import { createClient } from '@/lib/supabase/client'
import { PageHeader, Card, StatusBadge, LoadingState, ErrorState } from '@/components/ui'

type Incident = {
  id: string
  title: string
  severity: string
  description: string
  status: string
  assigned_to: string | null
  resolved_at: string | null
  created_at: string
}

export default function IncidentsPage() {
  const [items, setItems] = useState<Incident[]>([])
  const [filter, setFilter] = useState<'open' | 'investigating' | 'resolved' | 'all'>('open')
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
        .from('safeguarding_incidents')
        .select('id, title, severity, description, status, assigned_to, resolved_at, created_at')
        .eq('school_id', membership.school_id)
        .order('created_at', { ascending: false })
        .limit(200)
      if (queryError) throw queryError
      setItems((data ?? []) as Incident[])
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not load safeguarding incidents.')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { load() }, [])

  const filtered = useMemo(() => {
    if (filter === 'all') return items
    return items.filter((item) => item.status === filter)
  }, [items, filter])

  if (loading) return <LoadingState message="Loading safeguarding incidents…" />
  if (error) return <ErrorState message={error} onRetry={load} />

  return (
    <div>
      <PageHeader title="Safeguarding incidents" subtitle="Restricted school-level incident records. Access is limited to authorised leadership." action={<button onClick={load} className="btn-secondary"><RefreshCw className="h-4 w-4" /> Refresh</button>} />
      <div className="mb-5 flex flex-wrap gap-2">
        {(['open', 'investigating', 'resolved', 'all'] as const).map((value) => (
          <button key={value} onClick={() => setFilter(value)} className={filter === value ? 'btn-primary' : 'btn-secondary'}>{value === 'all' ? 'All incidents' : value}</button>
        ))}
      </div>
      <Card>
        <div className="flex items-center gap-3 border-b border-ink-200/70 px-5 py-4">
          <AlertTriangle className="h-5 w-5 text-rose-600" />
          <div><h2 className="text-sm font-semibold text-ink-900">Incident register</h2><p className="mt-1 text-xs text-ink-500">{filtered.length} records in the latest 200 incidents</p></div>
        </div>
        {filtered.length === 0 ? (
          <p className="px-5 py-10 text-center text-sm text-ink-500">No incidents match this filter.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="data-table">
              <thead><tr><th>Type</th><th>Severity</th><th>Status</th><th>Description</th><th>Assigned</th><th>Reported</th></tr></thead>
              <tbody>
                {filtered.map((item) => (
                  <tr key={item.id}>
                    <td className="text-xs font-semibold text-ink-800">{item.title}</td>
                    <td><StatusBadge value={item.severity} /></td>
                    <td><StatusBadge value={item.status} /></td>
                    <td className="max-w-sm text-xs text-ink-600">{item.description}</td>
                    <td className="font-mono text-[10px] text-ink-500">{item.assigned_to?.slice(0, 8) ?? 'Unassigned'}</td>
                    <td className="text-xs text-ink-500">{new Date(item.created_at).toLocaleString()}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>
      <p className="mt-4 text-xs leading-5 text-ink-500">This is a restricted read-only register. Use your school’s approved safeguarding procedure for incident response and escalation.</p>
    </div>
  )
}
