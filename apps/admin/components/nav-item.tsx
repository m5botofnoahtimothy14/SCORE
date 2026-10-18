'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import type { LucideIcon } from 'lucide-react'

export interface NavEntry {
  href: string
  icon: LucideIcon
  label: string
}

export function NavItem({ href, icon: Icon, label }: NavEntry) {
  const pathname = usePathname()
  const isActive = pathname === href
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