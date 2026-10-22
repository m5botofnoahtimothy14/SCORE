'use client'

import { useEffect, useMemo, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { logAudit } from '@/lib/audit'
import {
  PageHeader, Card, StatusBadge, LoadingState, ErrorState,
  inputCls, btnPrimary, btnSecondary, useToast, EmptyState, Modal,
} from '@/components/ui'
import { AlertTriangle, CheckCircle, Clock } from 'lucide-react'

interface DoubtRow {
  id: string
  school_id: string
  conversation_id: string
  student_id: string
  student_record_id: string
  subject_id: string
  question: string
  chapter: string | null
  question_number: string | null
  explanation: string | null
  previous_attempts: string | null
  urgent: boolean
  urgent_reason: string | null
  urgent_pass_used: boolean
  status: 'waiting' | 'assigned' | 'resolved' | 'closed'
  assigned_mentor_id: string | null
  assigned_teacher_id: string | null
  named_mentor: boolean
  first_reply_at: string | null
  resolved_at: string | null
  closed_at: string | null
  created_at: string
  updated_at: string
  students?: { student_id_no: string; first_name: string; last_name: string } | null
  subjects?: { name: string } | null
}

interface MentorOption { id: string; name: string; staff_id_no: string }

// Doubt request management — searchable, filterable, audited.
// Queue order enforced by the backend RPCs (urgent -> escalated -> oldest).
export default function DoubtsPage() {
  const [rows, setRows] = useState<DoubtRow[]>([])
  const [subjects, setSubjects] = useState<{ id: string; name: string }[]>([])
  const [mentors, setMentors] = useState<MentorOption[]>([])
  const [query, setQuery] = useState('')
  const [statusFilter, setStatusFilter] = useState('')
  const [urgentFilter, setUrgentFilter] = useState('')
  const [subjectFilter, setSubjectFilter] = useState('')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [schoolId, setSchoolId] = useState<string | null>(null)
  const [userId, setUserId] = useState<string | null>(null)
  const [editing, setEditing] = useState<DoubtRow | null>(null)
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

      const [resDoubts, resSubjects, resMentors] = await Promise.all([
        supabase.from('doubt_requests').select(`
          id, school_id, conversation_id, student_id, student_record_id,
          subject_id, question, chapter, question_number, explanation,
          previous_attempts, urgent, urgent_reason, urgent_pass_used, status,
          assigned_mentor_id, assigned_teacher_id, named_mentor,
          first_reply_at, resolved_at, closed_at, created_at, updated_at,
          students(student_id_no, first_name, last_name),
          subjects(name)
        `).eq('school_id', sid).order('created_at', { ascending: false }),
        supabase.from('subjects').select('id, name').eq('school_id', sid).order('name'),
        supabase.from('teachers').select('id, staff_id_no, first_name, last_name').eq('school_id', sid).eq('is_active', true).order('first_name'),
      ])
      if (!resDoubts || !resSubjects || !resMentors) throw new Error('Failed to load doubt data.')
      if (resDoubts.error) throw resDoubts.error
      setRows((resDoubts.data ?? []) as unknown as DoubtRow[])
      setSubjects((resSubjects.data ?? []) as { id: string; name: string }[])
      setMentors(((resMentors.data ?? []) as { id: string; staff_id_no: string; first_name: string; last_name: string }[]).map((t) => ({
        id: t.id, name: t.first_name + ' ' + t.last_name, staff_id_no: t.staff_id_no,
      })))
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load doubt requests.')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { load() }, [])

  const filtered = useMemo(() => {
    const q = query.toLowerCase()
    return rows.filter((r) => {
      const student = r.students as any
      const subject = r.subjects as any
      const matchText = !q ||
        (r.id + ' ' + (student?.first_name ?? '') + ' ' + (student?.last_name ?? '') +
          ' ' + (student?.student_id_no ?? '') + ' ' + (subject?.name ?? '') + ' ' + r.question).toLowerCase().includes(q)
      const matchStatus = !statusFilter || r.status === statusFilter
      const matchUrgent = !urgentFilter || (urgentFilter === 'yes' ? r.urgent : !r.urgent)
      const matchSubject = !subjectFilter || r.subject_id === subjectFilter
      return matchText && matchStatus && matchUrgent && matchSubject
    })
  }, [rows, query, statusFilter, urgentFilter, subjectFilter])

  const waitingMinutes = (createdAt: string) => {
    const diff = Date.now() - new Date(createdAt).getTime()
    return Math.floor(diff / 60000)
  }

  async function reassignAction(doubt: DoubtRow, reason: string) {
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('Not signed in.')
      const newMentorId = doubt.assigned_mentor_id
      if (!newMentorId) {
        show(false, 'Select a mentor first.')
        return
      }
      const { error } = await supabase.rpc('claim_doubt', { p_request_id: doubt.id })
      if (error) throw error
      await logAudit(supabase, user.id, {
        schoolId, action: 'doubt.reassign', targetType: 'doubt_request', targetId: doubt.id,
        outcome: 'success', reason, metadata: { new_mentor_id: newMentorId },
      })
      show(true, 'Request reassigned.')
      setEditing(null)
      load()
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'Reassign failed.')
    }
  }

  async function escalateAction(doubt: DoubtRow) {
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('Not signed in.')
      await logAudit(supabase, user.id, {
        schoolId, action: 'doubt.escalate', targetType: 'doubt_request', targetId: doubt.id,
        outcome: 'success', reason: 'Queue escalation threshold exceeded',
      })
      show(true, 'Escalated.')
      load()
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'Escalate failed.')
    }
  }

  async function resolveAction(doubt: DoubtRow) {
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('Not signed in.')
      const { error } = await supabase.rpc('resolve_doubt', { p_request_id: doubt.id })
      if (error) throw error
      await logAudit(supabase, user.id, {
        schoolId, action: 'doubt.resolve', targetType: 'doubt_request', targetId: doubt.id,
        outcome: 'success',
      })
      show(true, 'Resolved.')
      setEditing(null)
      load()
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'Resolve failed.')
    }
  }

  async function reopenAction(doubt: DoubtRow) {
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('Not signed in.')
      const { error } = await supabase.rpc('reopen_doubt', { p_request_id: doubt.id })
      if (error) throw error
      await logAudit(supabase, user.id, {
        schoolId, action: 'doubt.reopen', targetType: 'doubt_request', targetId: doubt.id,
        outcome: 'success',
      })
      show(true, 'Reopened.')
      setEditing(null)
      load()
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'Reopen failed.')
    }
  }

  if (error) return <ErrorState message={error} onRetry={load} />
  if (loading) return <LoadingState message="Loading doubt requests…" />

  return (
    <div>
      {node}
      <PageHeader
        title="Doubt Requests"
        subtitle={filtered.length + ' of ' + rows.length + ' requests · Queue: urgent first, then escalated (>30 min), then oldest'}
        action={<div className="flex gap-2">
          <button onClick={load} className={btnSecondary}>Refresh</button>
        </div>}
      />
      <Card className="p-3 mb-4 flex flex-wrap gap-2">
        <input className={inputCls} style={{ maxWidth: 260 }} placeholder="Search student, ID, subject, question…" value={query} onChange={(e) => setQuery(e.target.value)} />
        <select className={inputCls} style={{ maxWidth: 160 }} value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)}>
          <option value="">All statuses</option>
          <option value="waiting">Waiting</option>
          <option value="assigned">Assigned</option>
          <option value="resolved">Resolved</option>
          <option value="closed">Closed</option>
        </select>
        <select className={inputCls} style={{ maxWidth: 140 }} value={urgentFilter} onChange={(e) => setUrgentFilter(e.target.value)}>
          <option value="">Urgency</option>
          <option value="yes">Urgent</option>
          <option value="no">Standard</option>
        </select>
        <select className={inputCls} style={{ maxWidth: 180 }} value={subjectFilter} onChange={(e) => setSubjectFilter(e.target.value)}>
          <option value="">All subjects</option>
          {subjects.map(function (s) { return <option key={s.id} value={s.id}>{s.name}</option> })}
        </select>
      </Card>
      <Card>
        {filtered.length === 0 ? <EmptyState title="No doubt requests match" /> : (
          <div className="overflow-x-auto mask-fade-r">
            <table className="data-table">
              <thead>
                <tr className="text-left text-ink-600 text-xs border-b sticky top-0 bg-white z-10">
                  <th className="p-3">Student</th>
                  <th className="p-3">Subject</th>
                  <th className="p-3">Question</th>
                  <th className="p-3 text-right">Wait</th>
                  <th className="p-3 text-right">Status</th>
                  <th className="p-3 text-right">Mentor</th>
                  <th className="p-3 text-right">Urgent</th>
                  <th className="p-3 text-right">Actions</th>
                </tr>
              </thead>
              <tbody>
                {filtered.map(function (r) {
                  const student = r.students as any
                  const subject = r.subjects as any
                  const mentor = mentors.find(function (m) { return m.id === r.assigned_mentor_id })
                  const mins = waitingMinutes(r.created_at)
                  const escalated = mins > 30
                  return (
                    <tr key={r.id} className="border-b border-ink-200 last:border-0 group">
                      <td className="p-3 font-medium">{student?.first_name ?? '—'} {student?.last_name ?? ''}
                        <span className="font-mono text-xs text-ink-400 block">({student?.student_id_no ?? '—'})</span></td>
                      <td className="p-3 text-sm">{subject?.name ?? '—'}</td>
                      <td className="p-3 text-sm max-w-xs truncate">{r.question}</td>
                      <td className="p-3 text-right text-sm font-medium {escalated ? 'text-rose-700' : 'text-ink-700'}">{mins}m</td>
                      <td className="p-3 text-right"><StatusBadge value={r.status} /></td>
                      <td className="p-3 text-right text-sm">{mentor ? mentor.name : 'Unassigned'}</td>
                      <td className="p-3 text-right">{r.urgent ? (
                        <span className="inline-flex items-center gap-1 text-[10px] font-bold text-rose-700"><AlertTriangle className="h-3 w-3" /> YES</span>
                      ) : '—'}</td>
                      <td className="p-3 text-right whitespace-nowrap">
                        <button onClick={function () { setEditing(r) }} className="text-brand-600 text-xs hover:underline">Manage</button>
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      {editing && (
        <Modal title={'Doubt #' + editing.id.slice(0, 8)} onClose={function () { setEditing(null) }} wide>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div className="space-y-3">
              <p className="text-sm font-medium">Question</p>
              <p className="text-sm text-ink-700 bg-ink-50 rounded-lg p-3 border border-ink-100">{editing.question}</p>
              {editing.chapter && (
                <div>
                  <p className="text-xs text-ink-500 mb-1">Chapter</p>
                  <p className="text-sm">{editing.chapter}</p>
                </div>
              )}
              {editing.question_number && (
                <div>
                  <p className="text-xs text-ink-500 mb-1">Question #</p>
                  <p className="text-sm">{editing.question_number}</p>
                </div>
              )}
              {editing.urgent && (
                <div className="pt-2">
                  <p className="text-xs text-ink-500 mb-1">Urgent reason</p>
                  <p className="text-sm text-rose-700">{editing.urgent_reason}</p>
                </div>
              )}
              <p className="text-xs text-ink-500 mt-3">Status: <span className="font-medium">{editing.status.replace(/_/g, ' ')}</span></p>
              <p className="text-xs text-ink-500">Wait: {waitingMinutes(editing.created_at)} minutes</p>
              <p className="text-xs text-ink-500">Named mentor: {editing.named_mentor ? 'Yes' : 'No'}</p>
            </div>
            <div className="space-y-3">
              {editing.status === 'waiting' && (
                <div>
                  <p className="text-xs font-medium text-ink-600 mb-2">Assign to mentor</p>
                  <select className={inputCls} value={editing.assigned_mentor_id ?? ''}
                    onChange={(e) => setEditing({ ...editing, assigned_mentor_id: e.target.value || null })}>
                    <option value="">Unassigned (shared queue)</option>
                    {mentors.map(function (m) { return <option key={m.id} value={m.id}>{m.name} ({m.staff_id_no})</option> })}
                  </select>
                  <button onClick={function () { reassignAction(editing, 'Admin reassignment from Doubt Requests page') }}
                    className={btnPrimary + ' mt-2'}>Assign</button>
                </div>
              )}
              {editing.status === 'assigned' && (
                <div className="space-y-2">
                  <button onClick={function () { resolveAction(editing) }} className={btnPrimary}>Mark resolved</button>
                  <button onClick={function () { reopenAction(editing) }} className={btnSecondary}>Reopen</button>
                  <button onClick={function () { escalateAction(editing) }} className={btnSecondary}>Escalate</button>
                </div>
              )}
              {(editing.status === 'resolved' || editing.status === 'closed') && (
                <div className="space-y-2">
                  <button onClick={function () { reopenAction(editing) }} className={btnPrimary}>Reopen conversation</button>
                </div>
              )}
              <div className="pt-2">
                <p className="text-[10px] text-ink-400">Conversation is handled in the SCORE app.</p>
              </div>
            </div>
          </div>
        </Modal>
      )}
    </div>
  )
}
