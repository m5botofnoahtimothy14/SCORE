import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'

export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode
}) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) redirect('/auth/login')

  // Get admin membership + profile
  const { data: membership } = await supabase
    .from('school_memberships')
    .select('role, schools(id, name, code, logo_url)')
    .eq('user_id', user.id)
    .eq('is_active', true)
    .in('role', ['platform_owner', 'school_admin', 'principal'])
    .order('joined_at', { ascending: false })
    .limit(1)
    .maybeSingle()

  if (!membership) redirect('/auth/login?error=insufficient_permissions')

  return (
    <div className="flex h-screen bg-gray-50">
      <Sidebar user={user} membership={membership as unknown as SidebarProps['membership']} />
      <main className="flex-1 overflow-auto">
        <TopBar />
        <div className="p-6">{children}</div>
      </main>
    </div>
  )
}

// ── Sidebar ──────────────────────────────────────────────────
import Link from 'next/link'
import {
  LayoutDashboard, School, Users, GraduationCap, BookOpen,
  Megaphone, ShieldAlert, ClipboardList, Settings, Bell,
  Activity, TicketIcon, Search
} from 'lucide-react'
import { LogoutButton } from './logout-button'

const navItems = [
  { href: '/dashboard', icon: LayoutDashboard, label: 'Overview', exact: true },
  { href: '/dashboard/schools', icon: School, label: 'Schools' },
  { href: '/dashboard/students', icon: GraduationCap, label: 'Students' },
  { href: '/dashboard/teachers', icon: Users, label: 'Teachers' },
  { href: '/dashboard/classes', icon: BookOpen, label: 'Classes' },
  { href: '/dashboard/announcements', icon: Megaphone, label: 'Announcements' },
  { href: '/dashboard/moderation', icon: ShieldAlert, label: 'Moderation' },
  { href: '/dashboard/incidents', icon: ShieldAlert, label: 'Incidents' },
  { href: '/dashboard/audit', icon: ClipboardList, label: 'Audit Trail' },
  { href: '/dashboard/notifications', icon: Bell, label: 'Notifications' },
  { href: '/dashboard/health', icon: Activity, label: 'System Health' },
  { href: '/dashboard/tickets', icon: TicketIcon, label: 'Support' },
  { href: '/dashboard/settings', icon: Settings, label: 'Settings' },
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
  return (
    <aside className="w-64 bg-slate-900 flex flex-col h-full">
      {/* School branding */}
      <div className="p-5 border-b border-slate-800">
        <div className="flex items-center gap-3">
          <div className="w-9 h-9 rounded-lg bg-blue-600 flex items-center justify-center text-white font-bold text-sm">
            {school?.code?.charAt(0) ?? 'T'}
          </div>
          <div className="min-w-0">
            <p className="text-white font-semibold text-sm truncate">{school?.name ?? 'TeachCross'}</p>
            <p className="text-slate-400 text-xs capitalize">{membership?.role?.replace(/_/g, ' ')}</p>
          </div>
        </div>
      </div>

      {/* Nav items */}
      <nav className="flex-1 p-3 overflow-y-auto space-y-1">
        {navItems.map((item) => (
          <NavItem key={item.href} {...item} />
        ))}
      </nav>

      {/* User + logout */}
      <div className="p-3 border-t border-slate-800">
        <div className="flex items-center gap-3 px-3 py-2 rounded-lg hover:bg-slate-800 cursor-pointer group">
          <div className="w-8 h-8 rounded-full bg-blue-600 flex items-center justify-center text-white text-sm font-medium">
            {user?.email?.charAt(0).toUpperCase()}
          </div>
          <div className="flex-1 min-w-0">
            <p className="text-slate-200 text-sm font-medium truncate">{user?.email}</p>
          </div>
          <LogoutButton />
        </div>
      </div>
    </aside>
  )
}

function NavItem({ href, icon: Icon, label }: { href: string; icon: typeof LayoutDashboard; label: string }) {
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

function TopBar() {
  return (
    <div className="bg-white border-b border-gray-200 px-6 py-3 flex items-center justify-between">
      <div className="flex items-center gap-2">
        <Search className="w-4 h-4 text-gray-400" />
        <input
          placeholder="Search..."
          className="text-sm text-gray-500 outline-none bg-transparent"
        />
      </div>
      <div className="flex items-center gap-3">
        <span className="text-xs text-gray-400 bg-gray-100 px-2 py-1 rounded-full">
          Admin
        </span>
      </div>
    </div>
  )
}
