'use client'

import { useEffect, useMemo, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { logAudit } from '@/lib/audit'
import { parseTeacherCsv, TEACHER_CSV_TEMPLATE } from '@/lib/csv'
import { PageHeader, Card, StatusBadge, LoadingState, ErrorState, Modal, inputCls, btnPrimary, btnSecondary, useToast, EmptyState } from '@/components/ui'

interface Teacher {
  id: string
  staff_id_no: string
  first_name: string
  last_name: string
  phone: string
  email: string | null
  is_active: boolean
  is_leadership: boolean
  user_id: string | null
  assignments?: { class_name: string; subject: string | null }[]
}

// Teachers roster, assignments, leadership flag, CSV import. Teachers can
// never self-assign: all changes here are admin-only and audited.
export default function TeachersPage() {
  const [teachers, setTeachers] = useState<Teacher[]>([])
  const [classes, setClasses] = useState<{ id: string; name: string }[]>([])
  const [subjects, setSubjects] = useState<{ id: string; name: string }[]>([])
  const [query, setQuery] = useState('')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [editing, setEditing] = useState<Partial<Teacher> | null>(null)
  const [assigning, setAssigning] = useState<Teacher | null>(null)
  const [assignForm, setAssignForm] = useState({ class_id: '', subject_id: '' })
  const [importOpen, setImportOpen] = useState(false)
  const [importText, setImportText] = useState('')
  const [importReport, setImportReport] = useState<{ ok: number; errors: { line: number; message: string }[] } | null>(null)
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
      const schoolId = (membership as { school_id: string } | null)?.school_id
      if (!schoolId) throw new Error('No school scope.')
      const [{ data: t }, { data: c }, { data: s }, { data: a }] = await Promise.all([
        supabase.from('teachers').select('*').eq('school_id', schoolId).order('first_name').limit(1000),
        supabase.from('classes').select('id, name').eq('school_id', schoolId).eq('is_active', true).order('name'),
        supabase.from('subjects').select('id, name').eq('school_id', schoolId).order('name'),
        supabase.from('teaching_assignments').select('teacher_id, class_id, subject_id, classes(name), subjects(name)').eq('school_id', schoolId),
      ])
      const byTeacher = new Map<string, { class_name: string; subject: string | null }[]>()
      for (const row of (((a ?? []) as unknown) as { teacher_id: string; classes: { name: string } | null; subjects: { name: string } | null }[])) {
        const list = byTeacher.get(row.teacher_id) ?? []
        list.push({ class_name: row.classes?.name ?? 'â€”', subject: row.subjects?.name ?? null })
        byTeacher.set(row.teacher_id, list)
      }
      setTeachers((((t ?? []) as Teacher[])).map((x) => ({ ...x, assignments: byTeacher.get(x.id) ?? [] })))
      setClasses((c ?? []) as { id: string; name: string }[])
      setSubjects((s ?? []) as { id: string; name: string }[])
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load teachers.')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { load() }, [])

  const filtered = useMemo(() => {
    const q = query.toLowerCase()
    return teachers.filter((t) => !q || `${t.first_name} ${t.last_name} ${t.staff_id_no}`.toLowerCase().includes(q))
  }, [teachers, query])

  async function save() {
    if (!editing?.first_name?.trim() || !editing?.last_name?.trim() || !editing?.staff_id_no?.trim() || !editing?.phone?.trim()) {
      show(false, 'Name, Staff ID and phone are required.')
      return
    }
    if (!/^\+[1-9]\d{6,14}$/.test(editing.phone.trim())) {
      show(false, 'Phone must be in E.164 format (+...).')
      return
    }
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      const { data: membership } = await supabase.from('school_memberships').select('school_id')
        .eq('user_id', user!.id).eq('is_active', true).limit(1).maybeSingle()
      const schoolId = (membership as { school_id: string }).school_id
      if (editing.id) {
        const { error } = await supabase.from('teachers').update({
          first_name: editing.first_name.trim(), last_name: editing.last_name.trim(),
          phone: editing.phone.trim(), email: editing.email || null,
          is_leadership: Boolean(editing.is_leadership),
        }).eq('id', editing.id)
        if (error) throw error
        await logAudit(supabase, user!.id, { schoolId, action: 'teacher.update', targetType: 'teacher', targetId: editing.id, outcome: 'success' })
        show(true, 'Teacher updated.')
      } else {
        const { data, error } = await supabase.from('teachers').insert({
          school_id: schoolId, staff_id_no: editing.staff_id_no.trim(),
          first_name: editing.first_name.trim(), last_name: editing.last_name.trim(),
          phone: editing.phone.trim(), email: editing.email || null,
          is_leadership: Boolean(editing.is_leadership),
        }).select('id').single()
        if (error) throw error
        await logAudit(supabase, user!.id, { schoolId, action: 'teacher.create', targetType: 'teacher', targetId: (data as { id: string }).id, outcome: 'success' })
        show(true, 'Teacher added to roster. They activate via OTP.')
      }
      setEditing(null)
      load()
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'Save failed.')
    }
  }

  async function toggleActive(t: Teacher) {
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      const { data: membership } = await supabase.from('school_memberships').select('school_id')
        .eq('user_id', user!.id).eq('is_active', true).limit(1).maybeSingle()
      const { error } = await supabase.from('teachers').update({ is_active: !t.is_active }).eq('id', t.id)
      if (error) throw error
      await logAudit(supabase, user!.id, {
        schoolId: (membership as { school_id: string }).school_id,
        action: t.is_active ? 'teacher.suspend' : 'teacher.reactivate',
        targetType: 'teacher', targetId: t.id, outcome: 'success',
      })
      show(true, t.is_active ? 'Teacher deactivated.' : 'Teacher reactivated.')
      load()
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'Update failed.')
    }
  }

  async function addAssignment() {
    if (!assigning || !assignForm.class_id) {
      show(false, 'Select a class.')
      return
    }
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      const { data: membership } = await supabase.from('school_memberships').select('school_id')
        .eq('user_id', user!.id).eq('is_active', true).limit(1).maybeSingle()
      const schoolId = (membership as { school_id: string }).school_id
      const { error } = await supabase.from('teaching_assignments').insert({
        school_id: schoolId, teacher_id: assigning.id, class_id: assignForm.class_id,
        subject_id: assignForm.subject_id || null,
      })
      if (error) throw error
      await logAudit(supabase, user!.id, { schoolId, action: 'teaching.assign', targetType: 'teacher', targetId: assigning.id, outcome: 'success', metadata: assignForm })
      show(true, 'Assignment added.')
      setAssigning(null)
      setAssignForm({ class_id: '', subject_id: '' })
      load()
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'Assignment failed.')
    }
  }

  async function runImport(commit: boolean) {
    const { rows, errors } = parseTeacherCsv(importText)
    if (!commit) {
      setImportReport({ ok: rows.length, errors })
      return
    }
    if (errors.length > 0) {
      show(false, 'Fix validation errors before committing.')
      return
    }
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      const { data: membership } = await supabase.from('school_memberships').select('school_id')
        .eq('user_id', user!.id).eq('is_active', true).limit(1).maybeSingle()
      const schoolId = (membership as { school_id: string }).school_id
      const { data: existing } = await supabase.from('teachers').select('staff_id_no').eq('school_id', schoolId)
        .in('staff_id_no', rows.map((r) => r.staff_id_no))
      const existingIds = new Set(((existing ?? []) as { staff_id_no: string }[]).map((e) => e.staff_id_no))
      const dupes = rows.filter((r) => existingIds.has(r.staff_id_no))
      if (dupes.length > 0) {
        setImportReport({ ok: 0, errors: dupes.map((d) => ({ line: 0, message: `already exists: ${d.staff_id_no}` })) })
        return
      }
      for (const r of rows) {
        const { error } = await supabase.from('teachers').insert({
          school_id: schoolId, staff_id_no: r.staff_id_no, first_name: r.first_name,
          last_name: r.last_name, phone: r.phone, email: r.email ?? null, is_leadership: Boolean(r.is_leadership),
        })
        if (error) throw new Error(`insert failed for ${r.staff_id_no}: ${error.message}`)
      }
      await logAudit(supabase, user!.id, { schoolId, action: 'roster.import', targetType: 'teachers', outcome: 'success', metadata: { imported: rows.length } })
      show(true, `Imported ${rows.length} teachers.`)
      setImportOpen(false)
      setImportText('')
      setImportReport(null)
      load()
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'Import failed.')
    }
  }

  if (loading) return <LoadingState />
  if (error) return <ErrorState message={error} onRetry={load} />

  return (
    <div>
      {node}
      <PageHeader
        title="Teachers"
        subtitle={`${filtered.length} roster records`}
        action={<div className="flex gap-2">
          <button onClick={() => { setImportOpen(true); setImportReport(null) }} className={btnSecondary}>Import CSV</button>
          <button onClick={() => setEditing({})} className={btnPrimary}>Add teacher</button>
        </div>}
      />
      <Card className="p-3 mb-4">
        <input className={inputCls} style={{ maxWidth: 260 }} placeholder="Search name or staff ID..." value={query} onChange={(e) => setQuery(e.target.value)} />
      </Card>
      <Card>
        {filtered.length === 0 ? <EmptyState title="No teachers found" /> : (
          <table className="w-full text-sm">
            <thead><tr className="text-left text-ink-600 text-xs border-b">
              <th className="p-3">Name</th><th>Staff ID</th><th>Phone</th><th>Classes</th><th>Status</th><th>Activated</th><th className="text-right pr-3">Actions</th>
            </tr></thead>
            <tbody>
              {filtered.map((t) => (
                <tr key={t.id} className="border-b border-ink-200 last:border-0">
                  <td className="p-3 font-medium">{t.first_name} {t.last_name}{t.is_leadership && ' Â· leadership'}</td>
                  <td className="font-mono text-xs">{t.staff_id_no}</td>
                  <td className="text-xs">{t.phone}</td>
                  <td className="text-xs">{t.assignments?.map((a) => `${a.class_name}${a.subject ? ` (${a.subject})` : ''}`).join(', ') || 'â€”'}</td>
                  <td><StatusBadge value={t.is_active ? 'active' : 'suspended'} /></td>
                  <td>{t.user_id ? 'Yes' : 'No'}</td>
                  <td className="text-right pr-3 whitespace-nowrap">
                    <button onClick={() => setEditing(t)} className="text-brand-600 text-xs mr-2 hover:underline">Edit</button>
                    <button onClick={() => setAssigning(t)} className="text-brand-600 text-xs mr-2 hover:underline">Assign</button>
                    <button onClick={() => toggleActive(t)} className="text-xs text-ink-700 hover:underline">{t.is_active ? 'Deactivate' : 'Reactivate'}</button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </Card>

      {editing && (
        <Modal title={editing.id ? 'Edit teacher' : 'Add teacher'} onClose={() => setEditing(null)}>
          <div className="space-y-3">
            <div className="grid grid-cols-2 gap-3">
              <input className={inputCls} placeholder="First name *" value={editing.first_name ?? ''} onChange={(e) => setEditing({ ...editing, first_name: e.target.value })} />
              <input className={inputCls} placeholder="Last name *" value={editing.last_name ?? ''} onChange={(e) => setEditing({ ...editing, last_name: e.target.value })} />
            </div>
            {!editing.id && <input className={inputCls} placeholder="Staff ID *" value={editing.staff_id_no ?? ''} onChange={(e) => setEditing({ ...editing, staff_id_no: e.target.value })} />}
            <input className={inputCls} placeholder="Phone (E.164) *" value={editing.phone ?? ''} onChange={(e) => setEditing({ ...editing, phone: e.target.value })} />
            <input className={inputCls} placeholder="Email (optional)" value={editing.email ?? ''} onChange={(e) => setEditing({ ...editing, email: e.target.value })} />
            <label className="text-sm flex items-center gap-2">
              <input type="checkbox" checked={Boolean(editing.is_leadership)} onChange={(e) => setEditing({ ...editing, is_leadership: e.target.checked })} />
              School leadership (principal / head)
            </label>
            <div className="flex justify-end gap-2 pt-2">
              <button onClick={() => setEditing(null)} className={btnSecondary}>Cancel</button>
              <button onClick={save} className={btnPrimary}>Save</button>
            </div>
          </div>
        </Modal>
      )}

      {assigning && (
        <Modal title={`Assign ${assigning.first_name} ${assigning.last_name}`} onClose={() => setAssigning(null)}>
          <div className="space-y-3">
            <select className={inputCls} value={assignForm.class_id} onChange={(e) => setAssignForm({ ...assignForm, class_id: e.target.value })}>
              <option value="">Select class *</option>
              {classes.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
            </select>
            <select className={inputCls} value={assignForm.subject_id} onChange={(e) => setAssignForm({ ...assignForm, subject_id: e.target.value })}>
              <option value="">No specific subject</option>
              {subjects.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
            </select>
            <div className="flex justify-end gap-2 pt-2">
              <button onClick={() => setAssigning(null)} className={btnSecondary}>Cancel</button>
              <button onClick={addAssignment} className={btnPrimary}>Add assignment</button>
            </div>
          </div>
        </Modal>
      )}

      {importOpen && (
        <Modal title="Import teacher roster (CSV)" wide onClose={() => setImportOpen(false)}>
          <p className="text-xs text-ink-600 mb-2">Columns: first_name,last_name,staff_id_no,phone,email,is_leadership,class_grade,class_section,subject</p>
          <button onClick={() => setImportText(TEACHER_CSV_TEMPLATE)} className="text-xs text-brand-600 hover:underline mb-2">Load template</button>
          <textarea className={inputCls} rows={8} value={importText} onChange={(e) => setImportText(e.target.value)} placeholder="Paste CSV here..." />
          {importReport && (
            <div className="mt-2 text-sm">
              <p className="text-ink-800">{importReport.ok} valid rows.</p>
              {importReport.errors.map((e, i) => <p key={i} className="text-red-600 text-xs">Line {e.line}: {e.message}</p>)}
            </div>
          )}
          <div className="flex justify-end gap-2 pt-3">
            <button onClick={() => runImport(false)} className={btnSecondary}>Validate</button>
            <button onClick={() => runImport(true)} className={btnPrimary}>Commit import</button>
          </div>
        </Modal>
      )}
    </div>
  )
}
