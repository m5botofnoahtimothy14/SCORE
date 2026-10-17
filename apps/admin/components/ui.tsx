'use client'

import { useState } from 'react'

// ── Shared UI primitives for the DMS ─────────────────────────

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
    <div className="flex items-start justify-between mb-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">{title}</h1>
        {subtitle && <p className="text-sm text-gray-500 mt-1">{subtitle}</p>}
      </div>
      {action}
    </div>
  )
}

export function Card({ children, className = '' }: { children: React.ReactNode; className?: string }) {
  return (
    <div className={`bg-white rounded-xl border border-gray-200 shadow-sm ${className}`}>{children}</div>
  )
}

export function StatusBadge({ value }: { value: string }) {
  const colors: Record<string, string> = {
    active: 'bg-green-100 text-green-800',
    success: 'bg-green-100 text-green-800',
    sent: 'bg-green-100 text-green-800',
    approved: 'bg-green-100 text-green-800',
    resolved: 'bg-green-100 text-green-800',
    closed: 'bg-gray-100 text-gray-600',
    pending: 'bg-yellow-100 text-yellow-800',
    held: 'bg-yellow-100 text-yellow-800',
    held_for_review: 'bg-yellow-100 text-yellow-800',
    pending_scan: 'bg-yellow-100 text-yellow-800',
    in_progress: 'bg-blue-100 text-blue-800',
    investigating: 'bg-blue-100 text-blue-800',
    under_review: 'bg-blue-100 text-blue-800',
    open: 'bg-blue-100 text-blue-800',
    failed: 'bg-red-100 text-red-800',
    blocked: 'bg-red-100 text-red-800',
    rejected: 'bg-red-100 text-red-800',
    quarantined: 'bg-orange-100 text-orange-800',
    escalated: 'bg-purple-100 text-purple-800',
    priority_alert: 'bg-red-100 text-red-800 font-semibold',
    suspended: 'bg-red-100 text-red-800',
    skipped: 'bg-gray-100 text-gray-600',
  }
  const cls = colors[value] ?? 'bg-gray-100 text-gray-700'
  return (
    <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${cls}`}>
      {value.replace(/_/g, ' ')}
    </span>
  )
}

export function EmptyState({ title, subtitle }: { title: string; subtitle?: string }) {
  return (
    <div className="text-center py-12">
      <p className="text-gray-900 font-medium">{title}</p>
      {subtitle && <p className="text-sm text-gray-500 mt-1">{subtitle}</p>}
    </div>
  )
}

export function ErrorState({ message, onRetry }: { message: string; onRetry: () => void }) {
  return (
    <div className="text-center py-12">
      <p className="text-red-600 text-sm">{message}</p>
      <button
        onClick={onRetry}
        className="mt-4 px-4 py-2 bg-blue-600 text-white text-sm rounded-lg hover:bg-blue-500"
      >
        Try again
      </button>
    </div>
  )
}

export function LoadingState({ message = 'Loading...' }: { message?: string }) {
  return (
    <div className="py-12 flex flex-col items-center gap-3">
      <div className="w-6 h-6 border-2 border-gray-300 border-t-blue-600 rounded-full animate-spin" />
      <p className="text-sm text-gray-500">{message}</p>
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
    <div className="fixed inset-0 bg-black/40 flex items-center justify-center z-50 p-4">
      <div className="bg-white rounded-xl p-6 max-w-sm w-full shadow-xl">
        <h3 className="font-semibold text-gray-900">{title}</h3>
        <p className="text-sm text-gray-500 mt-2">{message}</p>
        <div className="flex justify-end gap-2 mt-6">
          <button onClick={onCancel} className="px-4 py-2 text-sm text-gray-600 hover:bg-gray-100 rounded-lg">
            Cancel
          </button>
          <button
            onClick={onConfirm}
            className={`px-4 py-2 text-sm text-white rounded-lg ${
              danger ? 'bg-red-600 hover:bg-red-500' : 'bg-blue-600 hover:bg-blue-500'
            }`}
          >
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>
  )
}

export function Modal({
  title,
  children,
  onClose,
  wide = false,
}: {
  title: string
  children: React.ReactNode
  onClose: () => void
  wide?: boolean
}) {
  return (
    <div className="fixed inset-0 bg-black/40 flex items-center justify-center z-50 p-4 overflow-y-auto">
      <div className={`bg-white rounded-xl p-6 shadow-xl w-full ${wide ? 'max-w-2xl' : 'max-w-md'}`}>
        <div className="flex items-center justify-between mb-4">
          <h3 className="font-semibold text-gray-900">{title}</h3>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600 text-xl leading-none">
            ×
          </button>
        </div>
        {children}
      </div>
    </div>
  )
}

export function useToast() {
  const [toast, setToast] = useState<{ ok: boolean; msg: string } | null>(null)
  function show(ok: boolean, msg: string) {
    setToast({ ok, msg })
    setTimeout(() => setToast(null), 4000)
  }
  const node = toast ? (
    <div
      className={`fixed bottom-4 right-4 px-4 py-3 rounded-lg shadow-lg text-sm text-white z-50 ${
        toast.ok ? 'bg-green-600' : 'bg-red-600'
      }`}
    >
      {toast.msg}
    </div>
  ) : null
  return { show, node }
}

export const inputCls =
  'w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500'

export const btnPrimary =
  'px-4 py-2 bg-blue-600 text-white text-sm font-medium rounded-lg hover:bg-blue-500 disabled:opacity-50'

export const btnSecondary =
  'px-4 py-2 bg-white border border-gray-300 text-sm rounded-lg hover:bg-gray-50 disabled:opacity-50'
