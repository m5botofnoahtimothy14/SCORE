'use client'

import { useEffect, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { PageHeader, Card, StatusBadge, LoadingState, ErrorState, Modal, inputCls, btnPrimary, useToast, EmptyState } from '@/components/ui'

interface Announcement {
  id: string
  title: string
  body: string
  category: string
  audience_type: string
  class_id: string | null
  requires_ack: boolean
  is_published: boolean
  published_at: string | null
  created_at: string
}

// Announcements: create via the publish-announcement edge function
// (server-side audience resolution + permission checks), ack tracking,
// delivery diagnostics from notification_jobs.
export default function AnnouncementsPage() {
  const [items, setItems] = useState<Announcement[]>([])
  const [classes, setClasses] = useState<{ id: string; name: string }[]>([])
  const [schoolId, setSchoolId] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [creating, setCreating] = useState(false)
  const [form, setForm] = useState({ title: '', body: '', category: 'general', audience_type: 'class', class_id: '', requires_ack: false })
  const [detail, setDetail] = useState<{ id: string; recipients: number; acked: number; sent: number; failed: number } | null>(null)
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
      const [{ data: a, error: aErr }, { data: c }] = await Promise.all([
        supabase.from('announcements').select('*').eq('school_id', sid).order('created_at', { ascending: false }).limit(100),
        supabase.from('classes').select('id, name').eq('school_id', sid).eq('is_active', true).order('name'),
      ])
      if (aErr) throw aErr
      setItems((a ?? []) as Announcement[])
      setClasses((c ?? []) as { id: string; name: string }[])
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load announcements.')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { load() }, [])

  async function publish() {
    if (!form.title.trim() || !form.body.trim()) {
      show(false, 'Title and body are required.')
      return
    }
    if (form.audience_type === 'class' && !form.class_id) {
      show(false, 'Select a class for class announcements.')
      return
    }
    setCreating(true)
    try {
      const supabase = createClient()
      const { data, error } = await supabase.functions.invoke('publish-announcement', {
        body: {
          school_id: schoolId, title: form.title.trim(), body: form.body.trim(),
          category: form.category, audience_type: form.audience_type,
          class_id: form.class_id || null, requires_ack: form.requires_ack,
        },
      })
      if (error) throw error
      if (!(data as { success?: boolean }).success) {
        throw new Error((data as { error?: string }).error ?? 'publish_failed')
      }
      show(true, `Published to ${(data as { recipient_count: number }).recipient_count} recipients.`)
      setForm({ title: '', body: '', category: 'general', audience_type: 'class', class_id: '', requires_ack: false })
      load()
    } catch (e) {
      show(false, e instanceof Error ? friendly(e.message) : 'Publish failed.')
    } finally {
      setCreating(false)
    }
  }

  function friendly(code: string) {
    switch (code) {
      case 'insufficient_permissions_for_audience': return 'Your role cannot publish to this audience.'
      case 'priority_alerts_require_admin': return 'Priority alerts require an administrator.'
      case 'not_assigned_to_class': return 'You are not assigned to that class.'
      default: return `Publish failed (${code}).`
    }
  }

  async function openDetail(a: Announcement) {
    try {
      const supabase = createClient()
      const [{ count: recipients }, { count: acked }, { data: jobs }] = await Promise.all([
        supabase.from('announcement_recipients').select('id', { count: 'exact', head: true }).eq('announcement_id', a.id),
        supabase.from('announcement_receipts').select('id', { count: 'exact', head: true }).eq('announcement_id', a.id).not('acknowledged_at', 'is', null),
        supabase.from('notification_jobs').select('status').eq('data->>announcement_id', a.id),
      ])
      const list = (jobs ?? []) as { status: string }[]
      setDetail({
        id: a.id,
        recipients: recipients ?? 0,
        acked: acked ?? 0,
        sent: list.filter((j) => j.status === 'sent').length,
        failed: list.filter((j) => j.status === 'failed').length,
      })
    } catch {
      show(false, 'Could not load delivery details.')
    }
  }

  if (loading) return <LoadingState />
  if (error) return <ErrorState message={error} onRetry={load} />

  return (
    <div>
      {node}
      <PageHeader title="Announcements" subtitle="Publish, track acknowledgement and delivery" />
      <Card className="p-4 mb-4">
        <h2 className="font-semibold mb-3">New announcement</h2>
        <input className={`${inputCls} mb-2`} placeholder="Title *" value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} />
        <textarea className={`${inputCls} mb-2`} rows={3} placeholder="Message body *" value={form.body} onChange={(e) => setForm({ ...form, body: e.target.value })} />
        <div className="grid md:grid-cols-3 gap-2 mb-2">
          <select className={inputCls} value={form.category} onChange={(e) => setForm({ ...form, category: e.target.value })}>
            <option value="general">General</option><option value="academic">Academic</option>
            <option value="event">Event</option><option value="safety">Safety</option>
            <option value="priority_alert">Priority alert (admin only)</option>
          </select>
          <select className={inputCls} value={form.audience_type} onChange={(e) => setForm({ ...form, audience_type: e.target.value })}>
            <option value="class">Class</option><option value="school_wide">Entire school (admin)</option>
            <option value="staff">Staff</option><option value="leadership">Leadership</option>
          </select>
          {form.audience_type === 'class' && (
            <select className={inputCls} value={form.class_id} onChange={(e) => setForm({ ...form, class_id: e.target.value })}>
              <option value="">Select class…</option>
              {classes.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
            </select>
          )}
        </div>
        <label className="text-sm flex items-center gap-2 mb-3">
          <input type="checkbox" checked={form.requires_ack} onChange={(e) => setForm({ ...form, requires_ack: e.target.checked })} />
          Require acknowledgement
        </label>
        <button onClick={publish} disabled={creating} className={btnPrimary}>{creating ? 'Publishing...' : 'Publish'}</button>
      </Card>
      <Card>
        {items.length === 0 ? <EmptyState title="No announcements yet" /> : (
          <table className="w-full text-sm">
            <thead><tr className="text-left text-gray-500 text-xs border-b">
              <th className="p-3">Title</th><th>Category</th><th>Audience</th><th>Published</th><th className="text-right pr-3">Details</th>
            </tr></thead>
            <tbody>
              {items.map((a) => (
                <tr key={a.id} className="border-b border-gray-100 last:border-0">
                  <td className="p-3 font-medium">{a.title}</td>
                  <td><StatusBadge value={a.category} /></td>
                  <td className="text-xs">{a.audience_type.replace('_', ' ')}</td>
                  <td className="text-xs text-gray-500">{a.published_at ? new Date(a.published_at).toLocaleString() : '—'}</td>
                  <td className="text-right pr-3"><button onClick={() => openDetail(a)} className="text-blue-600 text-xs hover:underline">Delivery & acks</button></td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </Card>
      {detail && (
        <Modal title="Delivery & acknowledgement" onClose={() => setDetail(null)}>
          <div className="grid grid-cols-2 gap-3 text-sm">
            <div className="bg-gray-50 rounded-lg p-3"><p className="text-gray-500 text-xs">Recipients</p><p className="text-xl font-bold">{detail.recipients}</p></div>
            <div className="bg-gray-50 rounded-lg p-3"><p className="text-gray-500 text-xs">Acknowledged</p><p className="text-xl font-bold">{detail.acked}</p></div>
            <div className="bg-gray-50 rounded-lg p-3"><p className="text-gray-500 text-xs">Notifications sent</p><p className="text-xl font-bold">{detail.sent}</p></div>
            <div className="bg-gray-50 rounded-lg p-3"><p className="text-gray-500 text-xs">Notifications failed</p><p className="text-xl font-bold">{detail.failed}</p></div>
          </div>
          <p className="text-xs text-gray-500 mt-3">Acknowledgement is recipient-confirmed. A sent notification alone never counts as read.</p>
        </Modal>
      )}
    </div>
  )
}
