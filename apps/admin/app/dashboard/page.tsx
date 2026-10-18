'use client'

import { useEffect, useState } from 'react'
import Link from 'next/link'
import {
  GraduationCap, Users, BookOpen, Megaphone, ShieldAlert,
  Siren, BellOff, ArrowUpRight, AlertTriangle,
} from 'lucide-react'
import { createClient } from '@/lib/supabase/client'
import { PageHeader, Card, StatusBadge, LoadingState, ErrorState } from '@/components/ui'

interface Overview {
  schoolName: string
  role: string
  students: number
  teachers: number
  classes: number
  pendingModeration: number
  openIncidents: number
  announcementsWeek: number
  failedNotifications: number
  recentAudit: { id: string; action: string; outcome: string; created_at: string }[]
  providers: { fcm: boolean; moderation: boolean; vision: boolean }
}

export default function OverviewPage() {
  const [data, setData] = useState<Overview | null>(null)
  const [error, setError] = useState<string | null>(null)

  async function load() {
    setError(null)
    try {
      const supabase = createClient()
      const {
        data: { user },
      } = await supabase.auth.getUser()
      if (!user) throw new Error('Not signed in.')
      const { data: membership } = await supabase
        .from('school_memberships')
        .select('role, school_id, schools(name)')
        .eq('user_id', user.id)
        .eq('is_active', true)
        .in('role', ['platform_owner', 'school_admin', 'principal'])
        .order('joined_at', { ascending: false })
        .limit(1)
        .maybeSingle()
      if (!membership) throw new Error('No administrator access.')
      const schoolId = (membership as { school_id: string }).school_id
      const m = membership as unknown as { role: string; schools: { name: string } }

      const weekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString()
      const [students, teachers, classes, pendingModeration, openIncidents, announcementsWeek, failedNotifications, recentAudit, healthRes] =
        await Promise.all([
          supabase.from('students').select('id', { count: 'exact', head: true }).eq('school_id', schoolId),
          supabase.from('teachers').select('id', { count: 'exact', head: true }).eq('school_id', schoolId),
          supabase.from('classes').select('id', { count: 'exact', head: true }).eq('school_id', schoolId),
          supabase.from('moderation_review_cases').select('id', { count: 'exact', head: true }).eq('school_id', schoolId).in('status', ['pending', 'under_review']),
          supabase.from('safeguarding_incidents').select('id', { count: 'exact', head: true }).eq('school_id', schoolId).in('status', ['open', 'investigating']),
          supabase.from('announcements').select('id', { count: 'exact', head: true }).eq('school_id', schoolId).gte('created_at', weekAgo),
          supabase.from('notification_jobs').select('id', { count: 'exact', head: true }).eq('school_id', schoolId).eq('status', 'failed'),
          supabase
            .from('audit_events')
            .select('id, action, outcome, created_at')
            .eq('school_id', schoolId)
            .order('created_at', { ascending: false })
            .limit(10),
          fetch('/api/health').then((r) => (r.ok ? r.json() : null)).catch(() => null),
        ])

      setData({
        schoolName: m.schools?.name ?? '',
        role: m.role,
        students: students.count ?? 0,
        teachers: teachers.count ?? 0,
        classes: classes.count ?? 0,
        pendingModeration: pendingModeration.count ?? 0,
        openIncidents: openIncidents.count ?? 0,
        announcementsWeek: announcementsWeek.count ?? 0,
        failedNotifications: failedNotifications.count ?? 0,
        recentAudit: ((recentAudit.data ?? []) as Overview['recentAudit']) ?? [],
        providers: {
          fcm: Boolean(healthRes?.providers?.fcmConfigured),
          moderation: Boolean(healthRes?.providers?.textModerationConfigured),
          vision: Boolean(healthRes?.providers?.imageSafetyConfigured),
        },
      })
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load overview.')
    }
  }

  useEffect(() => {
    load()
  }, [])

  if (error) return <ErrorState message={error} onRetry={load} />
  if (!data) return <LoadingState message="Loading overview…" />

  const stats = [
    { label: 'Students', value: data.students, href: '/dashboard/students', icon: GraduationCap, tone: 'brand' },
    { label: 'Teachers', value: data.teachers, href: '/dashboard/teachers', icon: Users, tone: 'brand' },
    { label: 'Classes', value: data.classes, href: '/dashboard/classes', icon: BookOpen, tone: 'brand' },
    { label: 'Notices (7d)', value: data.announcementsWeek, href: '/dashboard/announcements', icon: Megaphone, tone: 'brand' },
    { label: 'Pending moderation', value: data.pendingModeration, href: '/dashboard/moderation', icon: ShieldAlert, tone: 'amber' },
    { label: 'Open incidents', value: data.openIncidents, href: '/dashboard/incidents', icon: Siren, tone: 'rose' },
    { label: 'Failed notifications', value: data.failedNotifications, href: '/dashboard/notifications', icon: BellOff, tone: 'rose' },
  ] as const

  const tones: Record<string, { chip: string; icon: string }> = {
    brand: { chip: 'from-brand-500/12 to-brand-500/0', icon: 'text-brand-500 bg-brand-50' },
    amber: { chip: 'from-amber-500/14 to-amber-500/0', icon: 'text-amber-600 bg-amber-50' },
    rose: { chip: 'from-rose-500/14 to-rose-500/0', icon: 'text-rose-500 bg-rose-50' },
  }

  return (
    <div>
      <PageHeader title={data.schoolName} subtitle={`Signed in as ${data.role.replace(/_/g, ' ')}`} />

      {(!data.providers.fcm || !data.providers.moderation || !data.providers.vision) && (
        <div className="mb-6 flex animate-fade-up items-start gap-3 rounded-2xl border border-amber-200/80 bg-gradient-to-b from-amber-50 to-amber-50/40 p-4 shadow-soft">
          <AlertTriangle className="mt-0.5 h-5 w-5 shrink-0 text-amber-500" />
          <p className="text-sm text-amber-900">
            <span className="font-semibold">Provider configuration incomplete: </span>
            {[
              !data.providers.fcm && 'FCM (push notifications disabled)',
              !data.providers.moderation && 'text moderation (messages held for review)',
              !data.providers.vision && 'image safety (uploads quarantined)',
            ]
              .filter(Boolean)
              .join(' · ')}
            . See{' '}
            <Link href="/dashboard/health" className="font-medium underline underline-offset-2">
              System Health
            </Link>{' '}
            for setup.
          </p>
        </div>
      )}

      <div className="mb-6 grid grid-cols-2 gap-4 md:grid-cols-4">
        {stats.map((s, i) => {
          const t = tones[s.tone]
          return (
            <Link
              key={s.label}
              href={s.href}
              className="group animate-fade-up"
              style={{ animationDelay: `${i * 45}ms` }}
            >
              <Card interactive className="relative p-4">
                <div className={`pointer-events-none absolute inset-0 bg-gradient-to-br ${t.chip} opacity-0 transition-opacity duration-300 group-hover:opacity-100`} />
                <div className="relative flex items-start justify-between">
                  <div>
                    <p className="text-[28px] font-bold leading-none tracking-tight text-ink-950 tabular-nums">
                      {s.value.toLocaleString()}
                    </p>
                    <p className="mt-2 text-xs font-medium text-ink-500">{s.label}</p>
                  </div>
                  <span className={`flex h-9 w-9 shrink-0 items-center justify-center rounded-xl ${t.icon} ring-1 ring-inset ring-black/[0.03]`}>
                    <s.icon className="h-[18px] w-[18px]" strokeWidth={2} />
                  </span>
                </div>
                <span className="pointer-events-none absolute bottom-3.5 right-3.5 opacity-0 transition-all duration-300 group-hover:translate-x-0 group-hover:opacity-100 -translate-x-1 text-ink-300">
                  <ArrowUpRight className="h-4 w-4" />
                </span>
              </Card>
            </Link>
          )
        })}
      </div>

      <Card className="animate-fade-up" style={{ animationDelay: '160ms' }}>
        <div className="flex items-center justify-between border-b border-ink-200/70 px-5 py-4">
          <h2 className="text-sm font-semibold text-ink-900">Recent audit events</h2>
          <Link
            href="/dashboard/audit"
            className="inline-flex items-center gap-1 text-xs font-medium text-brand-600 transition-colors hover:text-brand-700"
          >
            View all
            <ArrowUpRight className="h-3.5 w-3.5" />
          </Link>
        </div>
        {data.recentAudit.length === 0 ? (
          <p className="px-5 py-8 text-center text-sm text-ink-500">No audit events yet.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="data-table">
              <thead>
                <tr>
                  <th>Action</th>
                  <th className="w-32">Outcome</th>
                  <th className="w-48">Time</th>
                </tr>
              </thead>
              <tbody>
                {data.recentAudit.map((a) => (
                  <tr key={a.id}>
                    <td className="font-mono text-xs text-ink-600">{a.action}</td>
                    <td>
                      <StatusBadge value={a.outcome} />
                    </td>
                    <td className="text-xs text-ink-500">
                      {new Date(a.created_at).toLocaleString()}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>
    </div>
  )
}