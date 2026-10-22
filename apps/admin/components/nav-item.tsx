'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import {
  Activity, Bell, BookOpen, ClipboardList, GraduationCap, LayoutDashboard,
  Megaphone, School, Settings, ShieldAlert, ShieldCheck, Sigma, TicketIcon,
  UserCog, Users, HelpCircle, Clock, Percent, AlertCircle, type LucideIcon,
} from 'lucide-react'

/**
 * Icons are referenced by NAME, not by component.
 *
 * The dashboard layout is a Server Component, and the App Router cannot
 * serialise a function across the server/client boundary — passing a
 * LucideIcon component as a prop crashes every page with a 500. A plain
 * string survives the boundary and is resolved here, on the client.
 */
const NAV_ICONS: Record<string, LucideIcon> = {
  Activity,
  Bell,
  BookOpen,
  ClipboardList,
  GraduationCap,
  LayoutDashboard,
  Megaphone,
  School,
  Settings,
  ShieldAlert,
  ShieldCheck,
  Sigma,
  TicketIcon,
  UserCog,
  Users,
  HelpCircle,
  Clock,
  Percent,
  AlertCircle,
}

export interface NavEntry {
  href: string
  icon: string
  label: string
}

export function NavItem({ href, icon, label }: NavEntry) {
  const pathname = usePathname()
  const isActive = pathname === href
  const Icon = NAV_ICONS[icon] ?? LayoutDashboard

  return (
    <Link
      href={href}
      aria-current={isActive ? 'page' : undefined}
      className={[
        'group relative flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium',
        'transition-all duration-200 ease-spring',
        isActive
          ? 'bg-white/[0.10] text-white shadow-gloss'
          : 'text-slate-400 hover:bg-white/[0.05] hover:text-white',
      ].join(' ')}
    >
      {/* Active marker: a soft vertical light bar. */}
      <span
        className={[
          'absolute left-0 top-1/2 h-5 w-[3px] -translate-y-1/2 rounded-r-full bg-brand-400',
          'transition-all duration-300 ease-spring',
          isActive ? 'opacity-100 scale-y-100' : 'opacity-0 scale-y-50',
        ].join(' ')}
        aria-hidden
      />
      <Icon
        size={18}
        strokeWidth={isActive ? 2.1 : 1.85}
        className={[
          'shrink-0 transition-transform duration-300 ease-spring',
          isActive ? 'text-brand-300' : 'group-hover:scale-110',
        ].join(' ')}
      />
      {label}
    </Link>
  )
}
