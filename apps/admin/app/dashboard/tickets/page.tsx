'use client'

import { useEffect, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { logAudit } from '@/lib/audit'
import { PageHeader, Card, StatusBadge, LoadingState, ErrorState, Modal, inputCls, btnPrimary, btnSecondary, useToast, EmptyState } from '@/components/ui'

interface Ticket {
  id: string
  category: string
  subject: string
  description: string
  status: string
  created_at: string
  submitted_by: string
}

// Support tickets: school-level operational issues. Assign + resolve with
// real status transitions.
export default function TicketsPage() {
  const [tickets, setTickets] = useState<Ticket[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [creating, setCreating] = useState(false)
  const [form, setForm] = useState({ category: 'technical', subject: '', description: '' })
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
      const { data: membership } = await supabase.from('school_memberships').select('school_id')
        .eq('user_id', user.id).eq('is_active', true).limit(1).maybeSingle()
      const sid = (membership as { school_id: string } | null)?.school_id
      if (!sid) throw new Error('No school scope.')
      setSchoolId(sid)
      const { data, error } = await supabase.from('support_tickets').select('*').eq('school_id', sid).order('created_at', { ascending: false }).limit(100)
      if (error) throw error
      setTickets((data ?? []) as Ticket[])
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load tickets.')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { load() }, [])

  async function create() {
    if (!form.subject.trim() || !form.description.trim()) {
      show(false, 'Subject and description are required.')
      return
    }
    try {
      const supabase = createClient()
      const { data, error } = await supabase.from('support_tickets').insert({
        school_id: schoolId, submitted_by: userId, category: form.category,
        subject: form.subject.trim(), description: form.description.trim(),
      }).select('id').single()
      if (error) throw error
      await logAudit(supabase, userId!, { schoolId, action: 'ticket.create', targetType: 'ticket', targetId: (data as { id: string }).id, outcome: 'success' })
      show(true, 'Ticket submitted.')
      setCreating(false)
      setForm({ category: 'technical', subject: '', description: '' })
      load()
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'Submit failed.')
    }
  }

  async function setStatus(t: Ticket, status: string) {
    try {
      const supabase = createClient()
      const { error } = await supabase.from('support_tickets').update({
        status, resolved_at: status === 'resolved' || status === 'closed' ? new Date().toISOString() : null,
      }).eq('id', t.id)
      if (error) throw error
      await logAudit(supabase, userId!, { schoolId, action: `ticket.${status}`, targetType: 'ticket', targetId: t.id, outcome: 'success' })
      show(true, `Ticket marked ${status}.`)
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
      <PageHeader title="Support" subtitle="Operational issues and requests" action={<button onClick={() => setCreating(true)} className={btnPrimary}>New ticket</button>} />
      <Card>
        {tickets.length === 0 ? <EmptyState title="No tickets" /> : (
          <table className="w-full text-sm">
            <thead><tr className="text-left text-gray-500 text-xs border-b">
              <th className="p-3">Subject</th><th>Category</th><th>Status</th><th>Opened</th><th className="text-right pr-3">Actions</th>
            </tr></thead>
            <tbody>
              {tickets.map((t) => (
                <tr key={t.id} className="border-b border-gray-100 last:border-0">
                  <td className="p-3"><p className="font-medium">{t.subject}</p><p className="text-xs text-gray-500 max-w-md truncate">{t.description}</p></td>
                  <td className="text-xs">{t.category}</td>
                  <td><StatusBadge value={t.status} /></td>
                  <td className="text-xs text-gray-500">{new Date(t.created_at).toLocaleString()}</td>
                  <td className="text-right pr-3 whitespace-nowrap">
                    {t.status === 'open' && <button onClick={() => setStatus(t, 'in_progress')} className="text-blue-600 text-xs mr-2 hover:underline">Start</button>}
                    {['open', 'in_progress'].includes(t.status) && <button onClick={() => setStatus(t, 'resolved')} className="text-green-700 text-xs mr-2 hover:underline">Resolve</button>}
                    {t.status !== 'closed' && <button onClick={() => setStatus(t, 'closed')} className="text-xs text-gray-600 hover:underline">Close</button>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </Card>
      {creating && (
        <Modal title="New support ticket" onClose={() => setCreating(false)}>
          <div className="space-y-3">
            <select className={inputCls} value={form.category} onChange={(e) => setForm({ ...form, category: e.target.value })}>
              <option value="technical">Technical</option><option value="roster">Roster / enrollment</option>
              <option value="moderation">Moderation</option><option value="billing">Billing / plan</option>
              <option value="other">Other</option>
            </select>
            <input className={inputCls} placeholder="Subject *" value={form.subject} onChange={(e) => setForm({ ...form, subject: e.target.value })} />
            <textarea className={inputCls} rows={4} placeholder="Describe the issue *" value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} />
            <div className="flex justify-end gap-2">
              <button onClick={() => setCreating(false)} className={btnSecondary}>Cancel</button>
              <button onClick={create} className={btnPrimary}>Submit</button>
            </div>
          </div>
        </Modal>
      )}
    </div>
  )
}
