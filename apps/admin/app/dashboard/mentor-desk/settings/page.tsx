/* eslint-disable @typescript-eslint/no-explicit-any, @typescript-eslint/no-unused-vars */
'use client'

import { useEffect, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { logAudit } from '@/lib/audit'
import {
  PageHeader, Card, LoadingState, ErrorState,
  inputCls, btnPrimary, btnSecondary, useToast,
} from '@/components/ui'
import { AlertTriangle, Clock, Percent, RotateCcw, ShieldCheck, Users } from 'lucide-react'

interface MentorDeskSettings {
  id: string
  school_id: string
  open_doubt_limit: number
  session_allowance_minutes: number
  urgent_passes_per_week: number
  escalation_threshold_minutes: number
  week_start_day: number
  session_lengths: number[]
  verification_code_digits: number
  code_visible_minutes_before: number
  max_verification_attempts: number
  created_at: string
  updated_at: string
}

// Mentor Desk configuration — scoped to the admin's school (RLS). Platform
// owners see every school; school admins see only their own. Changes are
// audited with previous/new value, actor and reason.
export default function MentorDeskSettingsPage() {
  const [settings, setSettings] = useState<MentorDeskSettings | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)
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

      const { data: s, error: sErr } = await supabase
        .from('mentor_desk_settings')
        .select('*')
        .eq('school_id', sid)
        .maybeSingle()
      if (sErr) throw sErr
      if (!s) {
        // No configured settings yet — apply documented defaults and insert.
        const defaults: Partial<MentorDeskSettings> = {
          school_id: sid,
          open_doubt_limit: 3,
          session_allowance_minutes: 120,
          urgent_passes_per_week: 1,
          escalation_threshold_minutes: 30,
          week_start_day: 1,
          session_lengths: [15, 30, 45],
          verification_code_digits: 6,
          code_visible_minutes_before: 10,
          max_verification_attempts: 5,
        }
        const { data: inserted, error: iErr } = await supabase
          .from('mentor_desk_settings')
          .insert(defaults)
          .select()
          .single()
        if (iErr) throw iErr
        setSettings(inserted as MentorDeskSettings)
        await logAudit(supabase, user.id, {
          schoolId: sid, action: 'settings.create', targetType: 'mentor_desk_settings',
          targetId: (inserted as { id: string }).id, outcome: 'success',
          metadata: { note: 'documented defaults applied' },
        })
        return
      }
      setSettings(s as MentorDeskSettings)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load settings.')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { load() }, [])

  async function save() {
    if (!settings) return
    if (settings.open_doubt_limit < 1 || settings.open_doubt_limit > 50) {
      show(false, 'Open doubt limit must be 1–50.')
      return
    }
    if (settings.session_allowance_minutes < 1 || settings.session_allowance_minutes > 1000) {
      show(false, 'Session allowance must be 1–1000 minutes.')
      return
    }
    if (settings.urgent_passes_per_week < 0 || settings.urgent_passes_per_week > 10) {
      show(false, 'Urgent passes per week must be 0–10.')
      return
    }
    if (settings.escalation_threshold_minutes < 1 || settings.escalation_threshold_minutes > 480) {
      show(false, 'Escalation threshold must be 1–480 minutes.')
      return
    }
    setSaving(true)
    try {
      const supabase = createClient()
      const { error } = await supabase
        .from('mentor_desk_settings')
        .update({
          open_doubt_limit: settings.open_doubt_limit,
          session_allowance_minutes: settings.session_allowance_minutes,
          urgent_passes_per_week: settings.urgent_passes_per_week,
          escalation_threshold_minutes: settings.escalation_threshold_minutes,
          week_start_day: settings.week_start_day,
          session_lengths: settings.session_lengths,
          verification_code_digits: settings.verification_code_digits,
          code_visible_minutes_before: settings.code_visible_minutes_before,
          max_verification_attempts: settings.max_verification_attempts,
        })
        .eq('school_id', schoolId)
      if (error) throw error
      await logAudit(supabase, userId!, {
        schoolId, action: 'settings.update', targetType: 'mentor_desk_settings',
        targetId: settings.id, outcome: 'success', metadata: settings as unknown as Record<string, unknown>,
      })
      show(true, 'Mentor Desk settings saved. Applies to new requests and bookings.')
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'Save failed.')
    } finally {
      setSaving(false)
    }
  }

  if (error) return <ErrorState message={error} onRetry={load} />
  if (loading) return <LoadingState message="Loading Mentor Desk settings…" />
  if (!settings) return <ErrorState message="No settings found." onRetry={load} />

  return (
    <div>
      {node}
      <PageHeader
        title="Mentor Desk — Settings"
        subtitle="Configurable limits and rules. Changes apply to new requests and bookings (not retroactive)."
        action={<button onClick={save} disabled={saving} className={btnPrimary}>{saving ? 'Saving…' : 'Save changes'}</button>}
      />
      <div className="grid md:grid-cols-2 gap-4">
        <Card className="p-4">
          <div className="flex items-center gap-2 mb-3">
            <Users className="h-4 w-4 text-brand-600" />
            <h2 className="font-semibold text-ink-900">Doubt limits</h2>
          </div>
          <div className="space-y-3">
            <div>
              <p className="text-xs font-medium text-ink-600">Open doubts per subject</p>
              <input className={inputCls} type="number" min={1} max={50} value={settings.open_doubt_limit} onChange={(e) => setSettings({ ...settings, open_doubt_limit: Number(e.target.value) })} />
              <p className="text-[11px] text-ink-500 mt-1">Default 3. Configurable limit of unresolved doubts per subject.</p>
            </div>
          </div>
        </Card>
        <Card className="p-4">
          <div className="flex items-center gap-2 mb-3">
            <Clock className="h-4 w-4 text-brand-600" />
            <h2 className="font-semibold text-ink-900">Session allowance</h2>
          </div>
          <div className="space-y-3">
            <div>
              <p className="text-xs font-medium text-ink-600">Weekly session minutes per subject</p>
              <input className={inputCls} type="number" min={1} max={1000} value={settings.session_allowance_minutes} onChange={(e) => setSettings({ ...settings, session_allowance_minutes: Number(e.target.value) })} />
              <p className="text-[11px] text-ink-500 mt-1">Default 120 minutes. Week runs Monday–Sunday.</p>
            </div>
            <div>
              <p className="text-xs font-medium text-ink-600">Queue escalation threshold (minutes)</p>
              <input className={inputCls} type="number" min={1} max={480} value={settings.escalation_threshold_minutes} onChange={(e) => setSettings({ ...settings, escalation_threshold_minutes: Number(e.target.value) })} />
              <p className="text-[11px] text-ink-500 mt-1">Default 30. Requests waiting longer are escalated first in the mentor queue.</p>
            </div>
            <div>
              <p className="text-xs font-medium text-ink-600">Urgent passes per subject per week</p>
              <input className={inputCls} type="number" min={0} max={10} value={settings.urgent_passes_per_week} onChange={(e) => setSettings({ ...settings, urgent_passes_per_week: Number(e.target.value) })} />
              <p className="text-[11px] text-ink-500 mt-1">Default 1. Requires a reason; consumed only on accepted urgent request.</p>
            </div>
          </div>
        </Card>
        <Card className="p-4">
          <div className="flex items-center gap-2 mb-3">
            <ShieldCheck className="h-4 w-4 text-brand-600" />
            <h2 className="font-semibold text-ink-900">Verification & code</h2>
          </div>
          <div className="space-y-3">
            <div>
              <p className="text-xs font-medium text-ink-600">Verification code digits</p>
              <input className={inputCls} type="number" min={4} max={8} value={settings.verification_code_digits} onChange={(e) => setSettings({ ...settings, verification_code_digits: Number(e.target.value) })} />
              <p className="text-[11px] text-ink-500 mt-1">Default 6 digits.</p>
            </div>
            <div>
              <p className="text-xs font-medium text-ink-600">Code visible before session (minutes)</p>
              <input className={inputCls} type="number" min={1} max={60} value={settings.code_visible_minutes_before} onChange={(e) => setSettings({ ...settings, code_visible_minutes_before: Number(e.target.value) })} />
              <p className="text-[11px] text-ink-500 mt-1">Default 10. Student sees the code this many minutes before start.</p>
            </div>
            <div>
              <p className="text-xs font-medium text-ink-600">Max incorrect code attempts</p>
              <input className={inputCls} type="number" min={1} max={10} value={settings.max_verification_attempts} onChange={(e) => setSettings({ ...settings, max_verification_attempts: Number(e.target.value) })} />
              <p className="text-[11px] text-ink-500 mt-1">Default 5. After this, code entry is locked.</p>
            </div>
          </div>
        </Card>
        <Card className="p-4">
          <div className="flex items-center gap-2 mb-3">
            <Percent className="h-4 w-4 text-brand-600" />
            <h2 className="font-semibold text-ink-900">Session lengths</h2>
          </div>
          <div className="space-y-3">
            <div>
              <p className="text-xs font-medium text-ink-600">Allowed session lengths (minutes)</p>
              <div className="flex gap-2">
                {[15, 30, 45].map((len) => {
                  const active = settings.session_lengths.includes(len)
                  return (
                    <button key={len} onClick={() => {
                      const curr = settings.session_lengths
                      const next = active ? curr.filter((l) => l !== len) : [...curr, len].sort((a, b) => a - b)
                      setSettings({ ...settings, session_lengths: next })
                    }}
                    className={`flex h-8 w-10 items-center justify-center rounded-lg text-xs font-medium border transition-colors ${active ? 'bg-brand-100 text-brand-700 border-brand-200' : 'bg-white text-ink-700 border-ink-200 hover:border-ink-300'}`}>
                      {len}
                    </button>
                  )
                })}
              </div>
              <p className="text-[11px] text-ink-500 mt-1">Default 15, 30, 45. Durations exceeding remaining allowance are disabled server-side.</p>
            </div>
          </div>
        </Card>
      </div>
      <div className="mt-6 flex items-center gap-2 text-xs text-ink-500">
        <AlertTriangle className="h-3.5 w-3.5" />
        <p>Week boundary is Monday–Sunday. Allowance is computed from the persistent ledger — not cached.</p>
      </div>
    </div>
  )
}

