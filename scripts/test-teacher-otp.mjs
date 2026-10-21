// Verify the teacher OTP flow end to end against the deployed functions.
import { createClient } from '../apps/admin/node_modules/@supabase/supabase-js/dist/index.mjs'
import { readFileSync } from 'node:fs'

const env = {}
for (const line of readFileSync('apps/admin/.env.local', 'utf8').split(/\r?\n/)) {
  const m = line.match(/^([A-Z0-9_]+)=(.*)$/)
  if (m) env[m[1]] = m[2].trim().replace(/^"|"$/g, '')
}
const db = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
})
const SCHOOL = '11111111-1111-1111-1111-111111111111'
const fn = (name) => `${env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/${name}`

// The app signs in anonymously before it can call the OTP functions.
const app = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.NEXT_PUBLIC_SUPABASE_ANON_KEY, {
  auth: { persistSession: false },
})
const { data: sess, error: sErr } = await app.auth.signInAnonymously()
if (sErr) {
  console.error('anon sign-in failed:', sErr.message)
  process.exit(1)
}
const headers = {
  'Content-Type': 'application/json',
  apikey: env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
  Authorization: `Bearer ${sess.session.access_token}`,
}

const body = {
  phone: '+919000000090',
  school_id: SCHOOL,
  staff_id_no: 'T900',
  // The app sends a device secret; the function turns the anonymous session
  // into a permanent account with it.
  device_secret: 'demoDeviceSecret0123456789abcdef',
}

console.log('1. send-otp')
const r1 = await fetch(fn('send-otp'), { method: 'POST', headers, body: JSON.stringify(body) })
const b1 = await r1.json().catch(() => null)
console.log('  ->', r1.status, JSON.stringify(b1))

console.log('\n2. verify-otp (demo code 482913)')
const r2 = await fetch(fn('verify-otp'), {
  method: 'POST',
  headers,
  body: JSON.stringify({ ...body, otp: '482913' }),
})
const b2 = await r2.json().catch(() => null)
console.log('  ->', r2.status, JSON.stringify(b2))

if (b2?.success) {
  const { data: t } = await db
    .from('teachers')
    .select('staff_id_no, user_id, is_active')
    .eq('staff_id_no', 'T900')
    .maybeSingle()
  console.log('\n  teacher row:', t)

  const { data: m } = await db
    .from('school_memberships')
    .select('role, is_active')
    .eq('user_id', t.user_id)
  console.log('  membership:', m)
}
