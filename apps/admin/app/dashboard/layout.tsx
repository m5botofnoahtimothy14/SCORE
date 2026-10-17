import { redirect } from 'next/navigation'
import Link from 'next/link'
import {
  LayoutDashboard, School, Users, GraduationCap, BookOpen,
  Megaphone, ShieldAlert, ClipboardList, Settings, Bell,
  Activity, TicketIcon, UserCog,
} from 'lucide-react'
import { createClient } from '@/lib/supabase/server'
import { ADMIN_ROLES, roleLabel } from '@/lib/auth'
import { Footer } from '@/components/footer'
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
    <div className="flex h-screen bg-gray-50">
      <Sidebar
        user={user}
        membership={membership as unknown as SidebarProps['membership']}
      />
      <main className="flex-1 overflow-auto flex flex-col">
        <TopBar role={role} />
        <div className="flex-1 p-6">{children}</div>
        <Footer />
      </main>
    </div>
  )
}

interface NavEntry {
  href: string
  icon: typeof LayoutDashboard
  label: string
}

const operationsNav: NavEntry[] = [
  { href: '/dashboard', icon: LayoutDashboard, label: 'Overview' },
  { href: '/dashboard/students', icon: GraduationCap, label: 'Students' },
  { href: '/dashboard/teachers', icon: Users, label: 'Teachers' },
  { href: '/dashboard/classes', icon: BookOpen, label: 'Classes' },
  { href: '/dashboard/announcements', icon: Megaphone, label: 'Announcements' },
  { href: '/dashboard/moderation', icon: ShieldAlert, label: 'Moderation' },
  { href: '/dashboard/incidents', icon: ShieldAlert, label: 'Incidents' },
  { href: '/dashboard/audit', icon: ClipboardList, label: 'Audit Trail' },
  { href: '/dashboard/notifications', icon: Bell, label: 'Notifications' },
  { href: '/dashboard/tickets', icon: TicketIcon, label: 'Support' },
  { href: '/dashboard/settings', icon: Settings, label: 'Settings' },
]

// Super-Admin-only: platform-wide data and control.
const platformNav: NavEntry[] = [
  { href: '/dashboard/schools', icon: School, label: 'Schools' },
  { href: '/dashboard/admins', icon: UserCog, label: 'Administrators' },
  { href: '/dashboard/health', icon: Activity, label: 'System Health' },
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
        { section: 'Platform (Super Admin)', items: platformNav },
        { section: 'Operations', items: operationsNav },
      ]
    : [
        { section: 'My School', items: [{ href: '/dashboard/schools', icon: School, label: 'School Profile' }] },
        { section: 'Operations', items: operationsNav },
      ]

  return (
    <aside className="w-64 bg-slate-900 flex flex-col h-full">
      <div className="p-5 border-b border-slate-800">
        <div className="flex items-center gap-3">
          <div className={`w-9 h-9 rounded-lg flex items-center justify-center text-white font-bold text-sm ${isSuper ? 'bg-blue-600' : 'bg-slate-700'}`}>
            {isSuper ? 'SA' : (school?.code?.charAt(0) ?? 'A')}
          </div>
          <div className="flex-1 min-w-0">
            <p className="text-slate-100 text-sm font-semibold truncate">
              {isSuper ? 'TeachCross Platform' : (school?.name ?? 'School')}
            </p>
            <p className="text-slate-500 text-xs">{roleLabel(membership?.role ?? '')}</p>
          </div>
        </div>
        {isSuper && (
          <p className="mt-3 text-[11px] leading-snug text-slate-500">
            Full data and control across every school.
          </p>
        )}
      </div>

      <nav className="flex-1 overflow-y-auto px-3 py-4 space-y-5">
        {groups.map((group) => (
          <div key={group.section}>
            <p className="px-3 mb-1 text-[10px] font-semibold uppercase tracking-wider text-slate-500">
              {group.section}
            </p>
            <div className="space-y-0.5">
              {group.items.map((item) => (
                <NavItem key={item.href} {...item} />
              ))}
            </div>
          </div>
        ))}
      </nav>

      <div className="p-5 border-t border-slate-800">
        <div className="flex items-center gap-3">
          <div className="w-9 h-9 rounded-full bg-blue-600 flex items-center justify-center text-white text-sm font-medium">
            {user?.email?.charAt(0).toUpperCase()}
          </div>
          <div className="flex-1 min-w-0">
            <p className="text-slate-200 text-sm font-medium truncate">{user?.email}</p>
            <p className="text-slate-500 text-xs">{roleLabel(membership?.role ?? '')}</p>
          </div>
          <LogoutButton />
        </div>
      </div>
    </aside>
  )
}

function NavItem({ href, icon: Icon, label }: NavEntry) {
  return (
    <Link
      href={href}
      className="flex items-center gap-3 px-3 py-2.5 rounded-lg text-slate-400 hover:text-white hover:bg-slate-800 transition-all group text-sm font-medium"
    >
      <Icon size={18} className="flex-shrink-0" />
      {label}
    </Link>
  )
}

function TopBar({ role }: { role: string }) {
  const isSuper = role === 'platform_owner'
  return (
    <div className="bg-white border-b border-gray-200 px-6 py-3 flex items-center justify-between">
      <div className="flex items-center gap-2">
        <span className="text-sm text-gray-400">TeachCross Administration</span>
      </div>
      <div className="flex items-center gap-3">
        <span
          className={`text-xs px-2.5 py-1 rounded-full font-medium ${
            isSuper ? 'bg-blue-50 text-blue-700' : 'bg-gray-100 text-gray-600'
          }`}
        >
          {roleLabel(role)}
        </span>
      </div>
    </div>
  )
}
