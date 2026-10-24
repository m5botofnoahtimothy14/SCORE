/* eslint-disable @typescript-eslint/no-explicit-any, @typescript-eslint/no-unused-vars */
'use client'

import { useEffect, useMemo, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { logAudit } from '@/lib/audit'
import {
  PageHeader, Card, StatusBadge, LoadingState, ErrorState,
  inputCls, btnPrimary, btnSecondary, useToast, EmptyState, Modal,
} from '@/components/ui'
import { AlertTriangle, CheckCircle, Star, RotateCcw, Users } from 'lucide-react'

interface RatingRow {
  id: string
  school_id: string
  request_id: string
  student_id: string
  mentor_id: string
  rating: number
  comment: string | null
  created_at: string
  students?: { student_id_no: string; first_name: string; last_name: string } | null
  user_profiles?: { display_name: string } | null
  doubt_requests?: { subject_id: string; status: string; subjects?: { name: string } } | null
}

interface AssessmentRow {
  id: string
  school_id: string
  request_id: string
  mentor_id: string
  student_id: string
  preparation: 'unprepared' | 'developing' | 'satisfactory' | 'strong' | 'outstanding'
  engagement: 'unprepared' | 'developing' | 'satisfactory' | 'strong' | 'outstanding'
  private_note: string | null
  created_at: string
  updated_at: string
  doubt_requests?: { subject_id: string; subjects?: { name: string } } | null
}

// Feedback review — student ratings (1–5★) plus the mentor's private
// student assessment (visible only to that mentor and authorized admins).
export default function RatingsPage() {
  const [ratings, setRatings] = useState<RatingRow[]>([])
  const [assessments, setAssessments] = useState<AssessmentRow[]>([])
  const [mentors, setMentors] = useState<{ id: string; name: string }[]>([])
  const [subjects, setSubjects] = useState<{ id: string; name: string }[]>([])
  const [query, setQuery] = useState('')
  const [ratingFilter, setRatingFilter] = useState('')
  const [typeFilter, setTypeFilter] = useState('all') // all | ratings | assessments
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

      const { data: membership } = await supabase
        .from('school_memberships')
        .select('school_id, role')
        .eq('user_id', user.id)
        .eq('is_active', true)
        .in('role', ['platform_owner', 'school_admin', 'principal'])
        .order('joined_at', { ascending: false })
        .limit(1)
        .maybeSingle()
      const sid = (membership as { school_id: string } | null)?.school_id
      if (!sid) throw new Error('No school scope.')
      setSchoolId(sid)

      const [resRatings, resAssessments, resMentors, resSubjects] = await Promise.all([
        supabase.from('ratings').select(`
          id, school_id, request_id, student_id, mentor_id, rating, comment, created_at,
          students(student_id_no, first_name, last_name),
          user_profiles!ratings_mentor_id_fkey(display_name),
          doubt_requests(subject_id, status, subjects(name))
        `).eq('school_id', sid).order('created_at', { ascending: false }),
        supabase.from('mentor_assessments').select(`
          id, school_id, request_id, mentor_id, student_id, preparation, engagement,
          private_note, created_at, updated_at,
          doubt_requests(subject_id, subjects(name))
        `).eq('school_id', sid).order('created_at', { ascending: false }),
        supabase.from('teachers').select('id, first_name, last_name').eq('school_id', sid).eq('is_active', true).order('first_name'),
        supabase.from('subjects').select('id, name').eq('school_id', sid).order('name'),
      ])
      if (!resRatings || !resAssessments || !resMentors || !resSubjects) throw new Error('Failed to load feedback data.')
      if (resRatings.error) throw resRatings.error
      if (resAssessments.error) throw resAssessments.error
      setRatings((resRatings.data ?? []) as unknown as RatingRow[])
      setAssessments((resAssessments.data ?? []) as unknown as AssessmentRow[])
      setMentors(((resMentors.data ?? []) as { id: string; first_name: string; last_name: string }[]).map((t) => ({
        id: t.id, name: t.first_name + ' ' + t.last_name,
      })))
      setSubjects((resSubjects.data ?? []) as { id: string; name: string }[])
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load feedback.')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { load() }, [])

  const filteredRatings = useMemo(() => {
    const q = query.toLowerCase()
    return ratings.filter((r) => {
      const student = r.students as any
      const subject = r.doubt_requests?.subjects as any
      const matchText = !q ||
        `${student?.first_name ?? ''} ${student?.last_name ?? ''} ${student?.student_id_no ?? ''} ${r.comment ?? ''} ${subject?.name ?? ''}`.toLowerCase().includes(q)
      const matchRating = !ratingFilter || r.rating === Number(ratingFilter)
      return matchText && matchRating
    })
  }, [ratings, query, ratingFilter])

  const filteredAssessments = useMemo(() => {
    const q = query.toLowerCase()
    return assessments.filter((a) => {
      const subject = a.doubt_requests?.subjects as any
      const matchText = !q || `${subject?.name ?? ''} ${a.private_note ?? ''}`.toLowerCase().includes(q)
      return matchText
    })
  }, [assessments, query])

  const stars = (n: number) => '★'.repeat(n) + '☆'.repeat(5 - n)

  async function flagForReview(type: 'rating' | 'assessment', id: string, reason: string) {
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('Not signed in.')
      await logAudit(supabase, user.id, {
        schoolId, action: type === 'rating' ? 'rating.flag' : 'assessment.flag',
        targetType: type, targetId: id, outcome: 'success', reason,
      })
      show(true, 'Flagged for review (audit recorded).')
      load()
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'Flag failed.')
    }
  }

  if (error) return <ErrorState message={error} onRetry={load} />
  if (loading) return <LoadingState message="Loading feedback…" />

  return (
    <div>
      {node}
      <PageHeader
        title="Feedback & Ratings"
        subtitle="Student ratings (1–5★) and mentor's private student assessments — never exposed to students."
        action={<button onClick={load} className={btnSecondary}>Refresh</button>}
      />
      <Card className="p-3 mb-4 flex flex-wrap gap-2">
        <div className="flex items-center gap-2">
          <label className="text-xs text-ink-600">View</label>
          <button onClick={() => setTypeFilter('all')} className={`px-3 py-1 text-xs rounded ${typeFilter === 'all' ? 'bg-brand-100 text-brand-700' : 'text-ink-600 hover:bg-ink-50'}`}>All</button>
          <button onClick={() => setTypeFilter('ratings')} className={`px-3 py-1 text-xs rounded ${typeFilter === 'ratings' ? 'bg-brand-100 text-brand-700' : 'text-ink-600 hover:bg-ink-50'}`}>Ratings</button>
          <button onClick={() => setTypeFilter('assessments')} className={`px-3 py-1 text-xs rounded ${typeFilter === 'assessments' ? 'bg-brand-100 text-brand-700' : 'text-ink-600 hover:bg-ink-50'}`}>Assessments</button>
        </div>
        <input className={inputCls} style={{ maxWidth: 240 }} placeholder="Search student, mentor, subject, comment…" value={query} onChange={(e) => setQuery(e.target.value)} />
        {typeFilter === 'ratings' && (
          <select className={inputCls} style={{ maxWidth: 130 }} value={ratingFilter} onChange={(e) => setRatingFilter(e.target.value)}>
            <option value="">Filter by stars</option>
            {[1, 2, 3, 4, 5].map((n) => <option key={n} value={String(n)}>{n}★</option>)}
          </select>
        )}
      </Card>

      {typeFilter === 'ratings' ? (
        <Card>
          {filteredRatings.length === 0 ? <EmptyState title="No ratings match" /> : (
            <div className="overflow-x-auto mask-fade-r">
              <table className="data-table">
                <thead>
                  <tr className="text-left text-ink-600 text-xs border-b sticky top-0 bg-white z-10">
                    <th className="p-3">Student</th>
                    <th className="p-3">Mentor</th>
                    <th className="p-3 text-center">Rating</th>
                    <th className="p-3">Subject</th>
                    <th className="p-3">Comment</th>
                    <th className="p-3 text-right">Submitted</th>
                    <th className="p-3 text-right">Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {filteredRatings.map((r) => {
                    const student = r.students as any
                    const subject = r.doubt_requests?.subjects as any
                    return (
                      <tr key={r.id} className="border-b border-ink-200 last:border-0">
                        <td className="p-3 font-medium">{student?.first_name ?? '—'} {student?.last_name ?? ''}</td>
                        <td className="p-3 text-sm">{r.user_profiles?.display_name ?? '—'}</td>
                        <td className="p-3 text-center font-bold">{stars(r.rating)}</td>
                        <td className="p-3 text-sm">{subject?.name ?? '—'}</td>
                        <td className="p-3 text-sm max-w-xs truncate text-ink-600">{r.comment ?? '—'}</td>
                        <td className="p-3 text-right text-xs">{new Date(r.created_at).toLocaleString()}</td>
                        <td className="p-3 text-right whitespace-nowrap">
                          <button onClick={() => flagForReview('rating', r.id, 'Admin flagged for review')} className="text-[10px] text-rose-600 hover:text-rose-800 font-medium">Flag</button>
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
          )}
        </Card>
      ) : (
        <Card>
          {filteredAssessments.length === 0 ? <EmptyState title="No mentor assessments match" subtitle="Private assessments are only visible to the assigning mentor and administrators." /> : (
            <div className="overflow-x-auto mask-fade-r">
              <table className="data-table">
                <thead>
                  <tr className="text-left text-ink-600 text-xs border-b sticky top-0 bg-white z-10">
                    <th className="p-3">Student</th>
                    <th className="p-3">Mentor</th>
                    <th className="p-3 text-center">Preparation</th>
                    <th className="p-3 text-center">Engagement</th>
                    <th className="p-3">Subject</th>
                    <th className="p-3 text-right">Private note</th>
                    <th className="p-3 text-right">Submitted</th>
                    <th className="p-3 text-right">Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {filteredAssessments.map((a) => {
                    const subject = a.doubt_requests?.subjects as any
                    return (
                      <tr key={a.id} className="border-b border-ink-200 last:border-0">
                        <td className="p-3 font-medium">{a.student_id}</td>
                        <td className="p-3 text-sm">{mentors.find((m) => m.id === a.mentor_id)?.name ?? '—'}</td>
                        <td className="p-3 text-center text-sm">{scaleLabel(a.preparation)}</td>
                        <td className="p-3 text-center text-sm">{scaleLabel(a.engagement)}</td>
                        <td className="p-3 text-sm">{subject?.name ?? '—'}</td>
                        <td className="p-3 text-sm max-w-xs truncate text-ink-600">{a.private_note ?? '—'}</td>
                        <td className="p-3 text-right text-xs">{new Date(a.created_at).toLocaleString()}</td>
                        <td className="p-3 text-right whitespace-nowrap">
                          <button onClick={() => flagForReview('assessment', a.id, 'Admin flagged for review')} className="text-[10px] text-rose-600 hover:text-rose-800 font-medium">Flag</button>
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
          )}
        </Card>
      )}
    </div>
  )
}

function scaleLabel(v: string) {
  const map: Record<string, string> = {
    unprepared: 'Unprepared',
    developing: 'Developing',
    satisfactory: 'Satisfactory',
    strong: 'Strong',
    outstanding: 'Outstanding',
  }
  return map[v] ?? v
}

