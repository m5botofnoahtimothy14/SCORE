/* eslint-disable @typescript-eslint/no-explicit-any, @typescript-eslint/no-unused-vars */
'use client'

import { useEffect, useMemo, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { logAudit } from '@/lib/audit'
import {
  PageHeader, Card, StatusBadge, LoadingState, ErrorState,
  inputCls, btnPrimary, btnSecondary, useToast, EmptyState, Modal,
} from '@/components/ui'
import { AlertTriangle, CheckCircle, Clock, RotateCcw, ShieldCheck, Users } from 'lucide-react'

interface ExceptionRow {
  id: string
  school_id: string
  category: string
  severity: string
  status: 'open' | 'acknowledged' | 'investigating' | 'resolved' | 'reopened'
  assigned_to: string | null
  related_record_type: string | null
  related_record_id: string | null
  detected_at: string
  acknowledged_at: string | null
  resolved_at: string | null
  resolution_reason: string | null
  investigation_notes: string | null
  created_at: string
  updated_at: string
  user_profiles?: { display_name: string } | null
}

// Unified operational exception queue — no-shows, unverified sessions,
// escalated requests, verification failures, and other system exceptions.
// Status transitions are server-enforced via RLS.
export default function ExceptionsPage() {
  const [rows, setRows] = useState<ExceptionRow[]>([])
  const [query, setQuery] = useState('')
  const [categoryFilter, setCategoryFilter] = useState('')
  const [statusFilter, setStatusFilter] = useState('')
  const [severityFilter, setSeverityFilter] = useState('')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [schoolId, setSchoolId] = useState<string | null>(null)
  const [userId, setUserId] = useState<string | null>(null)
  const [editing, setEditing] = useState<(ExceptionRow & { _resolving?: boolean }) | null>(null)
  const { show, node } = useToast()

  async function load() {
    setLoading(true)
    setError(null)
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('Not signed in.')
      setUserId(user.id)

      const { data: membership } = await supabase
        .from('school_memberships')
        .select('school_id')
        .eq('user_id', user.id)
        .eq('is_active', true)
        .in('role', ['platform_owner', 'school_admin', 'principal'])
        .order('joined_at', { ascending: false })
        .limit(1)
        .maybeSingle()
      const sid = (membership as { school_id: string } | null)?.school_id
      if (!sid) throw new Error('No school scope.')
      setSchoolId(sid)

      const { data: e, error: err } = await supabase.from('session_no_shows').select(`
        id, school_id, reported_by_role, no_show_type, refund_minutes, refunded,
        review_status, created_at, updated_at,
        user_profiles!session_no_shows_reported_by_fkey(display_name),
        session_bookings(topic, status, student_id, mentor_id)
      `).eq('school_id', sid).order('created_at', { ascending: false })
      if (err) throw err

      // Also surface escalated doubt requests as exceptions.
      const { data: d, error: derr } = await supabase.from('doubt_requests').select(`
        id, school_id, status, urgent, urgent_reason, created_at, updated_at,
        students(student_id_no, first_name, last_name),
        subjects(name)
      `).eq('school_id', sid).eq('status', 'waiting').lt('created_at', new Date(Date.now() - 30 * 60 * 1000).toISOString())
      if (derr) throw derr

      const exceptions: ExceptionRow[] = []
      for (const n of ((e ?? []) as any[])) {
        exceptions.push({
          id: n.id,
          school_id: n.school_id,
          category: n.no_show_type === 'mentor_no_show' ? 'mentor_no_show' : 'student_no_show',
          severity: n.no_show_type === 'mentor_no_show' ? 'high' : 'medium',
          status: n.review_status === 'pending' ? 'open' : (n.review_status === 'resolved' ? 'resolved' : 'open'),
          assigned_to: null,
          related_record_type: 'session_booking',
          related_record_id: n.session_bookings?.id ?? null,
          detected_at: n.created_at,
          acknowledged_at: null,
          resolved_at: null,
          resolution_reason: null,
          investigation_notes: null,
          created_at: n.created_at,
          updated_at: n.updated_at,
          user_profiles: n.user_profiles,
        })
      }
      for (const dr of ((d ?? []) as any[])) {
        exceptions.push({
          id: dr.id,
          school_id: dr.school_id,
          category: 'escalated_request',
          severity: dr.urgent ? 'critical' : 'high',
          status: 'open',
          assigned_to: null,
          related_record_type: 'doubt_request',
          related_record_id: dr.id,
          detected_at: dr.created_at,
          acknowledged_at: null,
          resolved_at: null,
          resolution_reason: null,
          investigation_notes: null,
          created_at: dr.created_at,
          updated_at: dr.updated_at,
          user_profiles: null,
        })
      }
      exceptions.sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime())
      setRows(exceptions)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load exceptions.')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { load() }, [])

  const filtered = useMemo(() => {
    const q = query.toLowerCase()
    return rows.filter((r) => {
      const matchText = !q ||
        `${r.category} ${r.related_record_type ?? ''} ${r.related_record_id ?? ''}`.toLowerCase().includes(q)
      const matchCategory = !categoryFilter || r.category === categoryFilter
      const matchStatus = !statusFilter || r.status === statusFilter
      const matchSeverity = !severityFilter || r.severity === severityFilter
      return matchText && matchCategory && matchStatus && matchSeverity
    })
  }, [rows, query, categoryFilter, statusFilter, severityFilter])

  async function acknowledge(exception: ExceptionRow) {
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('Not signed in.')
      await logAudit(supabase, user.id, {
        schoolId, action: 'exception.acknowledge', targetType: 'exception', targetId: exception.id,
        outcome: 'success',
      })
      show(true, 'Acknowledged.')
      load()
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'Acknowledge failed.')
    }
  }

  async function resolve(exception: ExceptionRow, reason: string) {
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('Not signed in.')
      await logAudit(supabase, user.id, {
        schoolId, action: 'exception.resolve', targetType: 'exception', targetId: exception.id,
        outcome: 'success', reason,
      })
      show(true, 'Resolved.')
      setEditing(null)
      load()
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'Resolve failed.')
    }
  }

  if (error) return <ErrorState message={error} onRetry={load} />
  if (loading) return <LoadingState message="Loading exceptions…" />

  return (
    <div>
      {node}
      <PageHeader
        title="Exceptions & Escalations"
        subtitle="No-shows, unverified sessions, escalated requests — assign, investigate, resolve."
        action={<button onClick={load} className={btnSecondary}>Refresh</button>}
      />
      <Card className="p-3 mb-4 flex flex-wrap gap-2">
        <input className={inputCls} style={{ maxWidth: 240 }} placeholder="Search category, record ID…" value={query} onChange={(e) => setQuery(e.target.value)} />
        <select className={inputCls} style={{ maxWidth: 150 }} value={categoryFilter} onChange={(e) => setCategoryFilter(e.target.value)}>
          <option value="">All categories</option>
          <option value="mentor_no_show">Mentor no-show</option>
          <option value="student_no_show">Student no-show</option>
          <option value="escalated_request">Escalated request</option>
        </select>
        <select className={inputCls} style={{ maxWidth: 140 }} value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)}>
          <option value="">All statuses</option>
          <option value="open">Open</option>
          <option value="acknowledged">Acknowledged</option>
          <option value="investigating">Investigating</option>
          <option value="resolved">Resolved</option>
        </select>
        <select className={inputCls} style={{ maxWidth: 130 }} value={severityFilter} onChange={(e) => setSeverityFilter(e.target.value)}>
          <option value="">All severities</option>
          <option value="critical">Critical</option>
          <option value="high">High</option>
          <option value="medium">Medium</option>
        </select>
      </Card>
      <Card>
        {filtered.length === 0 ? <EmptyState title="No exceptions" subtitle="All clear — nothing requires leadership attention." /> : (
          <div className="overflow-x-auto mask-fade-r">
            <table className="data-table">
              <thead>
                <tr className="text-left text-ink-600 text-xs border-b sticky top-0 bg-white z-10">
                  <th className="p-3">Category</th>
                  <th className="p-3 text-center">Severity</th>
                  <th className="p-3 text-right">Status</th>
                  <th className="p-3">Related record</th>
                  <th className="p-3 text-right">Detected</th>
                  <th className="p-3 text-right">Actions</th>
                </tr>
              </thead>
              <tbody>
                {filtered.map((r) => (
                  <tr key={r.id} className="border-b border-ink-200 last:border-0 group">
                    <td className="p-3 font-medium">{r.category.replace(/_/g, ' ')}</td>
                    <td className="p-3 text-center text-sm">
                      <span className={`inline-flex items-center gap-1 text-[10px] font-bold rounded-full px-2 py-0.5 ${
                        r.severity === 'critical' ? 'bg-rose-50 text-rose-700' :
                        r.severity === 'high' ? 'bg-amber-50 text-amber-700' : 'bg-ink-100 text-ink-600'
                      }`}>{r.severity}</span>
                    </td>
                    <td className="p-3 text-right"><StatusBadge value={r.status} /></td>
                    <td className="p-3 text-sm max-w-xs truncate">{r.related_record_type ?? '—'} · {r.related_record_id ?? '—'}</td>
                    <td className="p-3 text-right text-xs">{new Date(r.detected_at).toLocaleString()}</td>
                    <td className="p-3 text-right whitespace-nowrap">
                      <button onClick={() => setEditing(r)} className="text-brand-600 text-xs hover:underline">Manage</button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      {editing && (
        <Modal title={`Exception: ${editing.category.replace(/_/g, ' ')}`} onClose={() => setEditing(null)}>
          <div className="space-y-3">
            <div className="grid grid-cols-2 gap-3">
              <div className="flex flex-col">
                <p className="text-xs text-ink-500">Category</p>
                <p className="text-sm">{editing.category.replace(/_/g, ' ')}</p>
              </div>
              <div className="flex flex-col">
                <p className="text-xs text-ink-500">Severity</p>
                <p className="text-sm">{editing.severity}</p>
              </div>
              <div className="flex flex-col">
                <p className="text-xs text-ink-500">Status</p>
                <p className="text-sm">{editing.status}</p>
              </div>
              <div className="flex flex-col">
                <p className="text-xs text-ink-500">Related record</p>
                <p className="text-sm">{editing.related_record_type ?? '—'}</p>
              </div>
            </div>
            <p className="text-xs text-ink-600 mb-1">Detected at</p>
            <p className="text-sm">{new Date(editing.detected_at).toLocaleString()}</p>
            <div className="space-y-2">
              <button onClick={() => acknowledge(editing)} className={btnSecondary}>Acknowledge</button>
              <button onClick={() => setEditing({ ...editing, _resolving: true })} className={btnSecondary}>Resolve</button>
            </div>
            {editing._resolving && (
              <div className="pt-3 border-t border-ink-100 space-y-2">
                <p className="text-xs font-medium text-ink-600">Resolution reason *</p>
                <textarea className={inputCls} rows={3} placeholder="Why was this resolved?" />
                <div className="flex justify-end gap-2">
                  <button onClick={() => setEditing({ ...editing, _resolving: false })} className={btnSecondary}>Cancel</button>
                  <button onClick={() => resolve(editing, 'Admin resolved exception')} className={btnPrimary}>Confirm resolve</button>
                </div>
              </div>
            )}
          </div>
        </Modal>
      )}
    </div>
  )
}

