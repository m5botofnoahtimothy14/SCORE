'use client'

import { useEffect, useState } from 'react'
import Link from 'next/link'
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
  if (!data) return <LoadingState message="Loading overview..." />

  const stats = [
    { label: 'Students', value: data.students, href: '/dashboard/students' },
    { label: 'Teachers', value: data.teachers, href: '/dashboard/teachers' },
    { label: 'Classes', value: data.classes, href: '/dashboard/classes' },
    { label: 'Notices (7d)', value: data.announcementsWeek, href: '/dashboard/announcements' },
    { label: 'Pending moderation', value: data.pendingModeration, href: '/dashboard/moderation' },
    { label: 'Open incidents', value: data.openIncidents, href: '/dashboard/incidents' },
    { label: 'Failed notifications', value: data.failedNotifications, href: '/dashboard/notifications' },
  ]

  return (
    <div>
      <PageHeader title={data.schoolName} subtitle={`Signed in as ${data.role.replace(/_/g, ' ')}`} />
      {(!data.providers.fcm || !data.providers.moderation || !data.providers.vision) && (
        <div className="bg-yellow-50 border border-yellow-200 rounded-xl p-4 mb-6 text-sm text-yellow-800">
          Provider configuration incomplete:{' '}
          {[
            !data.providers.fcm && 'FCM (push notifications disabled)',
            !data.providers.moderation && 'text moderation (messages held for review)',
            !data.providers.vision && 'image safety (uploads quarantined)',
          ]
            .filter(Boolean)
            .join(' · ')}
          . See <Link href="/dashboard/health" className="underline">System Health</Link> for setup.
        </div>
      )}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
        {stats.map((s) => (
          <Link key={s.label} href={s.href}>
            <Card className="p-4 hover:shadow-md transition-shadow">
              <p className="text-2xl font-bold text-gray-900">{s.value}</p>
              <p className="text-xs text-gray-500 mt-1">{s.label}</p>
            </Card>
          </Link>
        ))}
      </div>
      <Card className="p-4">
        <h2 className="font-semibold text-gray-900 mb-3">Recent audit events</h2>
        {data.recentAudit.length === 0 ? (
          <p className="text-sm text-gray-500">No audit events yet.</p>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left text-gray-500 text-xs">
                <th className="py-2">Action</th>
                <th>Outcome</th>
                <th>Time</th>
              </tr>
            </thead>
            <tbody>
              {data.recentAudit.map((a) => (
                <tr key={a.id} className="border-t border-gray-100">
                  <td className="py-2 font-mono text-xs">{a.action}</td>
                  <td>
                    <StatusBadge value={a.outcome} />
                  </td>
                  <td className="text-gray-500 text-xs">{new Date(a.created_at).toLocaleString()}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </Card>
    </div>
  )
}
