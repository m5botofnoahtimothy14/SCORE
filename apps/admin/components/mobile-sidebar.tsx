'use client'

import { usePathname } from 'next/navigation'
import { useEffect, useState, useCallback } from 'react'
import { X } from 'lucide-react'
import { roleLabel } from '@/lib/auth-client'
import { NavItem, type NavEntry } from '@/components/nav-item'

interface MobileSidebarProps {
  membership: {
    role?: string
    schools?:
      | { id: string; name: string; code: string; logo_url?: string | null }
      | { id: string; name: string; code: string; logo_url?: string | null }[]
      | null
  } | null
  groups: Array<{ section: string; items: NavEntry[] }>
  isSuper: boolean
}

export function MobileSidebar({ membership, groups, isSuper }: MobileSidebarProps) {
  const [sidebarOpen, setSidebarOpen] = useState(false)
  const pathname = usePathname()

  const handleRouteChange = useCallback(() => setSidebarOpen(false), [])
  useEffect(() => {
    handleRouteChange()
  }, [pathname, handleRouteChange])

  const rawSchool = membership?.schools
  const schoolObj = Array.isArray(rawSchool) ? rawSchool[0] : rawSchool

  return (
    <>
      {/* Mobile sidebar drawer */}
      <aside
        className={`fixed inset-0 z-40 bg-ink-950 flex-col overflow-hidden transform transition-transform duration-300 ease-in-out ${sidebarOpen ? 'translate-x-0' : '-translate-x-full'} md:hidden`}
      >
        <div className="relative border-b border-white/[0.07] px-4 py-4 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="relative">
              <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-brand-gradient text-sm font-bold text-white shadow-glow ring-1 ring-inset ring-white/25">
                {isSuper ? 'SA' : (schoolObj?.code?.charAt(0) ?? 'A')}
              </div>
            </div>
            <div className="min-w-0 flex-1">
              <p className="truncate text-sm font-semibold text-white">
                {isSuper ? 'SCORE+ Platform' : (schoolObj?.name ?? 'School')}
              </p>
              <p className="text-[10px] text-slate-400">{roleLabel(membership?.role ?? '')}</p>
            </div>
          </div>
          <button
            onClick={() => setSidebarOpen(false)}
            className="-mr-1 text-slate-300 hover:text-white"
            aria-label="Close menu"
          >
            <X className="h-6 w-6" />
          </button>
        </div>
        <nav className="relative flex-1 space-y-6 overflow-y-auto px-3 py-4">
          {groups.map((group) => (
            <div key={group.section}>
              <p className="mb-2 px-3 text-[10px] font-semibold uppercase tracking-[0.14em] text-slate-500">
                {group.section}
              </p>
              <div className="space-y-1">
                {group.items.map((item: NavEntry) => (
                  <NavItem
                    key={item.href}
                    {...item}
                    onClick={() => setSidebarOpen(false)}
                  />
                ))}
              </div>
            </div>
          ))}
        </nav>
      </aside>

      {/* Mobile backdrop */}
      {sidebarOpen && (
        <div
          className="fixed inset-0 z-30 bg-black/40 md:hidden backdrop-blur-sm"
          onClick={() => setSidebarOpen(false)}
        />
      )}
    </>
  )
}