'use client'

import { roleLabel } from '@/lib/auth-client'

interface TopBarClientProps {
  role: string
  isSuper: boolean
}

export function TopBarClient({ role, isSuper }: TopBarClientProps) {
  return (
    <div className="sticky top-0 z-20 flex items-center justify-between border-b border-ink-200/70 bg-white/70 px-4 py-3.5 backdrop-blur-xl lg:px-8">
      <div className="flex items-center gap-2">
        <span className="hidden md:flex text-sm font-medium text-ink-400">
          SCORE+ Administration
        </span>
      </div>
      <div className="flex items-center gap-3">
        <span
          className={[
            'hidden md:flex rounded-full px-2.5 py-1 text-xs font-semibold ring-1 ring-inset',
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
