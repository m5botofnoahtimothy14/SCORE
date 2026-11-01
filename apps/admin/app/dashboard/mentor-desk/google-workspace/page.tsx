'use client'

import { useEffect, useState } from 'react'
import { CalendarDays, ExternalLink, RefreshCw, ShieldCheck } from 'lucide-react'
import { createClient } from '@/lib/supabase/client'

type WorkspaceConfig = {
  organizer_email: string | null
  calendar_id: string
  time_zone: string
  is_enabled: boolean
  updated_at: string
}

const ERROR_LABELS: Record<string, string> = {
  google_oauth_not_configured: 'Google OAuth is not configured on the server.',
  google_consent_declined: 'Google Workspace access was not approved.',
  invalid_oauth_callback: 'The Google sign-in response was incomplete.',
  invalid_oauth_state: 'The connection request expired. Start again.',
  google_token_exchange_failed: 'Google could not complete the account connection.',
  google_refresh_token_missing: 'Google did not return offline access. Reconnect and approve the request.',
  google_identity_check_failed: 'SCORE+ could not verify the Google account.',
  google_email_not_verified: 'Use a verified Google Workspace account.',
  workspace_credentials_not_saved: 'SCORE+ could not save the Workspace connection.',
  google_oauth_callback_failed: 'The Google Workspace connection failed. Try again.',
}

