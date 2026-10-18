'use client'

import { useEffect, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { logAudit } from '@/lib/audit'
import { PageHeader, Card, StatusBadge, LoadingState, ErrorState, Modal, inputCls, btnPrimary, btnSecondary, useToast, EmptyState } from '@/components/ui'

interface ReviewCase {
  id: string
  status: string
  reason_code: string | null
  reviewer_notes: string | null
  created_at: string
  moderation_results?: { verdict: string; categories: Record<string, number>; provider: string; provider_error: string | null; message_id: string | null; attachment_id: string | null } | null
  message_body?: string | null
  sender_name?: string | null
}

// Moderation queue: flagged text + quarantined attachments with authorized
// review actions. Every decision writes to real records + audit trail.
// Private message bodies stay inside this restricted queue (never on dashboards).
export default function ModerationPage() {
  const [cases, setCases] = useState<ReviewCase[]>([])
  const [tab, setTab] = useState<'queue' | 'attachments'>('queue')
  const [attachments, setAttachments] = useState<{ id: string; file_name: string; status: string; storage_path: string; created_at: string; previewUrl?: string }[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [selected, setSelected] = useState<ReviewCase | null>(null)
  const [note, setNote] = useState('')
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
      const { data: c, error: cErr } = await supabase
        .from('moderation_review_cases')
        .select('id, status, reason_code, reviewer_notes, created_at, moderation_results(verdict, categories, provider, provider_error, message_id, attachment_id)')
        .eq('school_id', sid)
        .in('status', ['pending', 'under_review', 'escalated'])
        .order('created_at', { ascending: false })
        .limit(100)
      if (cErr) throw cErr
      const enriched: ReviewCase[] = []
      for (const row of (((c ?? []) as unknown) as (Omit<ReviewCase, 'message_body' | 'sender_name'> & { moderation_results: ReviewCase['moderation_results'] })[])) {
        let body: string | null = null
        let sender: string | null = null
        const mid = row.moderation_results?.message_id
        if (mid) {
          const { data: m } = await supabase.from('messages').select('body, sender_id').eq('id', mid).maybeSingle()
          if (m) {
            body = (m as { body: string | null }).body
            const { data: p } = await supabase.from('user_profiles').select('display_name').eq('id', (m as { sender_id: string }).sender_id).maybeSingle()
            sender = (p as { display_name: string } | null)?.display_name ?? null
          }
        }
        enriched.push({ ...row, message_body: body, sender_name: sender })
      }
      setCases(enriched)
      const { data: att } = await supabase.from('attachments')
        .select('id, file_name, status, storage_path, created_at')
        .eq('school_id', sid).in('status', ['pending_scan', 'quarantined']).order('created_at', { ascending: false }).limit(50)
      setAttachments(((att ?? []) as typeof attachments))
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load queue.')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { load() }, [])

  async function decide(action: 'approve' | 'reject' | 'escalate', closeCase = true) {
    if (!selected) return
    try {
      const supabase = createClient()
      const mid = selected.moderation_results?.message_id
      if (action === 'approve' && mid) {
        const { error } = await supabase.from('messages').update({ status: 'approved' }).eq('id', mid)
        if (error) throw error
      }
      if (action === 'reject' && mid) {
        const { error } = await supabase.from('messages').update({ status: 'blocked', is_deleted: true }).eq('id', mid)
        if (error) throw error
      }
      if (action === 'escalate') {
        const { data: inc, error } = await supabase.from('safeguarding_incidents').insert({
          school_id: schoolId, review_case_id: selected.id,
          title: `Escalated: ${selected.reason_code ?? 'moderation case'}`,
          description: note || null, severity: 'high', status: 'open', assigned_to: userId,
        }).select('id').single()
        if (error) throw error
        await supabase.from('moderation_review_cases').update({ status: 'escalated', reviewer_notes: note || null }).eq('id', selected.id)
        await logAudit(supabase, userId!, { schoolId, action: 'moderation.escalate', targetType: 'incident', targetId: (inc as { id: string }).id, outcome: 'success' })
        show(true, 'Escalated to a safeguarding incident.')
      } else {
        const { error } = await supabase.from('moderation_review_cases').update({
          status: closeCase ? 'closed' : 'under_review',
          reviewer_notes: note || null,
          disposition: action,
          closed_at: closeCase ? new Date().toISOString() : null,
          closed_by: closeCase ? userId : null,
        }).eq('id', selected.id)
        if (error) throw error
        await logAudit(supabase, userId!, { schoolId, action: `moderation.${action}`, targetType: 'review_case', targetId: selected.id, outcome: 'success', reason: note || undefined })
        show(true, action === 'approve' ? 'Message approved.' : 'Message blocked and removed.')
      }
      setSelected(null)
      setNote('')
      load()
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'Review action failed.')
    }
  }

  async function decideAttachment(id: string, approve: boolean) {
    try {
      const supabase = createClient()
      const { error } = await supabase.from('attachments')
        .update({ status: approve ? 'approved' : 'rejected', scanned_at: new Date().toISOString() })
        .eq('id', id)
      if (error) throw error
      await logAudit(supabase, userId!, { schoolId, action: approve ? 'attachment.approve' : 'attachment.reject', targetType: 'attachment', targetId: id, outcome: 'success' })
      show(true, approve ? 'Attachment approved.' : 'Attachment rejected.')
      load()
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'Attachment decision failed.')
    }
  }

  async function preview(path: string, id: string) {
    try {
      const supabase = createClient()
      const { data } = await supabase.storage.from('attachments').createSignedUrl(path, 120)
      if (data?.signedUrl) {
        setAttachments((prev) => prev.map((a) => (a.id === id ? { ...a, previewUrl: data.signedUrl } : a)))
      }
    } catch {
      show(false, 'Could not generate a preview link.')
    }
  }

  if (loading) return <LoadingState />
  if (error) return <ErrorState message={error} onRetry={load} />

  return (
    <div>
      {node}
      <PageHeader title="Moderation" subtitle="Flagged messages and attachments awaiting human review" />
      <div className="flex gap-2 mb-4">
        <button onClick={() => setTab('queue')} className={tab === 'queue' ? btnPrimary : btnSecondary}>Message queue ({cases.length})</button>
        <button onClick={() => setTab('attachments')} className={tab === 'attachments' ? btnPrimary : btnSecondary}>Attachments ({attachments.length})</button>
      </div>
      {tab === 'queue' ? (
        <Card>
          {cases.length === 0 ? <EmptyState title="Queue is clear" subtitle="Flagged content will appear here." /> : (
            <table className="w-full text-sm">
              <thead><tr className="text-left text-ink-600 text-xs border-b">
                <th className="p-3">Flagged content</th><th>Verdict</th><th>Status</th><th className="text-right pr-3">Review</th>
              </tr></thead>
              <tbody>
                {cases.map((c) => (
                  <tr key={c.id} className="border-b border-ink-200 last:border-0">
                    <td className="p-3 max-w-md">
                      <p className="truncate">{c.message_body ?? '(attachment case)'}</p>
                      <p className="text-xs text-ink-600">{c.sender_name ?? ''} Â· {c.reason_code} Â· {new Date(c.created_at).toLocaleString()}</p>
                    </td>
                    <td><StatusBadge value={c.moderation_results?.verdict ?? 'held'} /></td>
                    <td><StatusBadge value={c.status} /></td>
                    <td className="text-right pr-3"><button onClick={() => { setSelected(c); setNote('') }} className="text-brand-600 text-xs hover:underline">Open</button></td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </Card>
      ) : (
        <Card>
          {attachments.length === 0 ? <EmptyState title="No attachments pending" /> : (
            <table className="w-full text-sm">
              <thead><tr className="text-left text-ink-600 text-xs border-b">
                <th className="p-3">File</th><th>Status</th><th>Preview</th><th className="text-right pr-3">Decision</th>
              </tr></thead>
              <tbody>
                {attachments.map((a) => (
                  <tr key={a.id} className="border-b border-ink-200 last:border-0">
                    <td className="p-3">{a.file_name}</td>
                    <td><StatusBadge value={a.status} /></td>
                    <td>
                      {a.previewUrl
                        ? <a href={a.previewUrl} target="_blank" rel="noreferrer" className="text-brand-600 text-xs hover:underline">Open signed link (2 min)</a>
                        : <button onClick={() => preview(a.storage_path, a.id)} className="text-brand-600 text-xs hover:underline">Generate preview</button>}
                    </td>
                    <td className="text-right pr-3 whitespace-nowrap">
                      <button onClick={() => decideAttachment(a.id, true)} className="text-green-700 text-xs mr-2 hover:underline">Approve</button>
                      <button onClick={() => decideAttachment(a.id, false)} className="text-red-700 text-xs hover:underline">Reject</button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </Card>
      )}
      {selected && (
        <Modal title="Review case" wide onClose={() => setSelected(null)}>
          <div className="bg-ink-50 rounded-lg p-3 text-sm mb-3">
            <p className="font-medium">{selected.sender_name ?? 'Unknown sender'}</p>
            <p className="mt-1">{selected.message_body ?? '(no text â€” attachment case)'}</p>
            <p className="text-xs text-ink-600 mt-2">
              Provider: {selected.moderation_results?.provider ?? 'â€”'} Â·
              Scores: {JSON.stringify(selected.moderation_results?.categories ?? {})}
              {selected.moderation_results?.provider_error && ` Â· Error: ${selected.moderation_results.provider_error}`}
            </p>
          </div>
          <textarea className={inputCls} rows={3} placeholder="Reviewer notes / reason code..." value={note} onChange={(e) => setNote(e.target.value)} />
          <div className="flex justify-end gap-2 mt-3 flex-wrap">
            <button onClick={() => decide('approve')} className={btnPrimary}>Approve</button>
            <button onClick={() => decide('reject')} className="px-4 py-2 bg-red-600 text-white text-sm rounded-lg hover:bg-red-500">Block & remove</button>
            <button onClick={() => decide('escalate')} className="px-4 py-2 bg-purple-600 text-white text-sm rounded-lg hover:bg-purple-500">Escalate to incident</button>
          </div>
        </Modal>
      )}
    </div>
  )
}
