/* eslint-disable @typescript-eslint/no-explicit-any, @typescript-eslint/no-unused-vars */
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
  status: string
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
export default function DoubtsPage() {
  const [rows, setRows] = useState<DoubtRow[]>([])
  const [subjects, setSubjects] = useState<{ id: string; name: string }[]>([])
  const [mentors, setMentors] = useState<MentorOption[]>([])
  const [query, setQuery] = useState('')
  const [statusFilter, setStatusFilter] = useState('')
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
        supabase
          .from('doubt_requests')
          .select(`
            id, school_id, conversation_id, student_id, student_record_id,
            subject_id, question, chapter, question_number, explanation,
            previous_attempts, urgent, urgent_reason, urgent_pass_used,
            status, assigned_mentor_id, assigned_teacher_id, named_mentor,
            first_reply_at, resolved_at, closed_at, created_at, updated_at,
            students(student_id_no, first_name, last_name),
            subjects(name)
          `)
          .eq('school_id', sid)
          .order('created_at', { ascending: false }),
        supabase.from('subjects').select('id, name').eq('school_id', sid).order('name'),
        supabase.from('teachers').select('id, staff_id_no, first_name, last_name').eq('school_id', sid).eq('is_active', true).order('first_name'),
      ])
      if (!resDoubts || !resSubjects || !resMentors) throw new Error('Failed to load doubt data.')
      if (resDoubts.error) throw resDoubts.error
      setRows((resDoubts.data ?? []) as unknown as DoubtRow[])
      setSubjects((resSubjects.data ?? []) as { id: string; name: string }[])
      setMentors((resMentors.data ?? []).map((t: any) => ({
        id: t.id, name: t.first_name + ' ' + t.last_name,
        staff_id_no: t.staff_id_no,
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
      const student = r.students as { first_name?: string; last_name?: string; student_id_no?: string } | null
      const subject = r.subjects as { name?: string } | null
      const matchText = !q ||
        `${r.id} ${student?.first_name ?? ''} ${student?.last_name ?? ''} ${student?.student_id_no ?? ''} ${r.question} ${subject?.name ?? ''}`.toLowerCase().includes(q)
      const matchStatus = !statusFilter || r.status === statusFilter
      return matchText && matchStatus
    })
  }, [rows, query, statusFilter])

  async function assignDoubt(doubt: DoubtRow, mentorId: string) {
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('Not signed in.')

      // Find teacher record for mentor
      const { data: teacher } = await supabase
        .from('teachers')
        .select('id')
        .eq('user_id', mentorId)
        .single()
      if (!teacher) throw new Error('Teacher not found.')

      const { error } = await supabase
        .from('doubt_requests')
        .update({
          assigned_mentor_id: mentorId,
          assigned_teacher_id: teacher.id,
          status: 'assigned',
          updated_at: new Date().toISOString(),
        })
        .eq('id', doubt.id)

      if (error) throw error
      await logAudit(supabase, user.id, {
        schoolId, action: 'doubt.assign', targetType: 'doubt_request', targetId: doubt.id,
        outcome: 'success', metadata: { mentor_id: mentorId },
      })
      show(true, 'Doubt assigned to mentor.')
      setEditing(null)
      load()
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'Assign failed.')
    }
  }

  async function resolveDoubt(doubt: DoubtRow) {
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('Not signed in.')

      const { error } = await supabase.rpc('resolve_doubt', {
        p_request_id: doubt.id,
      })
      if (error) throw error
      await logAudit(supabase, user.id, {
        schoolId, action: 'doubt.resolve', targetType: 'doubt_request', targetId: doubt.id,
        outcome: 'success',
      })
      show(true, 'Doubt marked as resolved.')
      setEditing(null)
      load()
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'Resolve failed.')
    }
  }

  async function reopenDoubt(doubt: DoubtRow) {
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('Not signed in.')

      const { error } = await supabase.rpc('reopen_doubt', {
        p_request_id: doubt.id,
      })
      if (error) throw error
      await logAudit(supabase, user.id, {
        schoolId, action: 'doubt.reopen', targetType: 'doubt_request', targetId: doubt.id,
        outcome: 'success',
      })
      show(true, 'Doubt reopened.')
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
        subtitle="Student academic questions routed to mentors."
        action={<button onClick={load} className={btnSecondary}>Refresh</button>}
      />
      <Card className="p-3 mb-4 flex flex-wrap gap-2">
        <input className={inputCls} style={{ maxWidth: 260 }} placeholder="Search student, ID, subject, question…" value={query} onChange={(e) => setQuery(e.target.value)} />
        <select className={inputCls} style={{ maxWidth: 180 }} value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)}>
          <option value="">All statuses</option>
          <option value="pending_assignment">Pending Assignment</option>
          <option value="waiting">Waiting</option>
          <option value="assigned">Assigned</option>
          <option value="in_progress">In Progress</option>
          <option value="answered">Answered</option>
          <option value="resolved">Resolved</option>
          <option value="reopened">Reopened</option>
          <option value="closed">Closed</option>
        </select>
      </Card>
      <Card>
        {filtered.length === 0 ? <EmptyState title="No doubt requests match" /> : (
          <div className="overflow-x-auto mask-fade-r">
            <table className="data-table">
              <thead>
                <tr className="text-left text-ink-600 text-xs border-b sticky top-0 bg-white z-10">
                  <th className="p-3">Student</th>
                  <th className="p-3">Subject / Question</th>
                  <th className="p-3 text-right">Status</th>
                  <th className="p-3 text-right">Urgent</th>
                  <th className="p-3 text-right">Mentor</th>
                  <th className="p-3 text-right">Actions</th>
                </tr>
              </thead>
              <tbody>
                {filtered.map((r) => {
                  const student = r.students as any
                  const subject = r.subjects as any
                  return (
                    <tr key={r.id} className="border-b border-ink-200 last:border-0 group">
                      <td className="p-3 font-medium">{student?.first_name ?? '—'} {student?.last_name ?? ''} <span className="font-mono text-xs text-ink-400 block">({student?.student_id_no ?? '—'})</span></td>
                      <td className="p-3 text-sm max-w-xs truncate">{subject?.name ?? '—'} · {r.question}</td>
                      <td className="p-3 text-right"><StatusBadge value={r.status.replace(/_/g, ' ')} /></td>
                      <td className="p-3 text-right text-[10px]">
                        {r.urgent ? (
                          <span className="inline-flex items-center gap-1 text-[10px] font-bold text-rose-700"><AlertTriangle className="h-3 w-3" /> URGENT</span>
                        ) : (
                          <span className="text-[10px] text-ink-400">—</span>
                        )}
                      </td>
                      <td className="p-3 text-right text-sm">
                        {r.assigned_mentor_id ? (
                          <span className="text-[10px] font-bold text-brand-700">Assigned</span>
                        ) : (
                          <span className="text-[10px] text-ink-400">—</span>
                        )}
                      </td>
                      <td className="p-3 text-right whitespace-nowrap">
                        <button onClick={() => setEditing(r)} className="text-brand-600 text-xs hover:underline">Manage</button>
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
        <Modal title={`Doubt #${editing.id.slice(0, 8)}`} onClose={() => setEditing(null)}>
          <div className="space-y-4">
            <div className="space-y-2">
              <p className="text-xs font-medium text-ink-600">Question</p>
              <p className="text-sm">{editing.question}</p>
            </div>
            {editing.chapter && (
              <div className="space-y-2">
                <p className="text-xs font-medium text-ink-600">Chapter</p>
                <p className="text-sm">{editing.chapter}</p>
              </div>
            )}
            {editing.question_number && (
              <div className="space-y-2">
                <p className="text-xs font-medium text-ink-600">Question #</p>
                <p className="text-sm">{editing.question_number}</p>
              </div>
            )}
            <div className="space-y-2">
              <p className="text-xs font-medium text-ink-600">Status</p>
              <p className="text-sm">{editing.status.replace(/_/g, ' ')}</p>
            </div>
            <div className="space-y-2">
              <p className="text-xs font-medium text-ink-600">Urgent</p>
              <p className="text-sm">{editing.urgent ? 'Yes' : 'No'}</p>
            </div>
            <div className="space-y-2">
              <p className="text-xs font-medium text-ink-600 mt-3">Assign to Mentor</p>
              <select className={inputCls} value={editing.assigned_mentor_id ?? ''}
                onChange={(e) => setEditing({ ...editing, assigned_mentor_id: e.target.value || null })}>
                <option value="">Unassigned</option>
                {mentors.map((m) => (
                  <option key={m.id} value={m.id}>{m.name} ({m.staff_id_no})</option>
                ))}
              </select>
              <button onClick={() => editing.assigned_mentor_id ? assignDoubt(editing, editing.assigned_mentor_id) : null}
                className={btnPrimary + ' mt-2 w-full'}>Assign</button>
            </div>
            <div className="space-y-2 mt-4">
              {editing.status === 'pending_assignment' || editing.status === 'waiting' || editing.status === 'assigned' || editing.status === 'in_progress' || editing.status === 'answered' && (
                <div className="space-y-2">
                  <button onClick={() => resolveDoubt(editing)} className={btnPrimary}>Mark Resolved</button>
                  <button onClick={() => reopenDoubt(editing)} className={btnSecondary}>Reopen</button>
                </div>
              )}
              {editing.status === 'resolved' || editing.status === 'answered' || editing.status === 'closed' && (
                <button onClick={() => reopenDoubt(editing)} className={btnPrimary}>Reopen Conversation</button>
              )}
            </div>
            <div className="pt-2 border-t border-ink-100">
              <button onClick={() => setEditing(null)} className={btnSecondary}>Close</button>
            </div>
          </div>
        </Modal>
      )}
    </div>
  )
}