'use client'

import { useEffect, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { logAudit } from '@/lib/audit'
import { PageHeader, Card, StatusBadge, LoadingState, ErrorState, Modal, inputCls, btnPrimary, btnSecondary, useToast, EmptyState } from '@/components/ui'

interface Incident {
  id: string
  title: string
  description: string | null
  severity: string
  status: string
  assigned_to: string | null
  created_at: string
  investigation_notes?: string | null
}

// Safeguarding incidents + investigation requests/approvals. Sensitive
// content stays in this restricted area; access is audited.
export default function IncidentsPage() {
  const [incidents, setIncidents] = useState<Incident[]>([])
  const [requests, setRequests] = useState<{ id: string; purpose: string; status: string; scope_description: string; access_expires_at: string | null; created_at: string }[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [selected, setSelected] = useState<Incident | null>(null)
  const [notes, setNotes] = useState('')
  const [severity, setSeverity] = useState('medium')
  const [status, setStatus] = useState('open')
  const [newReq, setNewReq] = useState<{ incident_id: string; purpose: string; scope: string; legal: string } | null>(null)
  const [schoolId, setSchoolId] = useState<string | null>(null)
  const [userId, setUserId] = useState<string | null>(null)
  const [isOwner, setIsOwner] = useState(false)
  const { show, node } = useToast()

  async function load() {
    setLoading(true)
    setError(null)
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('Not signed in.')
      setUserId(user.id)
      const { data: membership } = await supabase.from('school_memberships').select('school_id, role')
        .eq('user_id', user.id).eq('is_active', true).limit(1).maybeSingle()
      const sid = (membership as { school_id: string } | null)?.school_id
      if (!sid) throw new Error('No school scope.')
      setSchoolId(sid)
      setIsOwner((membership as { role: string } | null)?.role === 'platform_owner')
      const [{ data: inc, error: iErr }, { data: req }] = await Promise.all([
        supabase.from('safeguarding_incidents').select('*').eq('school_id', sid).order('created_at', { ascending: false }).limit(100),
        supabase.from('investigation_requests').select('id, purpose, status, scope_description, access_expires_at, created_at').eq('school_id', sid).order('created_at', { ascending: false }).limit(50),
      ])
      if (iErr) throw iErr
      setIncidents((inc ?? []) as Incident[])
      setRequests((req ?? []) as typeof requests)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load incidents.')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { load() }, [])

  async function saveIncident() {
    if (!selected) return
    try {
      const supabase = createClient()
      const { error } = await supabase.from('safeguarding_incidents').update({
        investigation_notes: notes || null, severity, status,
        resolved_at: status === 'resolved' || status === 'closed' ? new Date().toISOString() : null,
      }).eq('id', selected.id)
      if (error) throw error
      await logAudit(supabase, userId!, { schoolId, action: 'incident.update', targetType: 'incident', targetId: selected.id, outcome: 'success', metadata: { severity, status } })
      show(true, 'Incident updated.')
      setSelected(null)
      load()
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'Update failed.')
    }
  }

  async function createRequest() {
    if (!newReq?.purpose.trim() || !newReq?.scope.trim()) {
      show(false, 'Purpose and scope are required.')
      return
    }
    try {
      const supabase = createClient()
      const { data, error } = await supabase.from('investigation_requests').insert({
        school_id: schoolId, incident_id: newReq.incident_id || null,
        requested_by: userId, purpose: newReq.purpose.trim(),
        legal_authorization: newReq.legal || null, scope_description: newReq.scope.trim(), status: 'requested',
      }).select('id').single()
      if (error) throw error
      await logAudit(supabase, userId!, { schoolId, action: 'investigation.request', targetType: 'investigation', targetId: (data as { id: string }).id, outcome: 'success' })
      show(true, 'Investigation requested. Platform approval is required before access.')
      setNewReq(null)
      load()
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'Request failed.')
    }
  }

  async function decideRequest(id: string, approve: boolean) {
    try {
      const supabase = createClient()
      const { error } = await supabase.from('investigation_requests').update({
        status: approve ? 'approved' : 'revoked',
        approved_by: userId,
        approved_at: new Date().toISOString(),
        access_expires_at: approve ? new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString() : null,
      }).eq('id', id)
      if (error) throw error
      await supabase.from('investigation_approvals').insert({ request_id: id, approver_id: userId, decision: approve ? 'approved' : 'rejected' })
      await logAudit(supabase, userId!, { schoolId, action: approve ? 'investigation.approve' : 'investigation.reject', targetType: 'investigation', targetId: id, outcome: 'success' })
      show(true, approve ? 'Access approved for 24 hours.' : 'Request rejected.')
      load()
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'Decision failed.')
    }
  }

  if (loading) return <LoadingState />
  if (error) return <ErrorState message={error} onRetry={load} />

  return (
    <div>
      {node}
      <PageHeader
        title="Safeguarding & Investigations"
        subtitle="Restricted to authorized reviewers. All access is audited."
        action={<button onClick={() => setNewReq({ incident_id: '', purpose: '', scope: '', legal: '' })} className={btnPrimary}>New investigation request</button>}
      />
      <Card className="mb-4">
        <h2 className="font-semibold p-4 pb-0">Incidents</h2>
        {incidents.length === 0 ? <EmptyState title="No incidents" /> : (
          <table className="w-full text-sm">
            <thead><tr className="text-left text-ink-600 text-xs border-b">
              <th className="p-3">Title</th><th>Severity</th><th>Status</th><th>Opened</th><th className="text-right pr-3">Open</th>
            </tr></thead>
            <tbody>
              {incidents.map((i) => (
                <tr key={i.id} className="border-b border-ink-200 last:border-0">
                  <td className="p-3 font-medium">{i.title}</td>
                  <td><StatusBadge value={i.severity} /></td>
                  <td><StatusBadge value={i.status} /></td>
                  <td className="text-xs text-ink-600">{new Date(i.created_at).toLocaleString()}</td>
                  <td className="text-right pr-3">
                    <button onClick={() => { setSelected(i); setNotes(i.investigation_notes ?? ''); setSeverity(i.severity); setStatus(i.status) }} className="text-brand-600 text-xs hover:underline">Open</button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </Card>
      <Card>
        <h2 className="font-semibold p-4 pb-0">Investigation requests</h2>
        {requests.length === 0 ? <EmptyState title="No requests" subtitle="Time-limited, approval-gated access only." /> : (
          <table className="w-full text-sm">
            <thead><tr className="text-left text-ink-600 text-xs border-b">
              <th className="p-3">Purpose</th><th>Scope</th><th>Status</th><th>Expires</th><th className="text-right pr-3">Decision</th>
            </tr></thead>
            <tbody>
              {requests.map((r) => (
                <tr key={r.id} className="border-b border-ink-200 last:border-0">
                  <td className="p-3 max-w-xs truncate">{r.purpose}</td>
                  <td className="text-xs max-w-xs truncate">{r.scope_description}</td>
                  <td><StatusBadge value={r.status} /></td>
                  <td className="text-xs">{r.access_expires_at ? new Date(r.access_expires_at).toLocaleString() : '—'}</td>
                  <td className="text-right pr-3">
                    {isOwner && r.status === 'requested' ? (
                      <>
                        <button onClick={() => decideRequest(r.id, true)} className="text-green-700 text-xs mr-2 hover:underline">Approve 24h</button>
                        <button onClick={() => decideRequest(r.id, false)} className="text-red-700 text-xs hover:underline">Reject</button>
                      </>
                    ) : <span className="text-xs text-ink-500">platform owner decides</span>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </Card>
      {selected && (
        <Modal title={selected.title} wide onClose={() => setSelected(null)}>
          {selected.description && <p className="text-sm text-ink-700 mb-3">{selected.description}</p>}
          <label className="text-xs text-ink-600">Investigation notes (restricted)</label>
          <textarea className={`${inputCls} mb-3`} rows={4} value={notes} onChange={(e) => setNotes(e.target.value)} />
          <div className="grid grid-cols-2 gap-2 mb-3">
            <select className={inputCls} value={severity} onChange={(e) => setSeverity(e.target.value)}>
              <option value="low">Low</option><option value="medium">Medium</option>
              <option value="high">High</option><option value="critical">Critical</option>
            </select>
            <select className={inputCls} value={status} onChange={(e) => setStatus(e.target.value)}>
              <option value="open">Open</option><option value="investigating">Investigating</option>
              <option value="escalated_external">Escalated external</option><option value="resolved">Resolved</option>
              <option value="closed">Closed</option>
            </select>
          </div>
          <div className="flex justify-end gap-2">
            <button onClick={() => setSelected(null)} className={btnSecondary}>Cancel</button>
            <button onClick={saveIncident} className={btnPrimary}>Save</button>
          </div>
        </Modal>
      )}
      {newReq && (
        <Modal title="Request investigation access" wide onClose={() => setNewReq(null)}>
          <div className="space-y-3">
            <input className={inputCls} placeholder="Purpose *" value={newReq.purpose} onChange={(e) => setNewReq({ ...newReq, purpose: e.target.value })} />
            <textarea className={inputCls} rows={3} placeholder="Scope: exactly what data is needed, and why * " value={newReq.scope} onChange={(e) => setNewReq({ ...newReq, scope: e.target.value })} />
            <input className={inputCls} placeholder="Legal authorization (if any)" value={newReq.legal} onChange={(e) => setNewReq({ ...newReq, legal: e.target.value })} />
            <p className="text-xs text-yellow-700 bg-yellow-50 border border-yellow-200 rounded-lg p-2">
              Access is granted only after platform approval, is time-limited, and every access event is recorded.
            </p>
            <div className="flex justify-end gap-2">
              <button onClick={() => setNewReq(null)} className={btnSecondary}>Cancel</button>
              <button onClick={createRequest} className={btnPrimary}>Submit request</button>
            </div>
          </div>
        </Modal>
      )}
    </div>
  )
}
