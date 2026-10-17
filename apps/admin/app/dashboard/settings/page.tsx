'use client'

import { useEffect, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { logAudit } from '@/lib/audit'
import { PageHeader, Card, LoadingState, ErrorState, inputCls, btnPrimary, useToast } from '@/components/ui'

interface Settings {
  allow_student_id_only_login: boolean
  require_activation_code: boolean
  otp_provider: string
  moderation_provider: string
  image_safety_provider: string
  max_file_size_mb: number
  retention_days: number
  timezone: string
}

// School policy configuration. Sensitive changes are audited; the
// ID-only-login toggle carries an explicit impersonation-risk warning.
export default function SettingsPage() {
  const [settings, setSettings] = useState<Settings | null>(null)
  const [retention, setRetention] = useState<{ data_type: string; retention_days: number }[]>([])
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
      const { data: membership } = await supabase.from('school_memberships').select('school_id')
        .eq('user_id', user.id).eq('is_active', true).limit(1).maybeSingle()
      const sid = (membership as { school_id: string } | null)?.school_id
      if (!sid) throw new Error('No school scope.')
      setSchoolId(sid)
      const [{ data: s, error: sErr }, { data: r }] = await Promise.all([
        supabase.from('school_settings').select('*').eq('school_id', sid).maybeSingle(),
        supabase.from('data_retention_policies').select('data_type, retention_days').eq('school_id', sid),
      ])
      if (sErr) throw sErr
      if (!s) throw new Error('School settings not found. Contact platform support.')
      setSettings(s as Settings)
      setRetention((r ?? []) as typeof retention)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load settings.')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { load() }, [])

  async function save() {
    if (!settings) return
    if (settings.max_file_size_mb < 1 || settings.max_file_size_mb > 15) {
      show(false, 'Max file size must be 1–15 MB (bucket limit).')
      return
    }
    setSaving(true)
    try {
      const supabase = createClient()
      const { error } = await supabase.from('school_settings').update({ ...settings }).eq('school_id', schoolId)
      if (error) throw error
      await logAudit(supabase, userId!, { schoolId, action: 'settings.update', targetType: 'school_settings', outcome: 'success', metadata: settings as unknown as Record<string, unknown> })
      show(true, 'Settings saved.')
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'Save failed.')
    } finally {
      setSaving(false)
    }
  }

  if (loading) return <LoadingState />
  if (error) return <ErrorState message={error} onRetry={load} />
  if (!settings) return <ErrorState message="No settings found." onRetry={load} />

  return (
    <div>
      {node}
      <PageHeader title="Settings" subtitle="School policy, providers and retention" action={<button onClick={save} disabled={saving} className={btnPrimary}>{saving ? 'Saving...' : 'Save changes'}</button>} />
      <div className="grid md:grid-cols-2 gap-4">
        <Card className="p-4">
          <h2 className="font-semibold mb-3">Enrollment & authentication</h2>
          <label className="flex items-start gap-2 text-sm mb-1">
            <input type="checkbox" className="mt-1" checked={settings.require_activation_code} onChange={(e) => setSettings({ ...settings, require_activation_code: e.target.checked })} />
            Require activation code for students (recommended)
          </label>
          <label className="flex items-start gap-2 text-sm">
            <input type="checkbox" className="mt-1" checked={settings.allow_student_id_only_login} onChange={(e) => setSettings({ ...settings, allow_student_id_only_login: e.target.checked })} />
            Allow ID-only login (weak — higher impersonation risk)
          </label>
          {settings.allow_student_id_only_login && (
            <p className="text-xs text-red-700 bg-red-50 border border-red-200 rounded-lg p-2 mt-2">
              Warning: a name + school ID alone is not a strong secret. Enabling ID-only login raises
              impersonation risk and is not recommended. Prefer activation codes.
            </p>
          )}
          <label className="text-xs text-gray-500 block mt-3">OTP provider</label>
          <select className={inputCls} value={settings.otp_provider} onChange={(e) => setSettings({ ...settings, otp_provider: e.target.value })}>
            <option value="textbee">TextBee (Android gateway)</option>
          </select>
        </Card>
        <Card className="p-4">
          <h2 className="font-semibold mb-3">Moderation & safety</h2>
          <label className="text-xs text-gray-500">Text moderation provider</label>
          <select className={`${inputCls} mb-2`} value={settings.moderation_provider} onChange={(e) => setSettings({ ...settings, moderation_provider: e.target.value })}>
            <option value="openai">OpenAI Moderation</option>
            <option value="google">Google Cloud Natural Language</option>
          </select>
          <label className="text-xs text-gray-500">Image safety provider</label>
          <select className={inputCls} value={settings.image_safety_provider} onChange={(e) => setSettings({ ...settings, image_safety_provider: e.target.value })}>
            <option value="apilayer_nudity">APILayer Nudity Detection</option>
          </select>
          <p className="text-xs text-gray-500 mt-2">If a provider is unconfigured or fails, content is held/quarantined — never auto-approved.</p>
        </Card>
        <Card className="p-4">
          <h2 className="font-semibold mb-3">Limits</h2>
          <label className="text-xs text-gray-500">Max file size (MB, ≤ 15)</label>
          <input className={`${inputCls} mb-2`} type="number" min={1} max={15} value={settings.max_file_size_mb} onChange={(e) => setSettings({ ...settings, max_file_size_mb: Number(e.target.value) })} />
          <label className="text-xs text-gray-500">Default retention (days)</label>
          <input className={inputCls} type="number" min={30} value={settings.retention_days} onChange={(e) => setSettings({ ...settings, retention_days: Number(e.target.value) })} />
          <label className="text-xs text-gray-500 block mt-2">Timezone</label>
          <input className={inputCls} value={settings.timezone} onChange={(e) => setSettings({ ...settings, timezone: e.target.value })} />
        </Card>
        <Card className="p-4">
          <h2 className="font-semibold mb-3">Data retention by type</h2>
          {retention.map((r) => (
            <div key={r.data_type} className="flex items-center justify-between py-1.5 text-sm border-b border-gray-100 last:border-0">
              <span className="font-mono text-xs">{r.data_type}</span>
              <span>{r.retention_days} days</span>
            </div>
          ))}
          {retention.length === 0 && <p className="text-sm text-gray-500">No retention policies set.</p>}
        </Card>
      </div>
      <div className="flex justify-end mt-4">
        <button onClick={save} disabled={saving} className={btnPrimary}>{saving ? 'Saving...' : 'Save changes'}</button>
      </div>
    </div>
  )
}
