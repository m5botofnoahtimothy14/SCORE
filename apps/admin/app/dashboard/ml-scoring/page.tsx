'use client'

import { useEffect, useState } from 'react'
import { RefreshCw, Sigma } from 'lucide-react'
import { createClient } from '@/lib/supabase/client'
import {
  PageHeader, Card, LoadingState, ErrorState, EmptyState, MetricTile,
  SectionHeader, btnSecondary, useToast,
} from '@/components/ui'

interface SchoolMetric {
  category: string
  audience: string
  tp: number
  fp: number
  fn: number
  tn: number
  precision: number
  recall: number
  f1: number
  support: number
}

interface Snapshot {
  id: string
  computed_at: string
  total_reviews: number
  total_predictions: number
  metrics: SchoolMetric[]
}

/**
 * ML / scoring dashboard for moderation.
 * Shows F1 / precision / recall per category per audience, computed by the
 * score-moderation edge function from moderation_results (predictions) vs
 * moderation_review_cases (human ground truth).
 */
export default function MlScoringPage() {
  const [snapshots, setSnapshots] = useState<Snapshot[]>([])
  const [latest, setLatest] = useState<Snapshot | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [scope, setScope] = useState<'school' | 'platform'>('school')
  const [isOwner, setIsOwner] = useState(false)
  const { show, node } = useToast()

  async function load(target: 'school' | 'platform' = scope) {
    setLoading(true)
    setError(null)
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('Not signed in.')

      const { data: membership } = await supabase
        .from('school_memberships')
        .select('school_id, role')
        .eq('user_id', user.id).eq('is_active', true).limit(1).maybeSingle()
      const m = membership as { school_id: string; role: string } | null
      if (!m) throw new Error('No school scope.')

      const owner = m.role === 'platform_owner'
      setIsOwner(owner)

      // Platform owners may review the whole platform; everyone else is
      // pinned to their own school (RLS enforces the same boundary).
      const effective: 'school' | 'platform' = owner && target === 'platform' ? 'platform' : 'school'

      let query = supabase
        .from('moderation_score_snapshots')
        .select('*')
        .order('computed_at', { ascending: false })
        .limit(50)
      if (effective === 'school') query = query.eq('school_id', m.school_id)

      const { data: s, error: sErr } = await query
      if (sErr) throw sErr
      setSnapshots(((s ?? []) as unknown) as Snapshot[])
      setLatest(s?.[0] ?? null)
      setScope(effective)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load ML scoring metrics.')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { load('school') }, [])

  function switchScope(next: 'school' | 'platform') {
    if (next === 'platform' && !isOwner) {
      show(false, 'Only a Super Admin can view platform-wide scoring.')
      return
    }
    load(next)
  }

  async function runScoring() {
    try {
      const res = await fetch('/api/ml-scoring/run', { method: 'POST' })
      const body = await res.json().catch(() => null)
      if (!res.ok) {
        throw new Error(body?.detail || body?.error || `Scoring failed (${res.status}).`)
      }
      const scored = body?.result?.schools_scored ?? 0
      show(true, scored > 0
        ? `Scoring complete — ${scored} school snapshot(s) written.`
        : 'Scoring complete — no reviewed content to score yet.')
      load(scope)
    } catch (e) {
      show(false, e instanceof Error ? e.message : 'Scoring failed.')
    }
  }

  if (loading) return <LoadingState message="Loading scoring metrics…" />
  if (error) return <ErrorState message={error} onRetry={() => load(scope)} />

  const latestMetrics = latest?.metrics ?? []

  // Aggregate summary across latest snapshot
  const avgF1 = latestMetrics.length > 0
    ? latestMetrics.reduce((a, m) => a + m.f1, 0) / latestMetrics.length
    : 0
  const totalTP = latestMetrics.reduce((a, m) => a + m.tp, 0)
  const totalFP = latestMetrics.reduce((a, m) => a + m.fp, 0)
  const totalFN = latestMetrics.reduce((a, m) => a + m.fn, 0)
  const totalSupport = latestMetrics.reduce((a, m) => a + m.support, 0)

  const precision = totalTP + totalFP > 0 ? (totalTP / (totalTP + totalFP)) * 100 : 0
  const recall = totalTP + totalFN > 0 ? (totalTP / (totalTP + totalFN)) * 100 : 0

  return (
    <div>
      {node}
      <PageHeader
        title="ML Scoring & Moderation Quality"
        subtitle="F1 / precision / recall per category per audience, computed from moderation verdicts vs human review."
        action={
          <div className="flex items-center gap-2">
            {isOwner && (
              <div className="flex rounded-xl bg-ink-100 p-1">
                {(['school', 'platform'] as const).map((s) => (
                  <button
                    key={s}
                    onClick={() => switchScope(s)}
                    className={[
                      'rounded-lg px-3 py-1.5 text-xs font-semibold capitalize transition-colors',
                      scope === s ? 'bg-white text-ink-900 shadow-soft' : 'text-ink-500 hover:text-ink-700',
                    ].join(' ')}
                  >
                    {s}
                  </button>
                ))}
              </div>
            )}
            <button onClick={runScoring} className={btnSecondary}>
              <Sigma className="mr-1.5 h-3.5 w-3.5" />
              Run scoring
            </button>
            <button onClick={() => load(scope)} className={btnSecondary}>
              <RefreshCw className="mr-1.5 h-3.5 w-3.5" />
              Refresh
            </button>
          </div>
        }
      />

      <div className="mb-6 grid grid-cols-2 gap-4 md:grid-cols-4">
        <MetricTile icon="CheckCircle2" label="Precision" value={latest ? `${precision.toFixed(1)}%` : '–'} accent={{ solid: '#1f47eb', soft: '#eef6ff', onSoft: '#1f47eb' }} />
        <MetricTile icon="Archive" label="Recall" value={latest ? `${recall.toFixed(1)}%` : '–'} accent={{ solid: '#1f47eb', soft: '#eef6ff', onSoft: '#1f47eb' }} />
        <MetricTile icon="BarChart" label="F1 Score" value={latest ? avgF1.toFixed(2) : '–'} accent={{ solid: '#0e9f6e', soft: '#eef9f5', onSoft: '#0e9f6e' }} />
        <MetricTile icon="ShieldCheck" label="Scored Predictions" value={latest?.total_predictions ?? 0} hint={latest ? `${totalSupport} scored across ${latestMetrics.length} categories` : undefined} accent={{ solid: '#1a56db', soft: '#eef6ff', onSoft: '#1a56db' }} />
      </div>

      <Card className="animate-fade-up">
        <div className="border-b border-ink-200/70 px-5 py-4">
          <SectionHeader
            title="Per-category scores (latest snapshot)"
            subtitle={latest?.computed_at ? new Date(latest.computed_at).toLocaleString() : 'No snapshot yet'}
          />
        </div>
        {latestMetrics.length === 0 ? (
          <EmptyState title="No scoring data yet" subtitle="Run the score-moderation edge function to compute F1 metrics from moderation results vs human review cases." />
        ) : (
          <div className="overflow-x-auto">
            <table className="data-table">
              <thead>
                <tr>
                  <th>Category</th><th className="w-32">Audience</th><th className="w-24">Precision</th><th className="w-24">Recall</th><th className="w-24">F1 Score</th><th className="w-32">Support</th>
                </tr>
              </thead>
              <tbody>
                {latestMetrics.map((m) => (
                  <tr key={`${m.category}|${m.audience}`} className="border-b border-ink-100 last:border-0">
                    <td className="p-3 font-medium text-ink-700">{m.category}</td>
                    <td className="p-3 text-xs text-ink-600">{m.audience}</td>
                    <td className="p-3 text-xs text-ink-700 font-mono">{m.precision.toFixed(2)}</td>
                    <td className="p-3 text-xs text-ink-700 font-mono">{m.recall.toFixed(2)}</td>
                    <td className="p-3 text-xs font-semibold">{m.f1.toFixed(2)}</td>
                    <td className="p-3 text-xs text-ink-600">{m.support}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      <Card className="animate-fade-up">
        <div className="border-b border-ink-200/70 px-5 py-4">
          <SectionHeader
            title="Snapshots history"
            subtitle="Each snapshot is one scoring run over moderation results vs review cases."
          />
        </div>
        {snapshots.length === 0 ? (
          <EmptyState title="No snapshots yet" subtitle="Snapshots are created each time the score-moderation edge function runs." />
        ) : (
          <div className="overflow-x-auto">
            <table className="data-table">
              <thead>
                <tr>
                  <th>Computed at</th><th className="w-32">Reviews</th><th className="w-32">Predictions</th><th className="w-32">Metrics</th>
                </tr>
              </thead>
              <tbody>
                {snapshots.map((s) => (
                  <tr key={s.id} className="border-b border-ink-100 last:border-0">
                    <td className="p-3 font-mono text-xs text-ink-700">{new Date(s.computed_at).toLocaleString()}</td>
                    <td className="p-3 text-xs text-ink-700">{s.total_reviews}</td>
                    <td className="p-3 text-xs text-ink-700">{s.total_predictions}</td>
                    <td className="p-3 text-xs text-ink-700">{s.metrics.length} categories</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      <Card className="animate-fade-up">
        <div className="border-b border-ink-200/70 px-5 py-4">
          <SectionHeader title="About the scoring" />
        </div>
        <div className="px-5 py-4 space-y-3">
          <p className="text-sm text-ink-700">
            The ML scoring layer compares model predictions (from the
            <b>moderate-message</b> / <b>moderate-image</b> edge functions)
            against human review outcomes (<b>moderation_review_cases</b>) to
            compute precision, recall, and F1 per moderation category per user
            role (student, teacher, leadership).
          </p>
          <p className="text-sm text-ink-700">
            <b>Precision</b> = TP / (TP + FP) &mdash; how often flagged content
            truly needed review. <b>Recall</b> = TP / (TP + FN) &mdash; how often
            the system caught content that needed review. <b>F1</b> is the
            harmonic mean of both.
          </p>
          <p className="text-sm text-ink-700">
            Unreviewed messages are excluded from scoring until a human
            administrator resolves them, so the metrics reflect ground truth,
            not guesses.
          </p>
        </div>
      </Card>
    </div>
  )
}
