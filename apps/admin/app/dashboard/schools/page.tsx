'use client'

import { useEffect, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { logAudit } from '@/lib/audit'
import { PageHeader, Card, StatusBadge, LoadingState, ErrorState, Modal, inputCls, btnPrimary, btnSecondary, useToast, EmptyState } from '@/components/ui'

interface School {
  id: string
  name: string
  code: string
  city: string | null
  state: string | null
  country: string
  phone: string | null
  email: string | null
  is_active: boolean
}

// Platform owners manage all schools; school admins see their own school
// read-only (edits to their own record still audited).
export default function SchoolsPage() {
  const [schools, setSchools] = useState<School[]>([])
  const [isOwner, setIsOwner] = useState(false)
  const [mySchoolId, setMySchoolId] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [editing, setEditing] = useState<Partial<School> | null>(null)
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
        .select('role, school_id')
        .eq('user_id', user.id)
        .eq('is_active', true)
        .in('role', ['platform_owner', 'school_admin', 'principal'])
        .limit(1)
        .maybeSingle()
      const role = (membership as { role: string } | null)?.role
      setIsOwner(role === 'platform_owner')
      setMySchoolId((membership as { school_id: string } | null)?.school_id ?? null)
      const { data, error } = role === 'platform_owner'
        ? await supabase.from('schools').select('*').order('name')
        : await supabase.from('schools').select('*').eq('id', (membership as { school_id: string }).school_id)
      if (error) throw error
      setSchools((data ?? []) as School[])
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load schools.')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { load() }, [])

  async function save() {
    if (!editing?.name?.trim() || !editing?.code?.trim()) {
      show(false, 'Name and code are required.')
      return
    }
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (editing.id) {
        const { error } = await supabase.from('schools').update({
          name: editing.name.trim(),
          city: editing.city || null,
          state: editing.state || null,
          phone: editing.phone || null,
          email: editing.email || null,
        }).eq('id', editing.id)
        if (error) throw error
        await logAudit(supabase, user!.id, { schoolId: editing.id, action: 'school.update', targetType: 'school', targetId: editing.id, outcome: 'success' })
        show(true, 'School updated.')
      } else {
        const { data, error } = await supabase.from('schools').insert({
          name: editing.name.trim(),
          code: editing.code.trim().toUpperCase(),
          city: editing.city || null,
          state: editing.state || null,
          country: 'India',
          phone: editing.phone || null,
          email: editing.email || null,
        }).select('id').single()
        if (error) throw error
        await supabase.from('school_settings').insert({ school_id: (data as { id: string }).id })
        await logAudit(supabase, user!.id, { schoolId: (data as { id: string }).id, action: 'school.create', targetType: 'school', targetId: (data as { id: string }).id, outcome: 'success' })
        show(true, 'School created.')
      }
      setEditing(null)
      load()
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'Save failed (code must be unique).')
    }
  }

  async function toggleActive(s: School) {
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      const { error } = await supabase.from('schools').update({ is_active: !s.is_active }).eq('id', s.id)
      if (error) throw error
      await logAudit(supabase, user!.id, {
        schoolId: s.id,
        action: s.is_active ? 'school.suspend' : 'school.reactivate',
        targetType: 'school', targetId: s.id, outcome: 'success',
        reason: 'Changed from Schools page',
      })
      show(true, s.is_active ? 'School suspended.' : 'School reactivated.')
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
        title="Schools"
        subtitle={isOwner ? 'All institutions on the platform' : 'Your institution'}
        action={isOwner ? <button onClick={() => setEditing({})} className={btnPrimary}>New school</button> : undefined}
      />
      {schools.length === 0 ? (
        <Card><EmptyState title="No schools found" /></Card>
      ) : (
        <div className="grid gap-4">
          {schools.map((s) => (
            <Card key={s.id} className="p-4 flex items-center justify-between">
              <div>
                <p className="font-semibold text-gray-900">{s.name} <span className="text-gray-400 font-mono text-xs">{s.code}</span></p>
                <p className="text-xs text-gray-500">{[s.city, s.state].filter(Boolean).join(', ') || '—'} · {s.email || 'no email'}</p>
                <div className="mt-1"><StatusBadge value={s.is_active ? 'active' : 'suspended'} /></div>
              </div>
              <div className="flex gap-2">
                <button onClick={() => setEditing(s)} className={btnSecondary}>Edit</button>
                {isOwner && s.id !== mySchoolId && (
                  <button onClick={() => toggleActive(s)} className={btnSecondary}>
                    {s.is_active ? 'Suspend' : 'Reactivate'}
                  </button>
                )}
              </div>
            </Card>
          ))}
        </div>
      )}
      {editing && (
        <Modal title={editing.id ? 'Edit school' : 'New school'} onClose={() => setEditing(null)}>
          <div className="space-y-3">
            <input className={inputCls} placeholder="School name *" value={editing.name ?? ''} onChange={(e) => setEditing({ ...editing, name: e.target.value })} />
            {!editing.id && <input className={inputCls} placeholder="Unique code, e.g. DPSN *" value={editing.code ?? ''} onChange={(e) => setEditing({ ...editing, code: e.target.value.toUpperCase() })} />}
            <div className="grid grid-cols-2 gap-3">
              <input className={inputCls} placeholder="City" value={editing.city ?? ''} onChange={(e) => setEditing({ ...editing, city: e.target.value })} />
              <input className={inputCls} placeholder="State" value={editing.state ?? ''} onChange={(e) => setEditing({ ...editing, state: e.target.value })} />
            </div>
            <input className={inputCls} placeholder="Phone" value={editing.phone ?? ''} onChange={(e) => setEditing({ ...editing, phone: e.target.value })} />
            <input className={inputCls} placeholder="Email" value={editing.email ?? ''} onChange={(e) => setEditing({ ...editing, email: e.target.value })} />
            <div className="flex justify-end gap-2 pt-2">
              <button onClick={() => setEditing(null)} className={btnSecondary}>Cancel</button>
              <button onClick={save} className={btnPrimary}>Save</button>
            </div>
          </div>
        </Modal>
      )}
    </div>
  )
}
