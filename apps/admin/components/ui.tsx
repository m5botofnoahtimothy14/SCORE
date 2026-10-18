'use client'

import { useEffect, useState } from 'react'
import { AlertTriangle, CheckCircle2, Inbox, Loader2, X } from 'lucide-react'

// ── Shared UI primitives for the DMS ─────────────────────────
// One design language for every screen: gloss, depth, calm motion.

export function PageHeader({
  title,
  subtitle,
  action,
}: {
  title: string
  subtitle?: string
  action?: React.ReactNode
}) {
  return (
    <div className="mb-7 flex flex-wrap items-start justify-between gap-4 animate-fade-up">
      <div className="min-w-0">
        <h1 className="text-[26px] font-bold leading-tight tracking-tight text-ink-950">
          {title}
        </h1>
        {subtitle && <p className="mt-1.5 text-sm text-ink-500">{subtitle}</p>}
      </div>
      {action && <div className="flex shrink-0 items-center gap-2">{action}</div>}
    </div>
  )
}

export function Card({
  children,
  className = '',
  interactive = false,
  style,
}: {
  children: React.ReactNode
  className?: string
  interactive?: boolean
  style?: React.CSSProperties
}) {
  return (
    <div
      style={style}
      className={[
        'surface-card overflow-hidden',
        interactive
          ? 'transition-all duration-300 ease-spring hover:-translate-y-0.5 hover:border-ink-300/70 hover:shadow-lift'
          : '',
        className,
      ].join(' ')}
    >
      {children}
    </div>
  )
}

/** Small coloured dot + label used by StatusBadge. */
function toneFor(value: string): { chip: string; dot: string } {
  switch (value) {
    case 'active':
    case 'success':
    case 'sent':
    case 'approved':
    case 'resolved':
    case 'delivered':
    case 'read':
      return { chip: 'bg-emerald-50 text-emerald-700 ring-emerald-600/15', dot: 'bg-emerald-500' }
    case 'closed':
    case 'skipped':
      return { chip: 'bg-ink-100 text-ink-600 ring-ink-500/10', dot: 'bg-ink-400' }
    case 'pending':
    case 'held':
    case 'held_for_review':
    case 'pending_scan':
    case 'queued':
      return { chip: 'bg-amber-50 text-amber-700 ring-amber-600/15', dot: 'bg-amber-500' }
    case 'in_progress':
    case 'investigating':
    case 'under_review':
    case 'open':
    case 'processing':
      return { chip: 'bg-sky-50 text-sky-700 ring-sky-600/15', dot: 'bg-sky-500' }
    case 'failed':
    case 'blocked':
    case 'rejected':
    case 'suspended':
      return { chip: 'bg-rose-50 text-rose-700 ring-rose-600/15', dot: 'bg-rose-500' }
    case 'quarantined':
      return { chip: 'bg-orange-50 text-orange-700 ring-orange-600/15', dot: 'bg-orange-500' }
    case 'escalated':
      return { chip: 'bg-violet-50 text-violet-700 ring-violet-600/15', dot: 'bg-violet-500' }
    case 'priority_alert':
      return { chip: 'bg-rose-50 text-rose-700 ring-rose-600/20', dot: 'bg-rose-500' }
    default:
      return { chip: 'bg-ink-100 text-ink-700 ring-ink-500/10', dot: 'bg-ink-400' }
  }
}

export function StatusBadge({ value }: { value: string }) {
  const { chip, dot } = toneFor(value)
  const emphasise = value === 'priority_alert'
  return (
    <span
      className={[
        'inline-flex items-center gap-1.5 whitespace-nowrap rounded-full px-2.5 py-1',
        'text-[11px] font-semibold capitalize ring-1 ring-inset',
        chip,
        emphasise ? 'animate-pulse-ring' : '',
      ].join(' ')}
    >
      <span className={`h-1.5 w-1.5 rounded-full ${dot}`} aria-hidden />
      {value.replace(/_/g, ' ')}
    </span>
  )
}

export function EmptyState({ title, subtitle }: { title: string; subtitle?: string }) {
  return (
    <div className="flex flex-col items-center justify-center px-6 py-16 text-center animate-fade-in">
      <div className="relative mb-4 flex h-14 w-14 items-center justify-center rounded-2xl bg-gradient-to-b from-ink-50 to-ink-100 ring-1 ring-inset ring-ink-200/70">
        <Inbox className="h-6 w-6 text-ink-400" strokeWidth={1.75} />
      </div>
      <p className="text-sm font-semibold text-ink-800">{title}</p>
      {subtitle && <p className="mt-1 max-w-sm text-sm text-ink-500">{subtitle}</p>}
    </div>
  )
}

