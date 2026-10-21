import { createServerClient } from '@supabase/ssr'
import { cookies } from 'next/headers'
import { createClient as createSupabaseClient } from '@supabase/supabase-js'

// Cookie-based client for the signed-in admin (RLS enforced).
export async function createClient() {
  const cookieStore = await cookies()

  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll()
        },
        setAll(cookiesToSet) {
          try {
            cookiesToSet.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, options)
            )
          } catch {
            // Called from a Server Component — cookies are read-only there.
          }
        },
      },
    }
  )
}

// Service-role client — SERVER ONLY. Bypasses RLS. Never import into
// client components or return its results unfiltered to the browser.
export function createServiceClient() {
  return createSupabaseClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { persistSession: false } }
  )
}

/**
 * Every service credential this deployment knows about.
 *
 * Supabase issues two shapes of service credential: the legacy
 * `role=service_role` JWT and the newer `sb_secret_…` key. Edge functions
 * are configured with one of them, so server-side calls try each in turn
 * rather than assuming a single format.
 */
export function serviceCredentials(): string[] {
  return [
    process.env.SUPABASE_SERVICE_ROLE_KEY,
    process.env.SUPABASE_SECRET_KEY_API,
  ].filter((v): v is string => Boolean(v && v.length > 0))
}

/**
 * Invoke an edge function as the platform service account.
 * Tries each known service credential until one is accepted.
 */
export async function invokeAsService(
  fn: string,
  body: Record<string, unknown>,
): Promise<{ data: unknown; error: Error | null }> {
  const url = `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/${fn}`
  const payload = JSON.stringify(body)

  let lastError: Error | null = null
  for (const credential of serviceCredentials()) {
    try {
      const res = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          apikey: credential,
          Authorization: `Bearer ${credential}`,
        },
        body: payload,
        cache: 'no-store',
      })
      const text = await res.text()
      let parsed: unknown = null
      try {
        parsed = text ? JSON.parse(text) : null
      } catch {
        parsed = { raw: text }
      }
      if (res.ok) return { data: parsed, error: null }
      lastError = new Error(
        (parsed as { error?: string; detail?: string })?.detail ??
          (parsed as { error?: string })?.error ??
          `Edge function ${fn} returned ${res.status}`,
      )
    } catch (e) {
      lastError = e instanceof Error ? e : new Error(String(e))
    }
  }
  return {
    data: null,
    error: lastError ?? new Error(`Edge function ${fn} could not be reached.`),
  }
}
