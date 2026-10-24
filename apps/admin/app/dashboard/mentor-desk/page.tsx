/* eslint-disable @typescript-eslint/no-explicit-any, @typescript-eslint/no-unused-vars */
'use client'

import { useEffect, useMemo, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { logAudit } from '@/lib/audit'
import {
  PageHeader, Card, StatusBadge, LoadingState, ErrorState,
  inputCls, btnPrimary, btnSecondary, useToast, EmptyState,
} from '@/components/ui'
import {
  Activity, AlertCircle, AlertTriangle, ArrowUpRight, CheckCircle, Clock, GraduationCap,
  HelpCircle, LayoutDashboard, Percent, School, Users,
} from 'lucide-react'

interface OverviewMetrics {
  totalDoubts: number
  waitingDoubts: number
  assignedDoubts: number
  escalatedDoubts: number
  resolvedDoubts: number
  upcomingSessions: number
  completedSessions: number
  verifiedSessions: number
  unverifiedSessions: number
  studentNoShows: number
  mentorNoShows: number
  availableMentors: number
  pendingMentorApprovals: number
  lowRatings: number
  studentsAtLimit: number
}

// Mentor Desk operational overview — all values computed from authoritative
// backend records (RLS-scoped to the admin's school).
export default function MentorDeskOverview() {
  const [metrics, setMetrics] = useState<OverviewMetrics | null>(null)
  const [activity, setActivity] = useState<
    { id: string; action: string; actor: string; target: string; created_at: string }[]
  >([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [schoolId, setSchoolId] = useState<string | null>(null)
  const [userId, setUserId] = useState<string | null>(null)
  const [refreshing, setRefreshing] = useState(false)
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

      const weekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString()
      const now = new Date().toISOString()

      const [
        totalDoubts, waitingDoubts, assignedDoubts, escalatedDoubts, resolvedDoubts,
        upcomingSessions, completedSessions, verifiedSessions, unverifiedSessions,
        studentNoShows, mentorNoShows, availableMentors, pendingMentorApprovals,
        lowRatings, studentsAtLimit, recentAudit,
      ] = await Promise.all([
        supabase.from('doubt_requests').select('id', { count: 'exact', head: true }).eq('school_id', sid),
        supabase.from('doubt_requests').select('id', { count: 'exact', head: true }).eq('school_id', sid).eq('status', 'waiting'),
        supabase.from('doubt_requests').select('id', { count: 'exact', head: true }).eq('school_id', sid).eq('status', 'assigned'),
        supabase.from('doubt_requests').select('id', { count: 'exact', head: true }).eq('school_id', sid).eq('status', 'waiting').lt('created_at', new Date(Date.now() - 30 * 60 * 1000).toISOString()),
        supabase.from('doubt_requests').select('id', { count: 'exact', head: true }).eq('school_id', sid).in('status', ['resolved', 'closed']),
        supabase.from('session_bookings').select('id', { count: 'exact', head: true }).eq('school_id', sid).eq('status', 'confirmed').gte('scheduled_at', now),
        supabase.from('session_bookings').select('id', { count: 'exact', head: true }).eq('school_id', sid).eq('status', 'completed'),
        supabase.from('session_bookings').select('id', { count: 'exact', head: true }).eq('school_id', sid).eq('status', 'completed').not('verified_at', 'is', null),
        supabase.from('session_bookings').select('id', { count: 'exact', head: true }).eq('school_id', sid).eq('status', 'completed').is('verified_at', null),
        supabase.from('session_no_shows').select('id', { count: 'exact', head: true }).eq('school_id', sid).eq('no_show_type', 'student_no_show').gte('created_at', weekAgo),
        supabase.from('session_no_shows').select('id', { count: 'exact', head: true }).eq('school_id', sid).eq('no_show_type', 'mentor_no_show').gte('created_at', weekAgo),
        supabase.from('mentor_availability').select('id', { count: 'exact', head: true }).eq('school_id', sid).eq('status', 'available'),
        supabase.from('mentor_subject_approvals').select('id', { count: 'exact', head: true }).eq('school_id', sid).eq('status', 'pending'),
        supabase.from('ratings').select('id', { count: 'exact', head: true }).eq('school_id', sid).lte('rating', 2),
        supabase.from('session_bookings').select('id', { count: 'exact', head: true }).eq('school_id', sid).eq('status', 'confirmed').gte('requested_at', weekAgo),
        supabase.from('audit_events').select('id, action, created_at').eq('school_id', sid).order('created_at', { ascending: false }).limit(12),
      ])

      // Resolve actor names for the activity feed.
      const actorIds = new Set((recentAudit.data ?? []).map((r: any) => r.actor_id))
      const actorNames = new Map<string, string>()
      if (actorIds.size > 0) {
        const { data: profiles } = await supabase.from('user_profiles').select('id, display_name').in('id', Array.from(actorIds))
        for (const p of (profiles ?? [])) actorNames.set(p.id, p.display_name ?? p.id)
      }

      setMetrics({
        totalDoubts: totalDoubts.count ?? 0,
        waitingDoubts: waitingDoubts.count ?? 0,
        assignedDoubts: assignedDoubts.count ?? 0,
        escalatedDoubts: escalatedDoubts.count ?? 0,
        resolvedDoubts: resolvedDoubts.count ?? 0,
        upcomingSessions: upcomingSessions.count ?? 0,
        completedSessions: completedSessions.count ?? 0,
        verifiedSessions: verifiedSessions.count ?? 0,
        unverifiedSessions: unverifiedSessions.count ?? 0,
        studentNoShows: studentNoShows.count ?? 0,
        mentorNoShows: mentorNoShows.count ?? 0,
        availableMentors: availableMentors.count ?? 0,
        pendingMentorApprovals: pendingMentorApprovals.count ?? 0,
        lowRatings: lowRatings.count ?? 0,
        studentsAtLimit: studentsAtLimit.count ?? 0,
      })

      setActivity(((recentAudit.data ?? []) as any[]).map((r: any) => ({
        id: r.id,
        action: r.action.replace(/_/g, ' '),
        actor: actorNames.get(r.actor_id) ?? 'System',
        target: r.target_type ?? 'record',
        created_at: r.created_at,
      })))
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load Mentor Desk overview.')
    } finally {
      setLoading(false)
      setRefreshing(false)
    }
  }

  useEffect(() => { load() }, [])

  const statGroups = useMemo(() => {
    if (!metrics) return []
    return [
      {
        section: 'Doubt requests',
        items: [
          { label: 'Total raised', value: metrics.totalDoubts.toLocaleString(), icon: Activity, href: '/dashboard/mentor-desk/doubts', tone: 'brand' },
          { label: 'Waiting for mentor', value: metrics.waitingDoubts.toLocaleString(), icon: HelpCircle, href: '/dashboard/mentor-desk/doubts', tone: 'amber' },
          { label: 'Assigned', value: metrics.assignedDoubts.toLocaleString(), icon: Users, href: '/dashboard/mentor-desk/doubts', tone: 'brand' },
          { label: 'Escalated (>30 min)', value: metrics.escalatedDoubts.toLocaleString(), icon: AlertCircle, href: '/dashboard/mentor-desk/exceptions', tone: 'rose' },
          { label: 'Resolved / closed', value: metrics.resolvedDoubts.toLocaleString(), icon: CheckCircle, href: '/dashboard/mentor-desk/doubts', tone: 'emerald' },
        ],
      },
      {
        section: 'Sessions',
        items: [
          { label: 'Upcoming', value: metrics.upcomingSessions.toLocaleString(), icon: Clock, href: '/dashboard/mentor-desk/sessions', tone: 'brand' },
          { label: 'Completed', value: metrics.completedSessions.toLocaleString(), icon: CheckCircle, href: '/dashboard/mentor-desk/sessions', tone: 'emerald' },
          { label: 'Verified', value: metrics.verifiedSessions.toLocaleString(), icon: CheckCircle, href: '/dashboard/mentor-desk/sessions', tone: 'emerald' },
          { label: 'Unverified closures', value: metrics.unverifiedSessions.toLocaleString(), icon: AlertTriangle, href: '/dashboard/mentor-desk/exceptions', tone: 'rose' },
          { label: 'Mentor no-shows (7d)', value: metrics.mentorNoShows.toLocaleString(), icon: AlertCircle, href: '/dashboard/mentor-desk/exceptions', tone: 'rose' },
        ],
      },
      {
        section: 'People & quality',
        items: [
          { label: 'Available mentors', value: metrics.availableMentors.toLocaleString(), icon: GraduationCap, href: '/dashboard/mentor-desk/mentors', tone: 'brand' },
          { label: 'Pending mentor approvals', value: metrics.pendingMentorApprovals.toLocaleString(), icon: HelpCircle, href: '/dashboard/mentor-desk/mentors', tone: 'amber' },
          { label: 'Low ratings (≤2★)', value: metrics.lowRatings.toLocaleString(), icon: AlertTriangle, href: '/dashboard/mentor-desk/ratings', tone: 'rose' },
          { label: 'Students at doubt limit', value: metrics.studentsAtLimit.toLocaleString(), icon: Percent, href: '/dashboard/mentor-desk/doubts', tone: 'rose' },
        ],
      },
    ]
  }, [metrics])

  if (error) return <ErrorState message={error} onRetry={load} />
  if (loading || !metrics) return <LoadingState message="Loading Mentor Desk overview…" />

  return (
    <div>
      {node}
      <PageHeader
        title="Mentor Desk — Overview"
        subtitle={`Live operational view · ${new Date().toLocaleDateString()}`}
        action={<button onClick={() => { setRefreshing(true); load() }} className={btnSecondary} disabled={refreshing}>{refreshing ? 'Refreshing…' : 'Refresh'}</button>}
      />

      {statGroups.map((group) => (
        <Card key={group.section} className="mb-6">
          <SectionHeader title={group.section} />
          <div className="grid grid-cols-2 gap-4 md:grid-cols-4 lg:grid-cols-5">
            {group.items.map((s, i) => (
              <Card key={s.label} interactive className="p-4" style={{ animationDelay: `${i * 40}ms` }}>
                <div className="relative flex items-start justify-between">
                  <div className="min-w-0">
                    <p className="text-[28px] font-bold leading-none tracking-tight text-ink-950 tabular-nums">{s.value}</p>
                    <p className="mt-2 text-xs font-medium text-ink-500">{s.label}</p>
                  </div>
                  <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl ring-1 ring-inset ring-black/[0.03]" style={{ backgroundColor: toneChip(s.tone).soft, color: toneChip(s.tone).onSoft }}>
                    <s.icon className="h-[18px] w-[18px]" strokeWidth={2} />
                  </span>
                </div>
                <a href={s.href} className="absolute inset-0 z-10" />
              </Card>
            ))}
          </div>
        </Card>
      ))}

      <Card className="mb-6">
        <div className="flex items-center justify-between border-b border-ink-200/70 px-5 py-4">
          <h2 className="text-sm font-semibold text-ink-900">Recent activity</h2>
          <Link href="/dashboard/audit" className="inline-flex items-center gap-1 text-xs font-medium text-brand-600 transition-colors hover:text-brand-700">
            View audit trail
            <ArrowUpRight className="h-3.5 w-3.5" />
          </Link>
        </div>
        {activity.length === 0 ? (
          <p className="px-5 py-8 text-center text-sm text-ink-500">No recent activity.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="data-table">
              <thead>
                <tr>
                  <th className="w-40">Action</th>
                  <th className="w-32">Actor</th>
                  <th className="w-32">Target</th>
                  <th className="w-48">Time</th>
                </tr>
              </thead>
              <tbody>
                {activity.map((a) => (
                  <tr key={a.id} className="border-b border-ink-200 last:border-0">
                    <td className="p-3 font-mono text-xs text-ink-600">{a.action}</td>
                    <td className="p-3 text-xs text-ink-700">{a.actor}</td>
                    <td className="p-3 text-xs text-ink-600">{a.target}</td>
                    <td className="p-3 text-xs text-ink-500 whitespace-nowrap">{new Date(a.created_at).toLocaleString()}</td>
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

function toneChip(tone: string) {
  const map: Record<string, { soft: string; onSoft: string }> = {
    brand: { soft: '#eef6ff', onSoft: '#1a56db' },
    amber: { soft: '#fffbeb', onSoft: '#b45309' },
    rose: { soft: '#fff1f2', onSoft: '#dc2626' },
    emerald: { soft: '#f0fdfa', onSoft: '#059669' },
  }
  return map[tone] ?? map.brand
}

function SectionHeader({ title }: { title: string }) {
  return (
    <div className="mb-3 flex items-end justify-between gap-3">
      <h2 className="text-xs font-semibold uppercase tracking-[0.14em] text-ink-400">{title}</h2>
    </div>
  )
}

type LinkProps = { href: string; children: React.ReactNode; className?: string }
function Link({ href, children, className }: LinkProps) {
  return <a href={href} className={['text-brand-600 text-xs font-medium hover:underline underline-offset-2', className].filter(Boolean).join(' ')}>{children}</a>
}


