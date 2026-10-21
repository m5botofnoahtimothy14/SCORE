import { redirect } from 'next/navigation'
import { ShieldCheck } from 'lucide-react'
import { createClient } from '@/lib/supabase/server'
import { ADMIN_ROLES, roleLabel } from '@/lib/auth'
import { Footer } from '@/components/footer'
import { NavItem, type NavEntry } from '@/components/nav-item'
import { LogoutButton } from './logout-button'

export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode
}) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) redirect('/auth/login')

  const { data: membership } = await supabase
    .from('school_memberships')
    .select('role, schools(id, name, code, logo_url)')
    .eq('user_id', user.id)
    .eq('is_active', true)
    .in('role', ADMIN_ROLES)
    .order('joined_at', { ascending: false })
    .limit(1)
    .maybeSingle()

  if (!membership) redirect('/auth/login?error=insufficient_permissions')

  const role = (membership as { role: string }).role

  return (
    <div className="flex h-screen overflow-hidden bg-background">
      <Sidebar
        user={user}
        membership={membership as unknown as SidebarProps['membership']}
      />
      <main className="flex min-w-0 flex-1 flex-col overflow-hidden">
        <TopBar role={role} />
        <div className="flex-1 overflow-y-auto px-6 py-7 lg:px-8">
          <div className="mx-auto w-full max-w-[1400px]">{children}</div>
        </div>
        <Footer />
      </main>
    </div>
  )
}

// Icons are referenced by name — the layout is a Server Component and
// component functions cannot cross the server/client boundary.
const operationsNav: NavEntry[] = [
  { href: '/dashboard', icon: 'LayoutDashboard', label: 'Overview' },
  { href: '/dashboard/students', icon: 'GraduationCap', label: 'Students' },
  { href: '/dashboard/teachers', icon: 'Users', label: 'Teachers' },
  { href: '/dashboard/classes', icon: 'BookOpen', label: 'Classes' },
  { href: '/dashboard/announcements', icon: 'Megaphone', label: 'Announcements' },
  { href: '/dashboard/moderation', icon: 'ShieldAlert', label: 'Moderation' },
  { href: '/dashboard/ml-scoring', icon: 'Sigma', label: 'ML Scoring' },
  { href: '/dashboard/incidents', icon: 'ShieldAlert', label: 'Incidents' },
  { href: '/dashboard/audit', icon: 'ClipboardList', label: 'Audit Trail' },
  { href: '/dashboard/notifications', icon: 'Bell', label: 'Notifications' },
  { href: '/dashboard/tickets', icon: 'TicketIcon', label: 'Support' },
  { href: '/dashboard/settings', icon: 'Settings', label: 'Settings' },
]

// Super-Admin-only: platform-wide data and control.
const platformNav: NavEntry[] = [
  { href: '/dashboard/schools', icon: 'School', label: 'All Schools' },
  { href: '/dashboard/admins', icon: 'UserCog', label: 'Administrators' },
  { href: '/dashboard/health', icon: 'Activity', label: 'System Health' },
]

interface SidebarProps {
  user: { email?: string | null }
  membership: {
    role: string
    schools: { id: string; name: string; code: string; logo_url?: string | null } | { id: string; name: string; code: string; logo_url?: string | null }[] | null
  }
}