export default function GoogleWorkspacePage() {
  const [schoolId, setSchoolId] = useState('')
  const [schoolName, setSchoolName] = useState('')
  const [config, setConfig] = useState<WorkspaceConfig | null>(null)
  const [calendarId, setCalendarId] = useState('primary')
  const [timeZone, setTimeZone] = useState('Asia/Kolkata')
  const [loading, setLoading] = useState(true)
  const [connecting, setConnecting] = useState(false)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)

  async function load() {
    setLoading(true)
    setError(null)
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('Sign in with a school administrator account.')
      const { data: membership, error: membershipError } = await supabase
        .from('school_memberships')
        .select('school_id, schools(name)')
        .eq('user_id', user.id)
        .eq('is_active', true)
        .in('role', ['platform_owner', 'school_admin', 'principal'])
        .order('joined_at', { ascending: false })
        .limit(1)
        .maybeSingle()
      if (membershipError || !membership) throw new Error('School administrator access is required.')
      const id = membership.school_id as string
      const rawSchool = membership.schools as unknown
      const school = Array.isArray(rawSchool) ? rawSchool[0] : rawSchool
      setSchoolId(id)
      setSchoolName((school as { name?: string } | null)?.name ?? 'Your school')
      const { data, error: configError } = await supabase
        .from('google_meet_config')
        .select('organizer_email, calendar_id, time_zone, is_enabled, updated_at')
        .eq('school_id', id)
        .maybeSingle()
      if (configError) throw configError
      const row = data as WorkspaceConfig | null
      setConfig(row)
      if (row) {
        setCalendarId(row.calendar_id || 'primary')
        setTimeZone(row.time_zone || 'Asia/Kolkata')
      }
      const params = new URLSearchParams(window.location.search)
      if (params.get('connected') === '1') setMessage('Google Workspace is connected. Review the calendar and time zone settings.')
      const callbackError = params.get('error')
      if (callbackError) setError(ERROR_LABELS[callbackError] ?? 'The Google Workspace connection failed.')
      if (params.has('connected') || callbackError) window.history.replaceState({}, '', window.location.pathname)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not load Workspace settings.')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { void load() }, [])

  async function connect() {
    if (!schoolId) return
    setConnecting(true)
    setError(null)
    setMessage(null)
    try {
      const supabase = createClient()
      const { data, error: invokeError } = await supabase.functions.invoke('google-workspace-oauth', {
        body: { action: 'start', school_id: schoolId },
      })
      if (invokeError) throw invokeError
      if (!data?.authorization_url) throw new Error('The server did not return a Google sign-in link.')
      window.location.assign(data.authorization_url)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not start Google Workspace connection.')
      setConnecting(false)
    }
  }

  async function saveSettings(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!schoolId || !config?.is_enabled) return
    setSaving(true)
    setError(null)
    setMessage(null)
    try {
      const supabase = createClient()
      const { error: updateError } = await supabase
        .from('google_meet_config')
        .update({
          calendar_id: calendarId.trim() || 'primary',
          time_zone: timeZone.trim(),
          updated_at: new Date().toISOString(),
        })
        .eq('school_id', schoolId)
      if (updateError) throw updateError
      setMessage('Workspace settings saved.')
      await load()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not save Workspace settings.')
    } finally {
      setSaving(false)
    }
  }

  if (loading) return <div className="rounded-2xl border border-border bg-card p-8 text-sm text-muted-foreground">Loading Google Workspace settings…</div>

  return (
    <div className="space-y-6">
      <header className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.16em] text-brand-600">Mentor Desk / Integrations</p>
          <h1 className="mt-2 text-2xl font-bold tracking-tight text-ink-950">Google Workspace</h1>
          <p className="mt-1 max-w-2xl text-sm text-ink-600">Connect your school's Workspace account. SCORE+ will create protected Meet sessions for confirmed bookings.</p>
        </div>
        <button onClick={() => void load()} className="inline-flex items-center justify-center gap-2 rounded-xl border border-border px-4 py-2 text-sm font-semibold text-ink-700 hover:bg-muted">
          <RefreshCw className="h-4 w-4" /> Refresh
        </button>
      </header>

      {error && <div role="alert" className="rounded-xl border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-800">{error}</div>}
      {message && <div role="status" className="rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-800">{message}</div>}

      <section className="overflow-hidden rounded-2xl border border-border bg-card shadow-sm">
        <div className="flex items-start gap-4 border-b border-border p-5 sm:p-6">
          <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-2xl bg-brand-50 text-brand-700"><CalendarDays className="h-6 w-6" /></div>
          <div className="min-w-0 flex-1">
            <h2 className="font-semibold text-ink-950">{schoolName}</h2>
            <p className="mt-1 text-sm text-ink-600">School meeting provider</p>
          </div>
          <span className={config?.is_enabled ? 'rounded-full bg-emerald-50 px-3 py-1 text-xs font-semibold text-emerald-700' : 'rounded-full bg-amber-50 px-3 py-1 text-xs font-semibold text-amber-700'}>
            {config?.is_enabled ? 'Connected' : 'Not connected'}
          </span>
        </div>

        <div className="space-y-5 p-5 sm:p-6">
          <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <p className="text-sm font-semibold text-ink-900">{config?.organizer_email ?? 'No Workspace account connected'}</p>
              <p className="mt-1 text-xs text-ink-500">OAuth credentials are stored in Supabase Vault. SCORE+ does not show or return refresh tokens.</p>
            </div>
            <button onClick={() => void connect()} disabled={connecting} className="inline-flex items-center justify-center gap-2 rounded-xl bg-brand-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-brand-700 disabled:cursor-not-allowed disabled:opacity-60">
              <ShieldCheck className="h-4 w-4" /> {connecting ? 'Connecting…' : config?.is_enabled ? 'Reconnect Workspace' : 'Connect Google Workspace'}
              <ExternalLink className="h-3.5 w-3.5" />
            </button>
          </div>

          <form onSubmit={saveSettings} className="grid gap-4 border-t border-border pt-5 sm:grid-cols-2">
            <label className="block text-sm font-medium text-ink-800">
              Calendar ID
              <input value={calendarId} onChange={(e) => setCalendarId(e.target.value)} disabled={!config?.is_enabled} placeholder="primary" className="mt-2 w-full rounded-xl border border-border bg-background px-3 py-2.5 text-sm outline-none focus:border-brand-500 disabled:opacity-50" />
              <span className="mt-1 block text-xs font-normal text-ink-500">Use primary or a school calendar shared with the connected account.</span>
            </label>
            <label className="block text-sm font-medium text-ink-800">
              Time zone
              <input value={timeZone} onChange={(e) => setTimeZone(e.target.value)} disabled={!config?.is_enabled} placeholder="Asia/Kolkata" className="mt-2 w-full rounded-xl border border-border bg-background px-3 py-2.5 text-sm outline-none focus:border-brand-500 disabled:opacity-50" />
              <span className="mt-1 block text-xs font-normal text-ink-500">Use an IANA time zone, for example Asia/Kolkata or Asia/Dubai.</span>
            </label>
            <div className="sm:col-span-2">
              <button type="submit" disabled={!config?.is_enabled || saving} className="rounded-xl border border-border px-4 py-2.5 text-sm font-semibold text-ink-700 hover:bg-muted disabled:cursor-not-allowed disabled:opacity-50">
                {saving ? 'Saving…' : 'Save Workspace settings'}
              </button>
            </div>
          </form>
        </div>
      </section>

      <section className="rounded-2xl border border-border bg-muted/40 p-5 sm:p-6">
        <h2 className="text-sm font-semibold text-ink-950">How session access works</h2>
        <ol className="mt-3 list-decimal space-y-2 pl-5 text-sm leading-6 text-ink-600">
          <li>The assigned teacher confirms a 15- or 30-minute booking.</li>
          <li>SCORE+ checks the booking, school, teacher School ID, and teacher Workspace email.</li>
          <li>SCORE+ creates a restricted Meet space and assigns the teacher as co-host.</li>
          <li>The student sees the link in the session screen. The student does not need a Google account.</li>
          <li>The teacher admits the student from the Meet waiting room. The existing session OTP controls closure.</li>
        </ol>
      </section>
    </div>
  )
}
