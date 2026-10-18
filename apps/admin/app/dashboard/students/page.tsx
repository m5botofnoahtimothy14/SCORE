'use client'

import { useEffect, useMemo, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { logAudit } from '@/lib/audit'
import { parseStudentCsv, STUDENT_CSV_TEMPLATE } from '@/lib/csv'
import { PageHeader, Card, StatusBadge, LoadingState, ErrorState, Modal, inputCls, btnPrimary, btnSecondary, useToast, EmptyState } from '@/components/ui'

interface Student {
  id: string
  student_id_no: string
  first_name: string
  last_name: string
  is_active: boolean
  user_id: string | null
  class_id?: string | null
  class_name?: string | null
}

interface ClassOption { id: string; name: string }

// Students: roster CRUD, class assignment (via reassign_student_class RPC),
// activation-code issuance (one-time display), CSV import with validation.
export default function StudentsPage() {
  const [students, setStudents] = useState<Student[]>([])
  const [classes, setClasses] = useState<ClassOption[]>([])
  const [classFilter, setClassFilter] = useState('')
  const [query, setQuery] = useState('')
  const [showInactive, setShowInactive] = useState(false)
  const [page, setPage] = useState(0)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [editing, setEditing] = useState<{ id?: string; first_name?: string; last_name?: string; student_id_no?: string; class_id?: string | null } | null>(null)
  const [importOpen, setImportOpen] = useState(false)
  const [importText, setImportText] = useState('')
  const [importReport, setImportReport] = useState<{ ok: number; errors: { line: number; message: string }[] } | null>(null)
  const [issuedCode, setIssuedCode] = useState<{ name: string; code: string; expires: string } | null>(null)
  const { show, node } = useToast()

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
        .eq('user_id', user.id).eq('is_active', true)
        .in('role', ['platform_owner', 'school_admin', 'principal'])
        .limit(1).maybeSingle()
      const schoolId = (membership as { school_id: string } | null)?.school_id
      if (!schoolId) throw new Error('No school scope.')
      const [{ data: sData, error: sErr }, { data: cData }] = await Promise.all([
        supabase.from('students').select('id, student_id_no, first_name, last_name, is_active, user_id').eq('school_id', schoolId).order('first_name').limit(1000),
        supabase.from('classes').select('id, name').eq('school_id', schoolId).eq('is_active', true).order('name'),
      ])
      if (sErr) throw sErr
      const enrollments = await supabase
        .from('class_enrollments')
        .select('student_id, class_id, classes(name)')
        .eq('school_id', schoolId)
        .is('unenrolled_at', null)
      const enrMap = new Map<string, { class_id: string; name: string }>()
      for (const e of ((enrollments.data ?? []) as unknown as { student_id: string; class_id: string; classes: { name: string } }[])) {
        enrMap.set(e.student_id, { class_id: e.class_id, name: e.classes?.name })
      }
      setStudents(((sData ?? []) as Omit<Student, 'class_id' | 'class_name'>[]).map((s) => ({
        ...s, class_id: enrMap.get(s.id)?.class_id ?? null, class_name: enrMap.get(s.id)?.name ?? null,
      })))
      setClasses((cData ?? []) as ClassOption[])
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load students.')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { load() }, [])

  const filtered = useMemo(() => {
    const q = query.toLowerCase()
    return students.filter((s) =>
      (showInactive || s.is_active) &&
      (!classFilter || s.class_id === classFilter) &&
      (!q || `${s.first_name} ${s.last_name} ${s.student_id_no}`.toLowerCase().includes(q))
    )
  }, [students, query, classFilter, showInactive])

  const PAGE_SIZE = 25
  const pageRows = filtered.slice(page * PAGE_SIZE, page * PAGE_SIZE + PAGE_SIZE)

  async function save() {
    if (!editing?.first_name?.trim() || !editing?.last_name?.trim() || !editing?.student_id_no?.trim()) {
      show(false, 'Name and Student ID are required.')
      return
    }
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      const { data: membership } = await supabase.from('school_memberships').select('school_id')
        .eq('user_id', user!.id).eq('is_active', true).limit(1).maybeSingle()
      const schoolId = (membership as { school_id: string }).school_id
      if (editing.id) {
        const { error } = await supabase.from('students').update({
          first_name: editing.first_name.trim(), last_name: editing.last_name.trim(),
        }).eq('id', editing.id)
        if (error) throw error
        if (editing.class_id) {
          const { data: res, error: rErr } = await supabase.rpc('reassign_student_class', {
            p_student_id: editing.id, p_new_class_id: editing.class_id, p_reason: 'Corrected from Students page',
          })
          if (rErr) throw rErr
          if (!(res as { success: boolean }).success) throw new Error((res as { error: string }).error)
        }
        await logAudit(supabase, user!.id, { schoolId, action: 'student.update', targetType: 'student', targetId: editing.id, outcome: 'success' })
        show(true, 'Student updated.')
      } else {
        const { data, error } = await supabase.from('students').insert({
          school_id: schoolId,
          student_id_no: editing.student_id_no.trim(),
          first_name: editing.first_name.trim(), last_name: editing.last_name.trim(),
        }).select('id').single()
        if (error) throw error
        const newId = (data as { id: string }).id
        if (editing.class_id) {
          await supabase.from('class_enrollments').insert({ school_id: schoolId, class_id: editing.class_id, student_id: newId })
        }
        await logAudit(supabase, user!.id, { schoolId, action: 'student.create', targetType: 'student', targetId: newId, outcome: 'success' })
        show(true, 'Student added. Issue an activation code next.')
      }
      setEditing(null)
      load()
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'Save failed.')
    }
  }

  async function toggleActive(s: Student) {
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      const { data: membership } = await supabase.from('school_memberships').select('school_id')
        .eq('user_id', user!.id).eq('is_active', true).limit(1).maybeSingle()
      const { error } = await supabase.from('students').update({ is_active: !s.is_active }).eq('id', s.id)
      if (error) throw error
      await logAudit(supabase, user!.id, {
        schoolId: (membership as { school_id: string }).school_id,
        action: s.is_active ? 'student.suspend' : 'student.reactivate',
        targetType: 'student', targetId: s.id, outcome: 'success',
      })
      show(true, s.is_active ? 'Student deactivated.' : 'Student reactivated.')
      load()
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'Update failed.')
    }
  }

  async function issueCode(s: Student) {
    setIssuedCode(null)
    try {
      const res = await fetch('/api/activation-code', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ student_id: s.id }),
      })
      const data = await res.json()
      if (!data.success) throw new Error(data.error ?? 'issue_failed')
      setIssuedCode({ name: `${s.first_name} ${s.last_name}`, code: data.code, expires: data.expires_at })
      show(true, 'Code issued â€” copy it now, it will not be shown again.')
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'Could not issue code.')
    }
  }

  async function runImport(commit: boolean) {
    const { rows, errors } = parseStudentCsv(importText)
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
      const { data: year } = await supabase.from('academic_years').select('id').eq('school_id', schoolId).eq('is_current', true).maybeSingle()
      // Pre-check duplicates already in DB
      const { data: existing } = await supabase.from('students').select('student_id_no').eq('school_id', schoolId)
        .in('student_id_no', rows.map((r) => r.student_id_no))
      const existingIds = new Set(((existing ?? []) as { student_id_no: string }[]).map((e) => e.student_id_no))
      const dupes = rows.filter((r) => existingIds.has(r.student_id_no))
      if (dupes.length > 0) {
        setImportReport({ ok: 0, errors: dupes.map((d, i) => ({ line: i + 2, message: `already exists in roster: ${d.student_id_no}` })) })
        return
      }
      let imported = 0
      for (const r of rows) {
        const { data: created, error } = await supabase.from('students').insert({
          school_id: schoolId, student_id_no: r.student_id_no,
          first_name: r.first_name, last_name: r.last_name, is_active: true,
        }).select('id').single()
        if (error) throw new Error(`insert failed for ${r.student_id_no}: ${error.message}`)
        const newId = (created as { id: string }).id
        // Resolve class by grade+section in current year
        const cls = classes.find((c) => c.name.includes(r.class_grade) && (!r.class_section || c.name.includes(r.class_section)))
        if (cls && year) {
          await supabase.from('class_enrollments').insert({ school_id: schoolId, class_id: cls.id, student_id: newId })
        }
        imported++
      }
      await logAudit(supabase, user!.id, { schoolId, action: 'roster.import', targetType: 'students', outcome: 'success', metadata: { imported } })
      show(true, `Imported ${imported} students.`)
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
        title="Students"
        subtitle={`${filtered.length} of ${students.length} records`}
        action={<div className="flex gap-2">
          <button onClick={() => { setImportOpen(true); setImportReport(null) }} className={btnSecondary}>Import CSV</button>
          <button onClick={() => setEditing({})} className={btnPrimary}>Add student</button>
        </div>}
      />
      <Card className="p-3 mb-4 flex flex-wrap gap-2">
        <input className={inputCls} style={{ maxWidth: 260 }} placeholder="Search name or ID..." value={query} onChange={(e) => { setQuery(e.target.value); setPage(0) }} />
        <select className={inputCls} style={{ maxWidth: 200 }} value={classFilter} onChange={(e) => { setClassFilter(e.target.value); setPage(0) }}>
          <option value="">All classes</option>
          {classes.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
        </select>
        <label className="text-sm text-ink-700 flex items-center gap-1">
          <input type="checkbox" checked={showInactive} onChange={(e) => setShowInactive(e.target.checked)} /> show inactive
        </label>
      </Card>
      <Card>
        {pageRows.length === 0 ? <EmptyState title="No students match" subtitle="Adjust filters or add records." /> : (
          <table className="w-full text-sm">
            <thead><tr className="text-left text-ink-600 text-xs border-b">
              <th className="p-3">Name</th><th>Student ID</th><th>Class</th><th>Status</th><th>Activated</th><th className="text-right pr-3">Actions</th>
            </tr></thead>
            <tbody>
              {pageRows.map((s) => (
                <tr key={s.id} className="border-b border-ink-200 last:border-0">
                  <td className="p-3 font-medium">{s.first_name} {s.last_name}</td>
                  <td className="font-mono text-xs">{s.student_id_no}</td>
                  <td>{s.class_name ?? 'â€”'}</td>
                  <td><StatusBadge value={s.is_active ? 'active' : 'suspended'} /></td>
                  <td>{s.user_id ? 'Yes' : 'No'}</td>
                  <td className="text-right pr-3 whitespace-nowrap">
                    <button onClick={() => setEditing(s)} className="text-brand-600 text-xs mr-2 hover:underline">Edit</button>
                    <button onClick={() => issueCode(s)} className="text-brand-600 text-xs mr-2 hover:underline">Issue code</button>
                    <button onClick={() => toggleActive(s)} className="text-xs text-ink-700 hover:underline">{s.is_active ? 'Deactivate' : 'Reactivate'}</button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
        <div className="flex justify-between items-center p-3 text-sm">
          <span className="text-ink-600">Page {page + 1} of {Math.max(1, Math.ceil(filtered.length / PAGE_SIZE))}</span>
          <div className="flex gap-2">
            <button disabled={page === 0} onClick={() => setPage(page - 1)} className={btnSecondary}>Prev</button>
            <button disabled={(page + 1) * PAGE_SIZE >= filtered.length} onClick={() => setPage(page + 1)} className={btnSecondary}>Next</button>
          </div>
        </div>
      </Card>

      {editing && (
        <Modal title={editing.id ? 'Edit student' : 'Add student'} onClose={() => setEditing(null)}>
          <div className="space-y-3">
            <div className="grid grid-cols-2 gap-3">
              <input className={inputCls} placeholder="First name *" value={editing.first_name ?? ''} onChange={(e) => setEditing({ ...editing, first_name: e.target.value })} />
              <input className={inputCls} placeholder="Last name *" value={editing.last_name ?? ''} onChange={(e) => setEditing({ ...editing, last_name: e.target.value })} />
            </div>
            {!editing.id && <input className={inputCls} placeholder="Student ID *" value={editing.student_id_no ?? ''} onChange={(e) => setEditing({ ...editing, student_id_no: e.target.value })} />}
            <select className={inputCls} value={editing.class_id ?? ''} onChange={(e) => setEditing({ ...editing, class_id: e.target.value || undefined })}>
              <option value="">{editing.id ? 'Keep current class' : 'No class yet'}</option>
              {classes.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
            </select>
            <div className="flex justify-end gap-2 pt-2">
              <button onClick={() => setEditing(null)} className={btnSecondary}>Cancel</button>
              <button onClick={save} className={btnPrimary}>Save</button>
            </div>
          </div>
        </Modal>
      )}

      {importOpen && (
        <Modal title="Import student roster (CSV)" wide onClose={() => setImportOpen(false)}>
          <p className="text-xs text-ink-600 mb-2">Columns: first_name,last_name,student_id_no,class_grade,class_section,date_of_birth,gender</p>
          <button onClick={() => setImportText(STUDENT_CSV_TEMPLATE)} className="text-xs text-brand-600 hover:underline mb-2">Load template</button>
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

      {issuedCode && (
        <Modal title="Activation code (show once)" onClose={() => setIssuedCode(null)}>
          <p className="text-sm text-ink-700">For <b>{issuedCode.name}</b>. Share securely; it expires {new Date(issuedCode.expires).toLocaleDateString()}.</p>
          <p className="font-mono text-2xl font-bold tracking-widest text-center my-4">{issuedCode.code}</p>
          <p className="text-xs text-red-600">This code will not be shown again. A new code can be issued if lost.</p>
        </Modal>
      )}
    </div>
  )
}
