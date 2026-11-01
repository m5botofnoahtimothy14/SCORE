'use client'

import { useEffect, useState } from 'react'
import { Activity, Bell, BrainCircuit, Database, RefreshCw, ShieldCheck } from 'lucide-react'
import { PageHeader, Card, StatusBadge, LoadingState, ErrorState } from '@/components/ui'

type HealthData = {
  db: { ok: boolean }
  tables: Record<string, { ok: boolean; error?: string }>
  providers: {
    fcmConfigured: boolean
    textModerationConfigured: boolean
    imageSafetyConfigured: boolean
    moderationPrimary: string | null
    imageSafetyPrimary: string | null
    aiInsightsConfigured: boolean
    smsConfigured: boolean
  }
  queues: {
    failedNotificationJobs: number
    retryableBackgroundJobs: number
    pendingModerationCases: boolean
  }
  activity: { lastMessageAt: string | null }
  version: string
  latencyMs: number
}

export default function HealthPage() {
  const [data, setData] = useState<HealthData | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)

  async function load() {
    setLoading(true)
    setError(null)
    try {
      const response = await fetch('/api/health', { cache: 'no-store' })
      const result = await response.json()
      if (!response.ok) throw new Error(result.error === 'unauthorized' ? 'Sign in with an administrator account.' : result.error === 'forbidden' ? 'Your account does not have permission to view system health.' : result.detail ?? 'Health check failed.')
      setData(result as HealthData)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not load system health.')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { load() }, [])

  if (loading) return <LoadingState message="Checking system health…" />
  if (error) return <ErrorState message={error} onRetry={load} />
  if (!data) return <ErrorState message="No health data returned." onRetry={load} />

  const providers = [
    ['Push notifications', data.providers.fcmConfigured, 'FCM credentials'],
    ['Text moderation', data.providers.textModerationConfigured, data.providers.moderationPrimary ?? 'No provider'],
    ['Image safety', data.providers.imageSafetyConfigured, data.providers.imageSafetyPrimary ?? 'No provider'],
    ['AI insights', data.providers.aiInsightsConfigured, 'AI provider credentials'],
    ['SMS delivery', data.providers.smsConfigured, 'SMS provider credentials'],
  ] as const

  return (
    <div>
      <PageHeader
        title="System health"
        subtitle="Live configuration checks. Secrets are never shown."
        action={<button onClick={load} className="btn-secondary"><RefreshCw className="h-4 w-4" /> Refresh</button>}
      />
      <div className="mb-5 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Card className="p-5"><Database className="mb-3 h-5 w-5 text-brand-600" /><p className="text-2xl font-bold text-ink-950">{data.db.ok ? 'Healthy' : 'Attention'}</p><p className="mt-1 text-xs text-ink-500">Database checks</p></Card>
        <Card className="p-5"><Activity className="mb-3 h-5 w-5 text-brand-600" /><p className="text-2xl font-bold text-ink-950">{data.latencyMs} ms</p><p className="mt-1 text-xs text-ink-500">Health endpoint latency</p></Card>
        <Card className="p-5"><Bell className="mb-3 h-5 w-5 text-brand-600" /><p className="text-2xl font-bold text-ink-950">{data.queues.failedNotificationJobs}</p><p className="mt-1 text-xs text-ink-500">Failed notification jobs</p></Card>
        <Card className="p-5"><BrainCircuit className="mb-3 h-5 w-5 text-brand-600" /><p className="text-2xl font-bold text-ink-950">{data.queues.retryableBackgroundJobs}</p><p className="mt-1 text-xs text-ink-500">Retryable background jobs</p></Card>
      </div>

      <div className="grid gap-5 lg:grid-cols-2">
        <Card>
          <div className="flex items-center gap-3 border-b border-ink-200/70 px-5 py-4"><ShieldCheck className="h-5 w-5 text-brand-600" /><h2 className="text-sm font-semibold text-ink-900">Provider configuration</h2></div>
          <div className="divide-y divide-ink-100 px-5">
            {providers.map(([name, configured, detail]) => (
              <div key={name} className="flex items-center justify-between gap-4 py-4">
                <div><p className="text-sm font-medium text-ink-800">{name}</p><p className="mt-1 text-xs text-ink-500">{detail}</p></div>
                <StatusBadge value={configured ? 'configured' : 'not_configured'} />
              </div>
            ))}
          </div>
        </Card>
        <Card>
          <div className="border-b border-ink-200/70 px-5 py-4"><h2 className="text-sm font-semibold text-ink-900">Database table checks</h2><p className="mt-1 text-xs text-ink-500">Version {data.version}</p></div>
          <div className="max-h-[420px] divide-y divide-ink-100 overflow-y-auto px-5">
            {Object.entries(data.tables).map(([name, status]) => (
              <div key={name} className="flex items-center justify-between gap-4 py-3"><span className="font-mono text-xs text-ink-600">{name}</span><StatusBadge value={status.ok ? 'available' : 'error'} /></div>
            ))}
          </div>
        </Card>
      </div>
      <p className="mt-4 text-xs text-ink-500">The health endpoint reports database reachability and configuration visible to the admin web runtime. Supabase Edge Function secrets are stored separately and are validated when those functions run. This page does not prove that every application workflow is operational.</p>
    </div>
  )
}
