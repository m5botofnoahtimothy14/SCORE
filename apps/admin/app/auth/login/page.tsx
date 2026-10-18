'use client'

import { Suspense, useState } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { Eye, EyeOff, Shield, AlertTriangle, Lock } from 'lucide-react'

export default function LoginPage() {
  return (
    <Suspense fallback={<LoginBackdrop />}>{<LoginForm />}</Suspense>
  )
}

function LoginBackdrop() {
  return (
    <div className="relative flex min-h-screen items-center justify-center overflow-hidden bg-ink-950">
      <div aria-hidden className="absolute inset-0 bg-grid-dark opacity-70" />
      <div
        aria-hidden
        className="absolute left-1/2 top-1/2 h-[26rem] w-[26rem] -translate-x-1/2 -translate-y-1/2 rounded-full bg-brand-600/20 blur-3xl"
      />
      <p className="relative text-sm text-slate-400">Loading…</p>
    </div>
  )
}

function LoginForm() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const errorParam = searchParams.get('error')

  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(
    errorParam === 'insufficient_permissions'
      ? 'You do not have administrator access to this system.'
      : null
  )

  const supabase = createClient()

  async function handleLogin(e: React.FormEvent) {
    e.preventDefault()
    setError(null)
    setLoading(true)

    try {
      const { data, error: authError } = await supabase.auth.signInWithPassword({
        email: email.trim().toLowerCase(),
        password,
      })

      if (authError) {
        // Generic error — do not reveal whether email exists
        setError('Invalid email or password. Please try again.')
        return
      }

      if (!data.user) {
        setError('Authentication failed. Please try again.')
        return
      }

      // Verify admin role (double check — middleware is primary)
      const { data: membership } = await supabase
        .from('school_memberships')
        .select('role, schools(name)')
        .eq('user_id', data.user.id)
        .eq('is_active', true)
        .in('role', ['platform_owner', 'school_admin', 'principal'])
        .limit(1)
        .maybeSingle()

      if (!membership) {
        await supabase.auth.signOut()
        setError('You do not have administrator access. Contact your platform administrator.')
        return
      }

      router.push('/dashboard')
      router.refresh()
    } catch {
      setError('A network error occurred. Please check your connection.')
    } finally {
      setLoading(false)
    }
  }

  const fieldCls =
    'w-full rounded-xl border border-white/10 bg-white/[0.06] px-4 py-3 text-white placeholder-slate-500 ' +
    'shadow-[inset_0_1px_0_0_rgb(255_255_255/0.06)] transition-all duration-200 ' +
    'hover:border-white/20 focus:border-brand-400 focus:bg-white/[0.09] focus:outline-none focus:ring-4 focus:ring-brand-500/20'

  return (
    <div className="relative flex min-h-screen items-center justify-center overflow-hidden bg-ink-950 p-4">
      {/* Ambient background: grid + two soft brand glows. */}
      <div aria-hidden className="absolute inset-0 bg-grid-dark opacity-60" />
      <div
        aria-hidden
        className="pointer-events-none absolute -left-32 top-[-6rem] h-[30rem] w-[30rem] rounded-full bg-brand-600/25 blur-3xl"
      />
      <div
        aria-hidden
        className="pointer-events-none absolute -bottom-40 -right-24 h-[28rem] w-[28rem] rounded-full bg-brand-400/15 blur-3xl"
      />

      <div className="relative w-full max-w-md animate-fade-up">
        {/* Logo & Header */}
        <div className="mb-7 text-center">
          <div className="relative mx-auto mb-4 inline-flex h-16 w-16 items-center justify-center rounded-2xl bg-brand-gradient shadow-glow ring-1 ring-inset ring-white/25">
            <Shield className="h-8 w-8 text-white" strokeWidth={2} />
            <div className="pointer-events-none absolute inset-x-0 top-0 h-1/2 rounded-t-2xl bg-brand-sheen" />
          </div>
          <h1 className="text-[26px] font-bold tracking-tight text-white">TeachCross Admin</h1>
          <p className="mt-1 text-sm text-slate-400">School Management System</p>
        </div>

        {/* Login Card — frosted glass */}
        <div className="glass-dark rounded-2xl p-7 shadow-lift sm:p-8">
          <div className="mb-6 flex items-center gap-2.5">
            <Lock className="h-4 w-4 text-brand-300" />
            <h2 className="text-base font-semibold text-white">Administrator Sign In</h2>
          </div>

          {error && (
            <div
              role="alert"
              className="mb-6 flex animate-scale-in items-start gap-3 rounded-xl border border-rose-400/25 bg-rose-500/10 p-4"
            >
              <AlertTriangle className="mt-0.5 h-5 w-5 shrink-0 text-rose-300" />
              <p className="text-sm text-rose-200">{error}</p>
            </div>
          )}

          <form onSubmit={handleLogin} className="space-y-5">
            <div>
              <label htmlFor="admin-email" className="mb-2 block text-sm font-medium text-slate-300">
                Email Address
              </label>
              <input
                id="admin-email"
                type="email"
                required
                autoComplete="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className={fieldCls}
                placeholder="admin@school.edu.in"
              />
            </div>

            <div>
              <label htmlFor="admin-password" className="mb-2 block text-sm font-medium text-slate-300">
                Password
              </label>
              <div className="relative">
                <input
                  id="admin-password"
                  type={showPassword ? 'text' : 'password'}
                  required
                  autoComplete="current-password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  className={`${fieldCls} pr-12`}
                  placeholder="••••••••"
                />
                <button
                  type="button"
                  onClick={() => setShowPassword(!showPassword)}
                  className="absolute right-3 top-1/2 -translate-y-1/2 rounded-lg p-1 text-slate-400 transition-colors hover:text-white"
                  aria-label={showPassword ? 'Hide password' : 'Show password'}
                >
                  {showPassword ? <EyeOff className="h-5 w-5" /> : <Eye className="h-5 w-5" />}
                </button>
              </div>
            </div>

            <button
              id="admin-login-btn"
              type="submit"
              disabled={loading}
              className="btn-primary w-full py-3 text-base"
            >
              {loading ? (
                <>
                  <span className="h-4 w-4 animate-spin rounded-full border-2 border-white/30 border-t-white" />
                  Signing In…
                </>
              ) : (
                'Sign In'
              )}
            </button>
          </form>

          <div className="mt-6 border-t border-white/[0.08] pt-5">
            <p className="text-center text-xs leading-relaxed text-slate-500">
              This system is restricted to authorized administrators only.
              <br />
              Unauthorized access is prohibited.
            </p>
          </div>
        </div>

        {/* NO public registration link — by design */}
        <p className="mt-6 text-center text-xs text-slate-500">
          Signed by <span className="font-medium text-slate-300">Noah Timothy Keba Joseph</span>{' '}
          <span className="font-mono text-slate-600">@2026</span>
        </p>
        <p className="mt-1 text-center text-[11px] text-slate-600">
          TeachCross™ — Proprietary License · © 2026 Noah Timothy Keba Joseph. All rights reserved.
        </p>
      </div>
    </div>
  )
}