function Sidebar({ user, membership }: SidebarProps) {
  const rawSchool = membership?.schools
  const school = Array.isArray(rawSchool) ? rawSchool[0] : rawSchool
  const isSuper = membership?.role === 'platform_owner'

  const groups = isSuper
    ? [
        { section: 'Platform Control', items: platformNav },
        { section: 'Operations', items: operationsNav },
      ]
    : [
        { section: 'My School', items: [{ href: '/dashboard/schools', icon: 'School', label: 'School Profile' }] },
        { section: 'Operations', items: operationsNav },
      ]

  const initial = (user?.email ?? 'A').charAt(0).toUpperCase()

  return (
    <aside className="relative hidden w-[268px] shrink-0 flex-col overflow-hidden bg-ink-950 md:flex">
      {/* Ambient depth behind the sidebar. */}
      <div
        aria-hidden
        className="pointer-events-none absolute inset-0 bg-grid-dark opacity-70"
      />
      <div
        aria-hidden
        className="pointer-events-none absolute -left-24 -top-24 h-64 w-64 rounded-full bg-brand-600/25 blur-3xl"
      />
      <div
        aria-hidden
        className="pointer-events-none absolute -bottom-28 -right-20 h-64 w-64 rounded-full bg-brand-500/10 blur-3xl"
      />

      {/* Brand header */}
      <div className="relative border-b border-white/[0.07] px-5 py-5">
        <div className="flex items-center gap-3">
          <div className="relative">
            <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-brand-gradient text-sm font-bold text-white shadow-glow ring-1 ring-inset ring-white/25">
              {isSuper ? 'SA' : (school?.code?.charAt(0) ?? 'A')}
            </div>
            {/* Gloss highlight */}
            <div className="pointer-events-none absolute inset-x-0 top-0 h-1/2 rounded-t-xl bg-brand-sheen" />
          </div>
          <div className="min-w-0 flex-1">
            <p className="truncate text-sm font-semibold text-white">
              {isSuper ? 'TeachCross Platform' : (school?.name ?? 'School')}
            </p>
            <p className="text-xs text-slate-400">{roleLabel(membership?.role ?? '')}</p>
          </div>
        </div>
        {isSuper && (
          <div className="mt-3.5 rounded-xl border border-brand-400/20 bg-brand-500/10 px-3 py-2.5">
            <p className="flex items-center gap-1.5 text-[11px] font-semibold text-brand-200">
              <ShieldCheck className="h-3.5 w-3.5" />
              Full platform control
            </p>
            <p className="mt-1 text-[11px] leading-snug text-slate-400">
              Every school, administrator and the underlying data.
            </p>
          </div>
        )}
      </div>

      {/* Navigation */}
      <nav className="relative flex-1 space-y-6 overflow-y-auto px-3 py-5">
        {groups.map((group) => (
          <div key={group.section}>
            <p className="mb-2 px-3 text-[10px] font-semibold uppercase tracking-[0.14em] text-slate-500">
              {group.section}
            </p>
            <div className="space-y-1">
              {group.items.map((item) => (
                <NavItem key={item.href} {...item} />
              ))}
            </div>
          </div>
        ))}
      </nav>

      {/* Account footer */}
      <div className="relative border-t border-white/[0.07] px-5 py-4">
        <div className="flex items-center gap-3">
          <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-gradient-to-br from-brand-400 to-brand-700 text-sm font-semibold text-white ring-1 ring-inset ring-white/20">
            {initial}
          </div>
          <div className="min-w-0 flex-1">
            <p className="truncate text-sm font-medium text-slate-100">{user?.email}</p>
            <p className="text-xs text-slate-500">{roleLabel(membership?.role ?? '')}</p>
          </div>
          <LogoutButton />
        </div>
      </div>
    </aside>
  )
}

function TopBar({ role }: { role: string }) {
  const isSuper = role === 'platform_owner'
  return (
    <div className="sticky top-0 z-20 flex items-center justify-between border-b border-ink-200/70 bg-white/70 px-6 py-3.5 backdrop-blur-xl lg:px-8">
      <div className="flex items-center gap-2">
        <span className="text-sm font-medium text-ink-400">
          TeachCross Administration
        </span>
      </div>
      <div className="flex items-center gap-3">
        <span
          className={[
            'rounded-full px-2.5 py-1 text-xs font-semibold ring-1 ring-inset',
            isSuper
              ? 'bg-brand-50 text-brand-700 ring-brand-600/15'
              : 'bg-ink-100 text-ink-600 ring-ink-500/10',
          ].join(' ')}
        >
          {roleLabel(role)}
        </span>
      </div>
    </div>
  )
}