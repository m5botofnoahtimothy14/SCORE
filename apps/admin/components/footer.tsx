import { ShieldCheck } from 'lucide-react'

// Platform authorship + license footer. Shown on every DMS page.
export function Footer() {
  return (
    <footer className="border-t border-ink-200/70 bg-white/60 px-6 py-4 backdrop-blur-sm lg:px-8">
      <div className="mx-auto flex w-full max-w-[1400px] flex-col items-center justify-between gap-2 text-center sm:flex-row sm:text-left">
        <p className="text-xs text-ink-500">
          Signed by{' '}
          <span className="font-semibold text-ink-800">
            Noah Timothy Keba Joseph
          </span>{' '}
          <span className="font-mono text-ink-400">@2026</span>
        </p>
        <p className="flex items-center gap-1.5 text-xs text-ink-400">
          <ShieldCheck className="h-3.5 w-3.5 text-brand-500" />
          SCORE+™ — Proprietary License · © 2026 Noah Timothy Keba Joseph. All rights reserved.
        </p>
      </div>
    </footer>
  )
}