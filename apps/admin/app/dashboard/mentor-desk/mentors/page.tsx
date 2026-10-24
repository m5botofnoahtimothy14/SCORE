/* eslint-disable @typescript-eslint/no-explicit-any, @typescript-eslint/no-unused-vars */
'use client'

import { useEffect, useMemo, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { logAudit } from '@/lib/audit'
import {
  PageHeader, Card, StatusBadge, LoadingState, ErrorState,
  inputCls, btnPrimary, btnSecondary, useToast, EmptyState, Modal,
} from '@/components/ui'
import { AlertTriangle, CheckCircle, Clock, ShieldCheck, Users } from 'lucide-react'

interface MentorRow {
  id: string
  school_id: string
  staff_id_no: string
  first_name: string
  last_name: string
  phone: string
  email: string | null
  is_active: boolean
  is_leadership: boolean
  user_id: string | null
  created_at: string
  updated_at: string
  mentor_availability?: { status: string; updated_at: string } | null
  mentor_subject_approvals?: { subject_id: string; status: string; subjects?: { name: string } }[] | null
}

// Mentor directory — approvals, availability, suspension.
// Unapproved mentors cannot accept student requests (enforced by RLS/RPCs).
export default function MentorsPage() {
  const [rows, setRows] = useState<MentorRow[]>([])
  const [subjects, setSubjects] = useState<{ id: string; name: string }[]>([])
  const [query, setQuery] = useState('')
  const [approvalFilter, setApprovalFilter] = useState('')
  const [activeFilter, setActiveFilter] = useState('')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [schoolId, setSchoolId] = useState<string | null>(null)
  const [userId, setUserId] = useState<string | null>(null)
  const [editing, setEditing] = useState<MentorRow | null>(null)
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

      const [resTeachers, resSubjects] = await Promise.all([
        supabase.from('teachers').select(`
          id, school_id, staff_id_no, first_name, last_name, phone, email,
          is_active, is_leadership, created_at, updated_at,
          mentor_availability(status, updated_at),
          mentor_subject_approvals(subject_id, status, subjects(name))
        `).eq('school_id', sid).order('first_name'),
        supabase.from('subjects').select('id, name').eq('school_id', sid).order('name'),
      ])
      if (!resTeachers || !resSubjects) throw new Error('Failed to load mentor data.')
      if (resTeachers.error) throw resTeachers.error
      setRows((resTeachers.data ?? []) as unknown as MentorRow[])
      setSubjects((resSubjects.data ?? []) as { id: string; name: string }[])
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load mentors.')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { load() }, [])

  const filtered = useMemo(() => {
    const q = query.toLowerCase()
    return rows.filter((r) => {
      const matchText = !q ||
        `${r.first_name} ${r.last_name} ${r.staff_id_no} ${r.email ?? ''}`.toLowerCase().includes(q)
      const matchApproval = !approvalFilter ||
        (approvalFilter === 'pending' ? !r.mentor_subject_approvals?.some((a) => a.status === 'approved') :
         approvalFilter === 'approved' ? r.mentor_subject_approvals?.some((a) => a.status === 'approved') :
         approvalFilter === 'none' ? r.mentor_subject_approvals?.length === 0 : true)
      const matchActive = !activeFilter || (activeFilter === 'active' ? r.is_active : !r.is_active)
      return matchText && matchApproval && matchActive
    })
  }, [rows, query, approvalFilter, activeFilter])

  async function approveSubject(mentorId: string, subjectId: string, approved: boolean) {
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('Not signed in.')
      const { error } = await supabase.rpc('approve_mentor_subject', {
        p_teacher_id: mentorId,
        p_subject_id: subjectId,
        p_approved: approved,
      })
      if (error) throw error
      await logAudit(supabase, user.id, {
        schoolId, action: 'mentor.subject_approve', targetType: 'mentor_subject_approval', targetId: `${mentorId}:${subjectId}`,
        outcome: 'success', metadata: { approved },
      })
      show(true, approved ? 'Subject approved.' : 'Subject rejected.')
      load()
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'Approval failed.')
    }
  }

  async function toggleActive(mentor: MentorRow) {
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('Not signed in.')
      const { error } = await supabase.from('teachers').update({ is_active: !mentor.is_active }).eq('id', mentor.id)
      if (error) throw error
      await logAudit(supabase, user.id, {
        schoolId, action: mentor.is_active ? 'mentor.suspend' : 'mentor.reactivate', targetType: 'teacher', targetId: mentor.id,
        outcome: 'success',
      })
      show(true, mentor.is_active ? 'Mentor deactivated.' : 'Mentor reactivated.')
      load()
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'Update failed.')
    }
  }

  async function setAvailability(mentorId: string, status: 'available' | 'away') {
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('Not signed in.')
      const { error } = await supabase.rpc('set_mentor_availability', { p_status: status })
      if (error) throw error
      await logAudit(supabase, user.id, {
        schoolId, action: 'mentor.availability', targetType: 'teacher', targetId: mentorId,
        outcome: 'success', metadata: { status },
      })
      show(true, `Availability set to ${status}.`)
      load()
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'Availability update failed.')
    }
  }

  if (error) return <ErrorState message={error} onRetry={load} />
  if (loading) return <LoadingState message="Loading mentors…" />

  return (
    <div>
      {node}
      <PageHeader
        title="Mentors"
        subtitle={`${filtered.length} of ${rows.length} roster records · Unapproved mentors cannot accept requests`}
        action={<button onClick={load} className={btnSecondary}>Refresh</button>}
      />
      <Card className="p-3 mb-4 flex flex-wrap gap-2">
        <input className={inputCls} style={{ maxWidth: 240 }} placeholder="Search name, staff ID, email…" value={query} onChange={(e) => setQuery(e.target.value)} />
        <select className={inputCls} style={{ maxWidth: 150 }} value={approvalFilter} onChange={(e) => setApprovalFilter(e.target.value)}>
          <option value="">Approval status</option>
          <option value="pending">Pending approval</option>
          <option value="approved">Approved (any subject)</option>
          <option value="none">No subject approvals</option>
        </select>
        <select className={inputCls} style={{ maxWidth: 140 }} value={activeFilter} onChange={(e) => setActiveFilter(e.target.value)}>
          <option value="">Availability</option>
          <option value="active">Active</option>
          <option value="inactive">Suspended</option>
        </select>
      </Card>
      <Card>
        {filtered.length === 0 ? <EmptyState title="No mentors match" /> : (
          <table className="data-table">
            <thead>
              <tr className="text-left text-ink-600 text-xs border-b sticky top-0 bg-white z-10">
                <th className="p-3">Mentor</th>
                <th className="p-3">Subjects approved</th>
                <th className="p-3 text-right">Availability</th>
                <th className="p-3 text-right">Status</th>
                <th className="p-3 text-right">Activated</th>
                <th className="p-3 text-right">Actions</th>
              </tr>
            </thead>
            <tbody>
              {filtered.map((r) => {
                const approvals = r.mentor_subject_approvals ?? []
                const approved = approvals.filter((a) => a.status === 'approved')
                const pending = approvals.filter((a) => a.status === 'pending')
                const availability = r.mentor_availability
                return (
                  <tr key={r.id} className="border-b border-ink-200 last:border-0 group">
                    <td className="p-3 font-medium">{r.first_name} {r.last_name} <span className="font-mono text-xs text-ink-400 block">({r.staff_id_no})</span></td>
                    <td className="p-3 text-sm">
                      {approved.length > 0 ? approved.map((a) => (a.subjects as any)?.name ?? 'Subject').join(', ') : 'None'}
                      {pending.length > 0 && <span className="text-amber-600 text-xs ml-1">({pending.length} pending)</span>}
                    </td>
                    <td className="p-3 text-right text-sm">
                      {availability?.status === 'available' ? (
                        <span className="inline-flex items-center gap-1 text-[10px] font-bold text-emerald-700"><CheckCircle className="h-3 w-3" /> Available</span>
                      ) : (
                        <span className="inline-flex items-center gap-1 text-[10px] font-bold text-ink-500"><Clock className="h-3 w-3" /> Away</span>
                      )}
                    </td>
                    <td className="p-3 text-right"><StatusBadge value={r.is_active ? 'active' : 'suspended'} /></td>
                    <td className="p-3 text-right text-xs">{r.user_id ? 'Yes' : 'No'}</td>
                    <td className="p-3 text-right whitespace-nowrap">
                      <button onClick={() => setEditing(r)} className="text-brand-600 text-xs hover:underline">Manage</button>
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        )}
      </Card>

      {editing && (
        <Modal title={`Mentor: ${editing.first_name} ${editing.last_name}`} onClose={() => setEditing(null)} wide>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            <div className="col-span-1 space-y-3">
              <p className="text-xs font-medium text-ink-600">Details</p>
              <p className="text-sm">{editing.first_name} {editing.last_name}</p>
              <p className="text-sm text-ink-600 font-mono">{editing.staff_id_no}</p>
              <p className="text-sm">{editing.phone}</p>
              {editing.email && <p className="text-sm">{editing.email}</p>}
              <p className="text-xs font-medium text-ink-600 mt-3">School leadership</p>
              <p className="text-sm">{editing.is_leadership ? 'Yes' : 'No'}</p>
              <p className="text-xs font-medium text-ink-600 mt-3">Account</p>
              <p className="text-sm">{editing.user_id ? 'Activated' : 'Not yet activated'}</p>
              {editing.is_active ? (
                <button onClick={() => toggleActive(editing)} className={btnSecondary}>Deactivate</button>
              ) : (
                <button onClick={() => toggleActive(editing)} className={btnPrimary}>Reactivate</button>
              )}
            </div>
            <div className="col-span-1 space-y-3">
              <p className="text-xs font-medium text-ink-600">Subject approvals</p>
              {subjects.length === 0 ? <p className="text-xs text-ink-400">No subjects configured.</p> : (
                <div className="space-y-2">
                  {subjects.map((s) => {
                    const a = (editing.mentor_subject_approvals ?? []).find((x) => x.subject_id === s.id)
                    const isApproved = a?.status === 'approved'
                    const isPending = a?.status === 'pending'
                    return (
                      <div key={s.id} className="flex items-center justify-between p-2 rounded-lg border border-ink-100 bg-white/50">
                        <span className="text-sm">{s.name}</span>
                        <div className="flex gap-1">
                          {isApproved ? (
                            <span className="text-[10px] font-bold text-emerald-700 bg-emerald-50 px-2 py-1 rounded">APPROVED</span>
                          ) : isPending ? (
                            <span className="text-[10px] font-bold text-amber-700 bg-amber-50 px-2 py-1 rounded">PENDING</span>
                          ) : (
                            <div className="flex gap-1">
                              <button onClick={() => approveSubject(editing.id, s.id, true)} className="text-[10px] text-emerald-600 hover:text-emerald-800 font-medium px-2 py-1">Approve</button>
                              <button onClick={() => approveSubject(editing.id, s.id, false)} className="text-[10px] text-rose-600 hover:text-rose-800 font-medium px-2 py-1">Reject</button>
                            </div>
                          )}
                        </div>
                      </div>
                    )
                  })}
                </div>
              )}
              <p className="text-xs font-medium text-ink-600 mt-3">Availability</p>
              <div className="flex gap-2">
                <button onClick={() => setAvailability(editing.id, 'available')} className={editing.mentor_availability?.status === 'available' ? 'text-xs text-emerald-700 font-medium bg-emerald-50 border border-emerald-100 rounded px-3 py-1.5' : 'text-xs text-emerald-600 hover:text-emerald-800 font-medium px-3 py-1.5'}>Available</button>
                <button onClick={() => setAvailability(editing.id, 'away')} className={editing.mentor_availability?.status === 'away' ? 'text-xs text-ink-700 font-medium bg-ink-50 border border-ink-100 rounded px-3 py-1.5' : 'text-xs text-ink-600 hover:text-ink-800 font-medium px-3 py-1.5'}>Away</button>
              </div>
              <p className="text-xs text-ink-500 mt-1">{editing.mentor_availability ? `Last updated: ${new Date(editing.mentor_availability.updated_at).toLocaleString()}` : 'Never set'}</p>
            </div>
            <div className="col-span-1 space-y-3 border-t border-ink-100 pt-4 md:col-span-3 md:border-t-0">
              <p className="text-xs font-medium text-ink-600">Impact warning</p>
              <p className="text-sm text-ink-700">
                Deactivating a mentor immediately revokes their school membership access. Any <strong>unconfirmed</strong>
                session bookings they hold remain requested — they will not be auto-reassigned. Confirm <strong>verified</strong>
                sessions are unaffected. Historical feedback and session records are preserved.
              </p>
              <button onClick={() => setEditing(null)} className={btnSecondary}>Close</button>
            </div>
          </div>
        </Modal>
      )}
    </div>
  )
}

