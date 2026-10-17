'use client'

import { useEffect, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { logAudit } from '@/lib/audit'
import { PageHeader, Card, StatusBadge, LoadingState, ErrorState, inputCls, btnSecondary, useToast, EmptyState } from '@/components/ui'

// Immutable audit trail viewer: filters + pagination + CSV export.
// Exports are themselves audited (action: data.export).
export default function AuditPage() {
  const [rows, setRows] = useState<{ id: string; action: string; outcome: string; target_type: string | null; created_at: string; reason: string | null }[]>([])
  const [actionFilter, setActionFilter] = useState('')
  const [outcomeFilter, setOutcomeFilter] = useState('')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const { show, node } = useToast()

  async function load() {
    setLoading(true)
    setError(null)
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('Not signed in.')
      const { data: membership } = await supabase.from('school_memberships').select('school_id')
        .eq('user_id', user.id).eq('is_active', true).limit(1).maybeSingle()
      const sid = (membership as { school_id: string } | null)?.school_id
      if (!sid) throw new Error('No school scope.')
      let q = supabase.from('audit_events').select('id, action, outcome, target_type, created_at, reason')
        .eq('school_id', sid).order('created_at', { ascending: false }).limit(200)
      if (actionFilter) q = q.ilike('action', `%${actionFilter}%`)
      if (outcomeFilter) q = q.eq('outcome', outcomeFilter)
      const { data, error } = await q
      if (error) throw error
      setRows((data ?? []) as typeof rows)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load audit trail.')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { load() }, [])

  function exportCsv() {
    const header = 'time,action,outcome,target,reason'
    const lines = rows.map((r) =>
      [r.created_at, r.action, r.outcome, r.target_type ?? '', (r.reason ?? '').replace(/"/g, '""')].map((v) => `"${v}"`).join(',')
    )
    const blob = new Blob([[header, ...lines].join('\n')], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `audit-export-${new Date().toISOString().slice(0, 10)}.csv`
    a.click()
    URL.revokeObjectURL(url)
    // Audit the export itself (fire-and-forget, surfaced on failure).
    ;(async () => {
      try {
        const supabase = createClient()
        const { data: { user } } = await supabase.auth.getUser()
        const { data: membership } = await supabase.from('school_memberships').select('school_id')
          .eq('user_id', user!.id).eq('is_active', true).limit(1).maybeSingle()
        await logAudit(supabase, user!.id, {
          schoolId: (membership as { school_id: string }).school_id,
          action: 'data.export', targetType: 'audit_events', outcome: 'success',
          metadata: { rows: rows.length },
        })
        show(true, `Exported ${rows.length} rows (export recorded in audit trail).`)
      } catch {
        show(false, 'Export downloaded, but recording it in the audit trail failed.')
      }
    })()
  }

  if (loading) return <LoadingState />
  if (error) return <ErrorState message={error} onRetry={load} />

  return (
    <div>
      {node}
      <PageHeader
        title="Audit Trail"
        subtitle="Append-only. No role can modify or delete these records."
        action={<button onClick={exportCsv} className={btnSecondary}>Export CSV</button>}
      />
      <Card className="p-3 mb-4 flex gap-2">
        <input className={inputCls} style={{ maxWidth: 260 }} placeholder="Filter action, e.g. roster" value={actionFilter} onChange={(e) => setActionFilter(e.target.value)} />
        <select className={inputCls} style={{ maxWidth: 180 }} value={outcomeFilter} onChange={(e) => setOutcomeFilter(e.target.value)}>
          <option value="">All outcomes</option>
          <option value="success">success</option>
          <option value="failure">failure</option>
          <option value="rejected">rejected</option>
        </select>
        <button onClick={load} className={btnSecondary}>Apply</button>
      </Card>
      <Card>
        {rows.length === 0 ? <EmptyState title="No audit events match" /> : (
          <table className="w-full text-sm">
            <thead><tr className="text-left text-gray-500 text-xs border-b">
              <th className="p-3">Time</th><th>Action</th><th>Target</th><th>Outcome</th><th>Reason</th>
            </tr></thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.id} className="border-b border-gray-100 last:border-0">
                  <td className="p-3 text-xs text-gray-500 whitespace-nowrap">{new Date(r.created_at).toLocaleString()}</td>
                  <td className="font-mono text-xs">{r.action}</td>
                  <td className="text-xs">{r.target_type ?? '—'}</td>
                  <td><StatusBadge value={r.outcome} /></td>
                  <td className="text-xs text-gray-500">{r.reason ?? '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </Card>
    </div>
  )
}
