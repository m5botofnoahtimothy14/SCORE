'use client'

import { useEffect, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import {
  PageHeader, Card, StatusBadge, LoadingState, ErrorState, Modal, EmptyState, useToast,
  inputCls, btnPrimary, btnSecondary,
} from '@/components/ui'

interface AdminRow {
  id: string
  user_id: string
  role: string
  is_active: boolean
  school_id: string
  school_name: string
  school_code: string
  display_name: string
  email: string
}

interface School {
  id: string
  name: string
  code: string
}

const roleLabel = (r: string) => (r === 'platform_owner' ? 'Super Admin' : r === 'principal' ? 'Principal' : 'Admin')

const emptyForm = { email: '', password: '', display_name: '', school_id: '', role: 'school_admin' }

// Super Admin only — manage school IT-head "Admin" accounts.
export function AdminsClient() {
  const [admins, setAdmins] = useState<AdminRow[]>([])
  const [schools, setSchools] = useState<School[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [open, setOpen] = useState(false)
  const [form, setForm] = useState(emptyForm)
  const { show, node } = useToast()

  async function load() {
    setLoading(true)
    setError(null)
    try {
      const res = await fetch('/api/admins')
      const json = await res.json()
      if (!res.ok) throw new Error(json.error ?? 'Failed to load administrators.')
      setAdmins((json.admins ?? []) as AdminRow[])

      const supabase = createClient()
      const { data } = await supabase.from('schools').select('id, name, code').order('name')
      setSchools((data ?? []) as School[])
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load administrators.')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { load() }, [])

  function openCreate() {
    setForm({ ...emptyForm, school_id: schools[0]?.id ?? '' })
    setOpen(true)
  }

  async function create() {
    if (!form.email || form.password.length < 8 || !form.school_id) {
      show(false, 'Email, a password (8+ chars) and a school are required.')
      return
    }
    try {
      const res = await fetch('/api/admins', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(form),
      })
      const json = await res.json()
      if (!res.ok) throw new Error(json.error ?? 'Create failed.')
      show(true, 'Admin account created.')
      setOpen(false)
      load()
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'Create failed.')
    }
  }

  async function toggle(row: AdminRow) {
    try {
      const res = await fetch('/api/admins', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ id: row.id, is_active: !row.is_active }),
      })
      const json = await res.json()
      if (!res.ok) throw new Error(json.error ?? 'Update failed.')
      show(true, row.is_active ? 'Admin deactivated.' : 'Admin reactivated.')
      load()
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'Update failed.')
    }
  }

  if (loading) return <LoadingState />
  if (error) return <ErrorState message={error} onRetry={load} />

  return (
    <div>
      {node}
      <PageHeader
        title="Administrators"
        subtitle="Create and manage each school's Admin (IT head). Super Admin only."
        action={<button onClick={openCreate} className={btnPrimary}>New admin</button>}
      />

      <Card>
        {admins.length === 0 ? (
          <EmptyState title="No administrators yet" subtitle="Create the first school Admin account." />
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left text-gray-500 border-b border-gray-100">
                <th className="px-4 py-3 font-medium">Name</th>
                <th className="px-4 py-3 font-medium">Email</th>
                <th className="px-4 py-3 font-medium">Role</th>
                <th className="px-4 py-3 font-medium">School</th>
                <th className="px-4 py-3 font-medium">Status</th>
                <th className="px-4 py-3" />
              </tr>
            </thead>
            <tbody>
              {admins.map((a) => (
                <tr key={a.id} className="border-b border-gray-50 last:border-0">
                  <td className="px-4 py-3 text-gray-900">
                    {a.display_name || '—'}
                    {a.role === 'platform_owner' && (
                      <span className="ml-2 text-[10px] uppercase tracking-wide text-blue-600 bg-blue-50 px-1.5 py-0.5 rounded">You · Owner</span>
                    )}
                  </td>
                  <td className="px-4 py-3 text-gray-600">{a.email}</td>
                  <td className="px-4 py-3">{roleLabel(a.role)}</td>
                  <td className="px-4 py-3 text-gray-600">
                    {a.school_name} <span className="text-gray-400 font-mono text-xs">{a.school_code}</span>
                  </td>
                  <td className="px-4 py-3"><StatusBadge value={a.is_active ? 'active' : 'suspended'} /></td>
                  <td className="px-4 py-3 text-right">
                    {a.role !== 'platform_owner' && (
                      <button onClick={() => toggle(a)} className={btnSecondary}>
                        {a.is_active ? 'Deactivate' : 'Reactivate'}
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </Card>

      {open && (
        <Modal title="New admin account" onClose={() => setOpen(false)}>
          <div className="space-y-3">
            <input className={inputCls} placeholder="Full name" value={form.display_name} onChange={(e) => setForm({ ...form, display_name: e.target.value })} />
            <input className={inputCls} type="email" placeholder="Email *" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} />
            <input className={inputCls} type="password" placeholder="Temporary password (8+ chars) *" value={form.password} onChange={(e) => setForm({ ...form, password: e.target.value })} />
            <select className={inputCls} value={form.school_id} onChange={(e) => setForm({ ...form, school_id: e.target.value })}>
              <option value="">Select school…</option>
              {schools.map((s) => (
                <option key={s.id} value={s.id}>{s.name} ({s.code})</option>
              ))}
            </select>
            <select className={inputCls} value={form.role} onChange={(e) => setForm({ ...form, role: e.target.value })}>
              <option value="school_admin">Admin — School IT Head</option>
              <option value="principal">Principal</option>
            </select>
            <p className="text-xs text-gray-500">
              This person signs in to the DMS with this email and password, scoped to their school.
            </p>
            <div className="flex justify-end gap-2 pt-2">
              <button onClick={() => setOpen(false)} className={btnSecondary}>Cancel</button>
              <button onClick={create} className={btnPrimary}>Create admin</button>
            </div>
          </div>
        </Modal>
      )}
    </div>
  )
}