export function ErrorState({ message, onRetry }: { message: string; onRetry: () => void }) {
  return (
    <div className="flex flex-col items-center justify-center px-6 py-16 text-center animate-scale-in">
      <div className="mb-4 flex h-14 w-14 items-center justify-center rounded-2xl bg-rose-50 ring-1 ring-inset ring-rose-600/15">
        <AlertTriangle className="h-6 w-6 text-rose-500" strokeWidth={1.75} />
      </div>
      <p className="max-w-md text-sm text-ink-700">{message}</p>
      <button onClick={onRetry} className="btn-primary mt-5">
        Try again
      </button>
    </div>
  )
}

export function LoadingState({ message = 'Loading…' }: { message?: string }) {
  return (
    <div className="flex flex-col items-center justify-center gap-3 py-16 animate-fade-in">
      <Loader2 className="h-6 w-6 animate-spin text-brand-500" strokeWidth={2.25} />
      <p className="text-sm text-ink-500">{message}</p>
    </div>
  )
}

/** Skeleton block used while a section resolves. */
export function Skeleton({ className = '' }: { className?: string }) {
  return (
    <div className={`shimmer-sweep relative overflow-hidden rounded-lg bg-ink-100 ${className}`} />
  )
}

function DialogShell({
  children,
  onClose,
  maxWidth = 'max-w-md',
}: {
  children: React.ReactNode
  onClose: () => void
  maxWidth?: string
}) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose()
    }
    window.addEventListener('keydown', onKey)
    const { overflow } = document.body.style
    document.body.style.overflow = 'hidden'
    return () => {
      window.removeEventListener('keydown', onKey)
      document.body.style.overflow = overflow
    }
  }, [onClose])

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-ink-950/45 p-4 backdrop-blur-[3px] animate-fade-in"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onClose()
      }}
    >
      <div
        role="dialog"
        aria-modal="true"
        className={`w-full ${maxWidth} animate-scale-in rounded-2xl border border-white/70 bg-white p-6 shadow-lift ring-gradient`}
      >
        {children}
      </div>
    </div>
  )
}

export function ConfirmDialog({
  title,
  message,
  confirmLabel = 'Confirm',
  danger = false,
  onConfirm,
  onCancel,
}: {
  title: string
  message: string
  confirmLabel?: string
  danger?: boolean
  onConfirm: () => void
  onCancel: () => void
}) {
  return (
    <DialogShell onClose={onCancel}>
      <h3 className="text-base font-semibold text-ink-950">{title}</h3>
      <p className="mt-2 text-sm leading-relaxed text-ink-500">{message}</p>
      <div className="mt-6 flex justify-end gap-2.5">
        <button onClick={onCancel} className="btn-secondary">
          Cancel
        </button>
        <button
          onClick={onConfirm}
          className={danger ? 'btn-danger' : 'btn-primary'}
        >
          {confirmLabel}
        </button>
      </div>
    </DialogShell>
  )
}

export function Modal({
  title,
  subtitle,
  children,
  onClose,
  wide = false,
}: {
  title: string
  subtitle?: string
  children: React.ReactNode
  onClose: () => void
  wide?: boolean
}) {
  return (
    <DialogShell onClose={onClose} maxWidth={wide ? 'max-w-2xl' : 'max-w-md'}>
      <div className="mb-5 flex items-start justify-between gap-4">
        <div className="min-w-0">
          <h3 className="text-base font-semibold text-ink-950">{title}</h3>
          {subtitle && <p className="mt-1 text-sm text-ink-500">{subtitle}</p>}
        </div>
        <button
          onClick={onClose}
          aria-label="Close"
          className="btn-ghost -mr-2 -mt-1 h-8 w-8 shrink-0 rounded-lg p-0"
        >
          <X className="h-4 w-4" />
        </button>
      </div>
      {children}
    </DialogShell>
  )
}

export function useToast() {
  const [toast, setToast] = useState<{ ok: boolean; msg: string } | null>(null)

  useEffect(() => {
    if (!toast) return
    const t = setTimeout(() => setToast(null), 4000)
    return () => clearTimeout(t)
  }, [toast])

  const show = (ok: boolean, msg: string) => setToast({ ok, msg })

  const node = toast ? (
    <div className="pointer-events-none fixed bottom-6 right-6 z-[60] animate-slide-in-right">
      <div
        role="status"
        className={[
          'flex max-w-sm items-start gap-3 rounded-xl border px-4 py-3 shadow-lift backdrop-blur-md',
          toast.ok
            ? 'border-emerald-200/80 bg-emerald-50/95 text-emerald-900'
            : 'border-rose-200/80 bg-rose-50/95 text-rose-900',
        ].join(' ')}
      >
        {toast.ok ? (
          <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0 text-emerald-600" />
        ) : (
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-rose-600" />
        )}
        <p className="text-sm font-medium">{toast.msg}</p>
      </div>
    </div>
  ) : null

  return { show, node }
}

// ── Exported class constants (existing pages import these) ──
export const inputCls = 'input'
export const btnPrimary = 'btn-primary'
export const btnSecondary = 'btn-secondary'