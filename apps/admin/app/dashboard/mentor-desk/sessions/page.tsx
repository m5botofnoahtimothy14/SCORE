'use client'

import { useEffect, useMemo, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { logAudit } from '@/lib/audit'
import {
  PageHeader, Card, StatusBadge, LoadingState, ErrorState,
  inputCls, btnPrimary, btnSecondary, useToast, EmptyState, Modal,
} from '@/components/ui'
import { AlertTriangle, CheckCircle } from 'lucide-react'
import { format } from 'date-fns'

interface BookingRow {
  id: string
  school_id: string
  student_id: string
  student_record_id: string
  mentor_id: string
  mentor_record_id: string
  subject_id: string
  duration_minutes: number
  topic: string
  preparation: string | null
  requested_at: string
  scheduled_at: string | null
  confirmed_at: string | null
  meeting_link: string | null
  meeting_room: string | null
  status: 'requested' | 'confirmed' | 'cancelled_by_student' | 'cancelled_by_mentor' | 'completed' | 'no_show_student' | 'no_show_mentor' | 'unverified_closed'
  allowance_minutes_used: number
  cancelled_at: string | null
  cancelled_by: string | null
  refunded: boolean
  verification_code: string | null
  code_expires_at: string | null
  code_attempts: number
  code_locked_at: string | null
  code_visible_at: string | null
  verified_at: string | null
  closed_without_code: boolean
  close_reason: string | null
  created_at: string
  updated_at: string
  students?: { student_id_no: string; first_name: string; last_name: string } | null
  teachers?: { staff_id_no: string; first_name: string; last_name: string } | null
  subjects?: { name: string } | null
  user_profiles?: { display_name: string } | null
}

// Session booking management. Verification codes are never exposed in the
// list — administrators investigate failures through the event history.
export default function SessionsPage() {
  const [rows, setRows] = useState<BookingRow[]>([])
  const [subjects, setSubjects] = useState<{ id: string; name: string }[]>([])
  const [mentors, setMentors] = useState<{ id: string; name: string }[]>([])
  const [query, setQuery] = useState('')
  const [statusFilter, setStatusFilter] = useState('')
  const [dateFrom, setDateFrom] = useState('')
  const [dateTo, setDateTo] = useState('')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [schoolId, setSchoolId] = useState<string | null>(null)
  const [userId, setUserId] = useState<string | null>(null)
  const [editing, setEditing] = useState<BookingRow | null>(null)
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

      const [resBookings, resSubjects, resMentors] = await Promise.all([
        supabase.from('session_bookings').select(`
          id, school_id, student_id, student_record_id, mentor_id, mentor_record_id,
          subject_id, duration_minutes, topic, preparation, requested_at,
          scheduled_at, confirmed_at, meeting_link, meeting_room, status,
          allowance_minutes_used, cancelled_at, cancelled_by, refunded,
          verification_code, code_expires_at, code_attempts, code_locked_at,
          code_visible_at, verified_at, closed_without_code, close_reason,
          created_at, updated_at,
          students(student_id_no, first_name, last_name),
          teachers(staff_id_no, first_name, last_name),
          subjects(name),
          user_profiles!session_bookings_mentor_id_fkey(display_name)
        `).eq('school_id', sid).order('created_at', { ascending: false }),
        supabase.from('subjects').select('id, name').eq('school_id', sid).order('name'),
        supabase.from('teachers').select('id, staff_id_no, first_name, last_name').eq('school_id', sid).eq('is_active', true).order('first_name'),
      ])
      if (!resBookings || !resSubjects || !resMentors) throw new Error('Failed to load session data.')
      if (resBookings.error) throw resBookings.error
      setRows((resBookings.data ?? []) as unknown as BookingRow[])
      setSubjects((resSubjects.data ?? []) as { id: string; name: string }[])
      setMentors(((resMentors.data ?? []) as { id: string; staff_id_no: string; first_name: string; last_name: string }[]).map((t) => ({
        id: t.id, name: t.first_name + ' ' + t.last_name,
      })))
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load session bookings.')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { load() }, [])

  const filtered = useMemo(() => {
    const q = query.toLowerCase()
    const from = dateFrom ? new Date(dateFrom).getTime() : 0
    const to = dateTo ? new Date(dateTo).getTime() + 86400000 : Infinity
    return rows.filter((r) => {
      const student = r.students as { first_name?: string; last_name?: string; student_id_no?: string } | null
      const mentor = r.teachers as { first_name?: string; last_name?: string; staff_id_no?: string } | null
      const subject = r.subjects as { name?: string } | null
      const matchText = !q ||
        `${r.id} ${student?.first_name ?? ''} ${student?.last_name ?? ''} ${student?.student_id_no ?? ''} ${mentor?.first_name ?? ''} ${mentor?.last_name ?? ''} ${subject?.name ?? ''} ${r.topic}`.toLowerCase().includes(q)
      const matchStatus = !statusFilter || r.status === statusFilter
      const scheduled = r.scheduled_at ? new Date(r.scheduled_at).getTime() : 0
      const matchDate = scheduled >= from && scheduled <= to
      return matchText && matchStatus && matchDate
    })
  }, [rows, query, statusFilter, dateFrom, dateTo])

  async function recordNoShow(booking: BookingRow, reportedBy: 'student' | 'mentor', reason: string) {
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('Not signed in.')
      const { error } = await supabase.rpc('record_no_show', {
        p_booking_id: booking.id,
        p_reported_by_role: reportedBy,
        p_reason: reason,
      })
      if (error) throw error
      await logAudit(supabase, user.id, {
        schoolId, action: 'session.no_show', targetType: 'session_booking', targetId: booking.id,
        outcome: 'success', reason, metadata: { reported_by: reportedBy },
      })
      show(true, `${reportedBy === 'mentor' ? 'Student' : 'Mentor'} no-show recorded.`)
      setEditing(null)
      load()
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'No-show record failed.')
    }
  }

  async function closeWithoutCode(booking: BookingRow, reason: string) {
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('Not signed in.')
      const { error } = await supabase.rpc('close_session_without_code', {
        p_booking_id: booking.id,
        p_reason: reason,
      })
      if (error) throw error
      await logAudit(supabase, user.id, {
        schoolId, action: 'session.close_without_code', targetType: 'session_booking', targetId: booking.id,
        outcome: 'success', reason,
      })
      show(true, 'Session closed without code — flagged for review.')
      setEditing(null)
      load()
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'Close failed.')
    }
  }

  async function cancel(booking: BookingRow, cancelledBy: string, reason: string) {
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('Not signed in.')
      const { error } = await supabase.rpc('cancel_session', { p_booking_id: booking.id, p_cancelled_by: user.id })
      if (error) throw error
      await logAudit(supabase, user.id, {
        schoolId, action: 'session.cancel', targetType: 'session_booking', targetId: booking.id,
        outcome: 'success', reason, metadata: { cancelled_by: cancelledBy },
      })
      show(true, 'Session cancelled. Allowance refunded.')
      setEditing(null)
      load()
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'Cancel failed.')
    }
  }

  if (error) return <ErrorState message={error} onRetry={load} />
  if (loading) return <LoadingState message="Loading session bookings…" />

  return (
    <div>
      {node}
      <PageHeader
        title="Session Bookings"
        subtitle="Verification codes are never shown here — investigate exceptions via the detail view."
        action={<button onClick={load} className={btnSecondary}>Refresh</button>}
      />
      <Card className="p-3 mb-4 flex flex-wrap gap-2">
        <input className={inputCls} style={{ maxWidth: 260 }} placeholder="Search student, mentor, topic…" value={query} onChange={(e) => setQuery(e.target.value)} />
        <select className={inputCls} style={{ maxWidth: 180 }} value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)}>
          <option value="">All statuses</option>
          <option value="requested">Requested</option>
          <option value="confirmed">Confirmed</option>
          <option value="completed">Completed</option>
          <option value="cancelled_by_student">Cancelled (student)</option>
          <option value="cancelled_by_mentor">Cancelled (mentor)</option>
          <option value="no_show_student">Student no-show</option>
          <option value="no_show_mentor">Mentor no-show</option>
          <option value="unverified_closed">Unverified closed</option>
        </select>
        <input className={inputCls} type="date" style={{ maxWidth: 150 }} value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} />
        <input className={inputCls} type="date" style={{ maxWidth: 150 }} value={dateTo} onChange={(e) => setDateTo(e.target.value)} />
      </Card>
      <Card>
        {filtered.length === 0 ? <EmptyState title="No session bookings match" /> : (
          <div className="overflow-x-auto mask-fade-r">
            <table className="data-table">
              <thead>
                <tr className="text-left text-ink-600 text-xs border-b sticky top-0 bg-white z-10">
                  <th className="p-3">Student</th>
                  <th className="p-3">Mentor</th>
                  <th className="p-3">Subject / Topic</th>
                  <th className="p-3 text-right">Scheduled</th>
                  <th className="p-3 text-right">Duration</th>
                  <th className="p-3 text-right">Status</th>
                  <th className="p-3 text-right">Verification</th>
                  <th className="p-3 text-right">Actions</th>
                </tr>
              </thead>
              <tbody>
                {filtered.map((r) => {
                  const student = r.students as any
                  const mentor = r.teachers as any
                  const subject = r.subjects as any
                  const isUnverified = r.closed_without_code || r.status === 'unverified_closed'
                  const codeLocked = r.code_locked_at !== null
                  return (
                    <tr key={r.id} className="border-b border-ink-200 last:border-0 group">
                      <td className="p-3 font-medium">{student?.first_name ?? '—'} {student?.last_name ?? ''} <span className="font-mono text-xs text-ink-400 block">({student?.student_id_no ?? '—'})</span></td>
                      <td className="p-3 text-sm">{mentor?.first_name ?? '—'} {mentor?.last_name ?? ''} <span className="font-mono text-xs text-ink-400 block">({mentor?.staff_id_no ?? '—'})</span></td>
                      <td className="p-3 text-sm max-w-xs truncate">{subject?.name ?? '—'} · {r.topic}</td>
                      <td className="p-3 text-right text-sm">{r.scheduled_at ? format(new Date(r.scheduled_at), 'MMM d, h:mm a') : '—'}</td>
                      <td className="p-3 text-right text-sm">{r.duration_minutes} min</td>
                      <td className="p-3 text-right"><StatusBadge value={r.status.replace(/_/g, ' ')} /></td>
                      <td className="p-3 text-right text-sm">
                        {isUnverified ? (
                          <span className="inline-flex items-center gap-1 text-[10px] font-bold text-rose-700"><AlertTriangle className="h-3 w-3" /> UNVERIFIED</span>
                        ) : r.status === 'completed' ? (
                          <span className="inline-flex items-center gap-1 text-[10px] font-bold text-emerald-700"><CheckCircle className="h-3 w-3" /> VERIFIED</span>
                        ) : r.code_visible_at ? (
                          codeLocked ? (
                            <span className="inline-flex items-center gap-1 text-[10px] font-bold text-amber-700"><AlertTriangle className="h-3 w-3" /> LOCKED</span>
                          ) : (
                            <span className="inline-flex items-center gap-1 text-[10px] font-bold text-brand-700">CODE</span>
                          )
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
        <Modal title={`Session #${editing.id.slice(0, 8)}`} onClose={() => setEditing(null)} wide>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            <div className="col-span-1 space-y-3">
              <p className="text-xs font-medium text-ink-600">Topic</p>
              <p className="text-sm">{editing.topic}</p>
              {editing.preparation && (
                <div className="mt-2">
                  <p className="text-xs font-medium text-ink-600">Preparation</p>
                  <p className="text-sm text-ink-700">{editing.preparation}</p>
                </div>
              )}
              <p className="text-xs font-medium text-ink-600 mt-3">Status</p>
              <p className="text-sm">{editing.status.replace(/_/g, ' ')}</p>
              <p className="text-xs font-medium text-ink-600 mt-3">Duration</p>
              <p className="text-sm">{editing.duration_minutes} minutes</p>
              <p className="text-xs font-medium text-ink-600 mt-3">Allowance used</p>
              <p className="text-sm">{editing.allowance_minutes_used} minutes</p>
              {editing.refunded && <p className="text-xs text-rose-600">Allowance refunded.</p>}
              {editing.meeting_link && (
                <div className="mt-2">
                  <p className="text-xs font-medium text-ink-600">Meeting link</p>
                  <a href={editing.meeting_link} target="_blank" rel="noopener noreferrer" className="text-sm text-brand-600 hover:underline break-all">{editing.meeting_link}</a>
                </div>
              )}
              {editing.meeting_room && (
                <div className="mt-2">
                  <p className="text-xs font-medium text-ink-600">Room</p>
                  <p className="text-sm">{editing.meeting_room}</p>
                </div>
              )}
            </div>
            <div className="col-span-1 space-y-3">
              <p className="text-xs font-medium text-ink-600">Timing</p>
              <p className="text-sm">Requested: {format(new Date(editing.requested_at), 'MMM d, h:mm a')}</p>
              {editing.scheduled_at && <p className="text-sm">Scheduled: {format(new Date(editing.scheduled_at), 'MMM d, h:mm a')}</p>}
              {editing.confirmed_at && <p className="text-sm">Confirmed: {format(new Date(editing.confirmed_at), 'MMM d, h:mm a')}</p>}
              {editing.cancelled_at && <p className="text-sm text-rose-600">Cancelled: {format(new Date(editing.cancelled_at), 'MMM d, h:mm a')}</p>}
              <p className="text-xs font-medium text-ink-600 mt-3">Verification</p>
              {editing.code_visible_at ? (
                <div>
                  <p className="text-sm">Code visible: {format(new Date(editing.code_visible_at), 'MMM d, h:mm a')}</p>
                  <p className="text-sm">Attempts: {editing.code_attempts}</p>
                  {editing.code_locked_at && <p className="text-sm text-rose-600">Code entry locked.</p>}
                  {editing.verified_at && <p className="text-sm text-emerald-700">Verified at: {format(new Date(editing.verified_at), 'MMM d, h:mm a')}</p>}
                  {editing.closed_without_code && <p className="text-sm text-rose-700">Closed without code — flagged.</p>}
                </div>
              ) : <p className="text-sm text-ink-400">Code not yet visible.</p>}
            </div>
            <div className="col-span-1 space-y-3">
              <p className="text-xs font-medium text-ink-600">Administrative actions</p>
              {editing.status === 'confirmed' && (
                <div className="space-y-2">
                  <button onClick={() => recordNoShow(editing, 'mentor', 'Admin recorded mentor no-show')} className={btnSecondary}><AlertTriangle className="h-3.5 w-3.5 mr-1.5" /> Mentor no-show</button>
                  <button onClick={() => cancel(editing, 'admin', 'Admin cancelled session')} className={btnSecondary}>Cancel session</button>
                </div>
              )}
              {editing.status === 'completed' && !editing.closed_without_code && (
                <button onClick={() => closeWithoutCode(editing, 'Admin exception closure without verification code')} className={btnSecondary}><AlertTriangle className="h-3.5 w-3.5 mr-1.5" /> Close without code</button>
              )}
              {editing.status === 'requested' && (
                <button onClick={() => cancel(editing, 'admin', 'Admin cancelled requested session')} className={btnSecondary}>Cancel request</button>
              )}
              {editing.status === 'no_show_mentor' && (
                <button onClick={() => recordNoShow(editing, 'mentor', 'Admin confirmed mentor no-show')} className={btnPrimary}>Confirm mentor no-show (refund)</button>
              )}
              {editing.status === 'unverified_closed' && (
                <p className="text-xs text-rose-600">Pending administrative review.</p>
              )}
              <div className="pt-2 border-t border-ink-100">
                <button onClick={() => setEditing(null)} className={btnSecondary}>Close</button>
              </div>
            </div>
          </div>
        </Modal>
      )}
    </div>
  )
}
