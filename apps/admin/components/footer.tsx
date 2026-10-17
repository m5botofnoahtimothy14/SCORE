import { ShieldCheck } from 'lucide-react'

// Platform authorship + license footer. Shown on every DMS page.
export function Footer() {
  return (
    <footer className="border-t border-gray-200 bg-white px-6 py-4">
      <div className="flex flex-col items-center justify-between gap-2 text-center sm:flex-row sm:text-left">
        <p className="text-xs text-gray-500">
          Signed by{' '}
          <span className="font-semibold text-gray-800">
            Noah Timothy Keba Joseph
          </span>{' '}
          <span className="font-mono text-gray-400">@2026</span>
        </p>
        <p className="flex items-center gap-1.5 text-xs text-gray-400">
          <ShieldCheck className="h-3.5 w-3.5" />
          TeachCross™ — Proprietary License · © 2026 Noah Timothy Keba Joseph. All rights reserved.
        </p>
      </div>
    </footer>
  )
}
