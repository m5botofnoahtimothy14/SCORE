// End-to-end verification against the LIVE production deployment.
//
// 1. Sets a known password for the platform owner (so the operator can log in).
// 2. Signs in through Supabase auth (same path the browser uses).
// 3. Carries the session cookies against the live Vercel URL and checks that
//    every dashboard surface and API route is reachable and error-free.
//
// Usage:  node scripts/verify-production.mjs <password> [baseUrl]
import { createClient } from '../apps/admin/node_modules/@supabase/supabase-js/dist/index.mjs'
import { createServerClient } from '../apps/admin/node_modules/@supabase/ssr/dist/main/index.js'
import { readFileSync } from 'node:fs'

const env = {}
for (const line of readFileSync('apps/admin/.env.local', 'utf8').split(/\r?\n/)) {
  const m = line.match(/^([A-Z0-9_]+)=(.*)$/)
  if (m) env[m[1]] = m[2].trim().replace(/^"|"$/g, '')
}

const PASSWORD = process.argv[2]
const BASE = (process.argv[3] ?? 'https://teachcross-admin.vercel.app').replace(/\/$/, '')

if (!PASSWORD) {
  console.error('Usage: node scripts/verify-production.mjs <password> [baseUrl]')
  process.exit(1)
}

const admin = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
})

// ── 1. Locate the platform owner and set the password ─────────────
const { data: owner } = await admin
  .from('school_memberships')
  .select('user_id, role, is_active')
  .eq('role', 'platform_owner')
  .eq('is_active', true)
  .limit(1)
  .single()
if (!owner) {
  console.error('No active platform_owner found.')
  process.exit(1)
}
console.log(`platform_owner: ${owner.user_id}`)

// Resolve the login email from the auth directory.
const { data: ownerUser } = await admin.auth.admin.getUserById(owner.user_id)
const OWNER_EMAIL = ownerUser?.user?.email
if (!OWNER_EMAIL) {
  console.error('Platform owner has no auth email.')
  process.exit(1)
}
console.log(`login email: ${OWNER_EMAIL}`)

const { error: pwErr } = await admin.auth.admin.updateUserById(owner.user_id, {
  password: PASSWORD,
  email_confirm: true,
})
if (pwErr) {
  console.error('Failed to set password:', pwErr.message)
  process.exit(1)
}
console.log('password set OK')

// ── 2. Sign in exactly like the browser does ──────────────────────
// @supabase/ssr stores the session in chunked `sb-<ref>-auth-token`
// cookies. We use the SSR client with a cookie adapter that captures them,
// then replay them against the live deployment.
const cookieJar = new Map()
const browser = createServerClient(
  env.NEXT_PUBLIC_SUPABASE_URL,
  env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
  {
    cookies: {
      getAll: () => Array.from(cookieJar, ([name, value]) => ({ name, value })),
      setAll: (list) => {
        for (const { name, value } of list) cookieJar.set(name, value)
      },
    },
  },
)
const { data: session, error: signErr } = await browser.auth.signInWithPassword({
  email: OWNER_EMAIL,
  password: PASSWORD,
})
if (signErr) {
  console.error('Sign-in failed:', signErr.message)
  process.exit(1)
}
console.log('sign-in OK — user', session.user.id)
console.log('session cookies:', Array.from(cookieJar.keys()).join(', '))

const cookieHeader = Array.from(cookieJar, ([name, value]) => `${name}=${value}`).join('; ')

async function check(label, path, opts = {}) {
  const res = await fetch(`${BASE}${path}`, {
    method: opts.method ?? 'GET',
    headers: {
      Cookie: cookieHeader,
      ...(opts.body ? { 'Content-Type': 'application/json' } : {}),
    },
    body: opts.body ? JSON.stringify(opts.body) : undefined,
    redirect: 'manual',
  })
  const text = await res.text()
  const bad =
    res.status >= 500 ||
    /Application error|Internal Server Error|Unhandled Runtime Error|__next_error__/i.test(text)
  const note = bad ? '  <-- ERROR' : ''
  console.log(`${String(res.status).padStart(3)}  ${label.padEnd(42)} ${opts.method ?? 'GET'} ${path}${note}`)
  return { res, text, bad }
}

// ── 3. Exercise the live site ─────────────────────────────────────
console.log('\n--- unauthenticated (should redirect to /auth/login) ---')
{
  const res = await fetch(`${BASE}/dashboard`, { redirect: 'manual' })
  console.log(`${res.status}  /dashboard  -> ${res.headers.get('location') ?? '(no redirect)'}`)
}

console.log('\n--- authenticated pages ---')
const pages = [
  ['Overview', '/dashboard'],
  ['Students', '/dashboard/students'],
  ['Teachers', '/dashboard/teachers'],
  ['Classes', '/dashboard/classes'],
  ['Announcements', '/dashboard/announcements'],
  ['Moderation', '/dashboard/moderation'],
  ['ML Scoring', '/dashboard/ml-scoring'],
  ['Incidents', '/dashboard/incidents'],
  ['Audit Trail', '/dashboard/audit'],
  ['Notifications', '/dashboard/notifications'],
  ['Support', '/dashboard/tickets'],
  ['Settings', '/dashboard/settings'],
  ['All Schools', '/dashboard/schools'],
  ['Administrators', '/dashboard/admins'],
  ['System Health', '/dashboard/health'],
]
let failures = 0
for (const [label, path] of pages) {
  const r = await check(label, path)
  if (r.bad) failures++
}

console.log('\n--- API routes ---')
const apis = [
  ['Health', '/api/health', 'GET'],
  ['Admins', '/api/admins', 'GET'],
  ['Notifications dispatch', '/api/notifications/dispatch', 'POST'],
  ['ML scoring run', '/api/ml-scoring/run', 'POST'],
]
for (const [label, path, method] of apis) {
  const r = await check(label, path, { method })
  if (r.bad) failures++
  if (r.res.status >= 400 && r.res.status < 500 && path !== '/api/notifications/dispatch') {
    console.log(`      body: ${r.text.slice(0, 300)}`)
  }
}

console.log('\n--- health payload ---')
{
  const res = await fetch(`${BASE}/api/health`, { headers: { Cookie: cookieHeader } })
  const body = await res.json().catch(() => null)
  if (body) {
    console.log('db.ok              :', body.db?.ok)
    console.log('providers          :', JSON.stringify(body.providers))
    console.log('queues             :', JSON.stringify(body.queues))
    console.log('tables failing     :', Object.entries(body.tables ?? {}).filter(([, v]) => !v.ok).map(([k]) => k).join(', ') || 'none')
    console.log('version            :', body.version)
  }
}

console.log('\n--- ml scoring run payload ---')
{
  const res = await fetch(`${BASE}/api/ml-scoring/run`, {
    method: 'POST',
    headers: { Cookie: cookieHeader },
  })
  console.log(res.status, (await res.text()).slice(0, 400))
}

console.log(failures === 0 ? '\nALL CHECKS PASSED' : `\n${failures} CHECK(S) FAILED`)
process.exit(failures === 0 ? 0 : 1)
