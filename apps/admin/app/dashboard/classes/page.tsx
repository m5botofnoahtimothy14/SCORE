'use client'

import { useEffect, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { logAudit } from '@/lib/audit'
import { PageHeader, Card, StatusBadge, LoadingState, ErrorState, inputCls, btnPrimary, btnSecondary, useToast } from '@/components/ui'

// Academic years, classes, subjects, enrollments viewer, bulk assignment.
export default function ClassesPage() {
  const [years, setYears] = useState<{ id: string; name: string; is_current: boolean }[]>([])
  const [classes, setClasses] = useState<{ id: string; name: string; grade: string; section: string | null; is_active: boolean; academic_year_id: string }[]>([])
  const [subjects, setSubjects] = useState<{ id: string; name: string; code: string | null }[]>([])
  const [enrollCounts, setEnrollCounts] = useState<Record<string, number>>({})
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [schoolId, setSchoolId] = useState<string | null>(null)
  const [yearForm, setYearForm] = useState({ name: '', starts_on: '', ends_on: '' })
  const [classForm, setClassForm] = useState({ name: '', grade: '', section: '', year_id: '' })
  const [subjectForm, setSubjectForm] = useState({ name: '', code: '' })
  const [bulkClass, setBulkClass] = useState('')
  const [bulkIds, setBulkIds] = useState('')
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
      setSchoolId(sid)
      const [{ data: y }, { data: c }, { data: s }, { data: e }] = await Promise.all([
        supabase.from('academic_years').select('id, name, is_current').eq('school_id', sid).order('name'),
        supabase.from('classes').select('id, name, grade, section, is_active, academic_year_id').eq('school_id', sid).order('name'),
        supabase.from('subjects').select('id, name, code').eq('school_id', sid).order('name'),
        supabase.from('class_enrollments').select('class_id').eq('school_id', sid).is('unenrolled_at', null),
      ])
      const counts: Record<string, number> = {}
      for (const row of ((e ?? []) as { class_id: string }[])) counts[row.class_id] = (counts[row.class_id] ?? 0) + 1
      setYears((y ?? []) as { id: string; name: string; is_current: boolean }[])
      setClasses((c ?? []) as typeof classes)
      setSubjects((s ?? []) as typeof subjects)
      setEnrollCounts(counts)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load.')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { load() }, [])

  async function audited(action: string, targetId?: string, metadata?: Record<string, unknown>) {
    const supabase = createClient()
    const { data: { user } } = await supabase.auth.getUser()
    await logAudit(supabase, user!.id, { schoolId, action, targetType: 'class', targetId, outcome: 'success', metadata })
  }

  async function createYear() {
    if (!yearForm.name || !yearForm.starts_on || !yearForm.ends_on) {
      show(false, 'Name, start and end dates are required.')
      return
    }
    try {
      const supabase = createClient()
      const { data, error } = await supabase.from('academic_years').insert({
        school_id: schoolId, name: yearForm.name, starts_on: yearForm.starts_on, ends_on: yearForm.ends_on, is_current: years.length === 0,
      }).select('id').single()
      if (error) throw error
      await audited('academic_year.create', (data as { id: string }).id)
      show(true, 'Academic year created.')
      setYearForm({ name: '', starts_on: '', ends_on: '' })
      load()
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'Create failed.')
    }
  }

  async function setCurrentYear(id: string) {
    try {
      const supabase = createClient()
      // Unset others first (partial unique index enforces a single current year).
      await supabase.from('academic_years').update({ is_current: false }).eq('school_id', schoolId)
      const { error } = await supabase.from('academic_years').update({ is_current: true }).eq('id', id)
      if (error) throw error
      await audited('academic_year.set_current', id)
      show(true, 'Current year updated.')
      load()
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'Update failed.')
    }
  }

  async function createClass() {
    if (!classForm.name || !classForm.grade || !classForm.year_id) {
      show(false, 'Name, grade and academic year are required.')
      return
    }
    try {
      const supabase = createClient()
      const { data, error } = await supabase.from('classes').insert({
        school_id: schoolId, academic_year_id: classForm.year_id,
        name: classForm.name, grade: classForm.grade, section: classForm.section || null,
      }).select('id').single()
      if (error) throw error
      await audited('class.create', (data as { id: string }).id)
      show(true, 'Class created.')
      setClassForm({ name: '', grade: '', section: '', year_id: '' })
      load()
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'Create failed.')
    }
  }

  async function createSubject() {
    if (!subjectForm.name) {
      show(false, 'Subject name is required.')
      return
    }
    try {
      const supabase = createClient()
      const { data, error } = await supabase.from('subjects').insert({
        school_id: schoolId, name: subjectForm.name, code: subjectForm.code || null,
      }).select('id').single()
      if (error) throw error
      await audited('subject.create', (data as { id: string }).id)
      show(true, 'Subject created.')
      setSubjectForm({ name: '', code: '' })
      load()
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'Create failed.')
    }
  }

  async function runBulkAssign() {
    const ids = bulkIds.split(/[\s,]+/).map((s) => s.trim()).filter(Boolean)
    if (!bulkClass || ids.length === 0) {
      show(false, 'Select a class and paste student IDs (one per line).')
      return
    }
    try {
      const supabase = createClient()
      const { data: found } = await supabase.from('students').select('id, student_id_no')
        .eq('school_id', schoolId!).in('student_id_no', ids)
      const foundIds = new Set(((found ?? []) as { student_id_no: string }[]).map((f) => f.student_id_no))
      const missing = ids.filter((i) => !foundIds.has(i))
      if (missing.length > 0) {
        show(false, `Unknown IDs: ${missing.slice(0, 5).join(', ')}${missing.length > 5 ? '…' : ''}`)
        return
      }
      let assigned = 0
      for (const f of (found ?? []) as { id: string }[]) {
        const { error } = await supabase.from('class_enrollments').insert({ school_id: schoolId, class_id: bulkClass, student_id: f.id })
        if (!error) assigned++
      }
      await audited('class.bulk_assign', bulkClass, { assigned })
      show(true, `Assigned ${assigned} students.`)
      setBulkIds('')
      load()
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'Bulk assignment failed.')
    }
  }

  if (loading) return <LoadingState />
  if (error) return <ErrorState message={error} onRetry={load} />

  return (
    <div>
      {node}
      <PageHeader title="Classes & Academic Years" subtitle="Structure, subjects and enrollments" />
      <div className="grid md:grid-cols-2 gap-4">
        <Card className="p-4">
          <h2 className="font-semibold mb-3">Academic years</h2>
          {years.map((y) => (
            <div key={y.id} className="flex items-center justify-between py-2 border-b border-gray-100 last:border-0 text-sm">
              <span>{y.name} {y.is_current && <StatusBadge value="active" />}</span>
              {!y.is_current && <button onClick={() => setCurrentYear(y.id)} className="text-blue-600 text-xs hover:underline">Set current</button>}
            </div>
          ))}
          <div className="grid grid-cols-3 gap-2 mt-3">
            <input className={inputCls} placeholder="2026-27" value={yearForm.name} onChange={(e) => setYearForm({ ...yearForm, name: e.target.value })} />
            <input className={inputCls} type="date" value={yearForm.starts_on} onChange={(e) => setYearForm({ ...yearForm, starts_on: e.target.value })} />
            <input className={inputCls} type="date" value={yearForm.ends_on} onChange={(e) => setYearForm({ ...yearForm, ends_on: e.target.value })} />
          </div>
          <button onClick={createYear} className={`${btnSecondary} mt-2`}>Add year</button>
        </Card>
        <Card className="p-4">
          <h2 className="font-semibold mb-3">Subjects</h2>
          <div className="flex flex-wrap gap-2 mb-3">
            {subjects.map((s) => <StatusBadge key={s.id} value={s.code ? `${s.name}` : s.name} />)}
            {subjects.length === 0 && <span className="text-sm text-gray-500">None yet.</span>}
          </div>
          <div className="grid grid-cols-2 gap-2">
            <input className={inputCls} placeholder="Mathematics" value={subjectForm.name} onChange={(e) => setSubjectForm({ ...subjectForm, name: e.target.value })} />
            <input className={inputCls} placeholder="Code (MATH)" value={subjectForm.code} onChange={(e) => setSubjectForm({ ...subjectForm, code: e.target.value })} />
          </div>
          <button onClick={createSubject} className={`${btnSecondary} mt-2`}>Add subject</button>
        </Card>
      </div>
      <Card className="p-4 mt-4">
        <h2 className="font-semibold mb-3">Classes</h2>
        <table className="w-full text-sm mb-4">
          <thead><tr className="text-left text-gray-500 text-xs border-b"><th className="py-2">Name</th><th>Grade</th><th>Section</th><th>Enrolled</th><th>Status</th></tr></thead>
          <tbody>
            {classes.map((c) => (
              <tr key={c.id} className="border-b border-gray-100 last:border-0">
                <td className="py-2 font-medium">{c.name}</td><td>{c.grade}</td><td>{c.section ?? '—'}</td>
                <td>{enrollCounts[c.id] ?? 0}</td>
                <td><StatusBadge value={c.is_active ? 'active' : 'suspended'} /></td>
              </tr>
            ))}
          </tbody>
        </table>
        <div className="grid md:grid-cols-4 gap-2">
          <input className={inputCls} placeholder="Class name (Grade 8-A)" value={classForm.name} onChange={(e) => setClassForm({ ...classForm, name: e.target.value })} />
          <input className={inputCls} placeholder="Grade (8)" value={classForm.grade} onChange={(e) => setClassForm({ ...classForm, grade: e.target.value })} />
          <input className={inputCls} placeholder="Section (A)" value={classForm.section} onChange={(e) => setClassForm({ ...classForm, section: e.target.value })} />
          <select className={inputCls} value={classForm.year_id} onChange={(e) => setClassForm({ ...classForm, year_id: e.target.value })}>
            <option value="">Academic year…</option>
            {years.map((y) => <option key={y.id} value={y.id}>{y.name}</option>)}
          </select>
        </div>
        <button onClick={createClass} className={`${btnPrimary} mt-2`}>Add class</button>
      </Card>
      <Card className="p-4 mt-4">
        <h2 className="font-semibold mb-1">Bulk assignment</h2>
        <p className="text-xs text-gray-500 mb-3">Enroll many students (by Student ID) into a class at once.</p>
        <select className={`${inputCls} mb-2`} value={bulkClass} onChange={(e) => setBulkClass(e.target.value)}>
          <option value="">Select class…</option>
          {classes.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
        </select>
        <textarea className={inputCls} rows={4} placeholder={'S1001\nS1002'} value={bulkIds} onChange={(e) => setBulkIds(e.target.value)} />
        <button onClick={runBulkAssign} className={`${btnPrimary} mt-2`}>Assign students</button>
      </Card>
    </div>
  )
}
