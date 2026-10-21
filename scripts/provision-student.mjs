// Creates a test student and issues an activation code through the LIVE
// production admin API (teachcross-admin.vercel.app) using the platform
// owner's session — exercising the real deployed code path.
//
//   node scripts/provision-student.mjs <password> [studentIdNo]
import { createClient } from '../apps/admin/node_modules/@supabase/supabase-js/dist/index.mjs'
import { createServerClient } from '../apps/admin/node_modules/@supabase/ssr/dist/main/index.js'
import { readFileSync } from 'node:fs'

const env = {}
for (const line of readFileSync('apps/admin/.env.local', 'utf8').split(/\r?\n/)) {
  const m = line.match(/^([A-Z0-9_]+)=(.*)$/)
  if (m) env[m[1]] = m[2].trim().replace(/^"|"$/g, '')
}

const PASSWORD = process.argv[2]
const STUDENT_ID_NO = process.argv[3] ?? 'S1004'
const BASE = (process.argv[4] ?? 'https://teachcross-admin.vercel.app').replace(/\/$/, '')
const SCHOOL = '11111111-1111-1111-1111-111111111111'
const CLASS_ID = '33333333-3333-3333-3333-333333333333'

const admin = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
})

// 1. Ensure the student exists
let { data: student } = await admin
  .from('students')
  .select('id, student_id_no, first_name, is_active')
  .eq('student_id_no', STUDENT_ID_NO)
  .maybeSingle()

if (!student) {
  const { data: created, error } = await admin
    .from('students')
    .insert({
      school_id: SCHOOL,
      student_id_no: STUDENT_ID_NO,
      first_name: 'Test',
      last_name: 'Student',
      is_active: true,
    })
    .select('id, student_id_no')
    .single()
  if (error) {
    console.error('create student failed:', error.message)
    process.exit(1)
  }
  student = created
  console.log(`created student ${STUDENT_ID_NO} (${student.id})`)
} else {
  console.log(`student ${STUDENT_ID_NO} exists (${student.id})`)
}

// 2. Enrol in a class so the app has a "Teacher Support" room
const { data: existing } = await admin
  .from('class_enrollments')
  .select('id')
  .eq('student_id', student.id)
  .is('unenrolled_at', null)
  .maybeSingle()
if (!existing) {
  const { error } = await admin
    .from('class_enrollments')
    .insert({ student_id: student.id, class_id: CLASS_ID, school_id: SCHOOL })
  console.log(error ? `enrol failed: ${error.message}` : 'enrolled in Grade 8-A')
} else {
  console.log('already enrolled in a class')
}

// 3. Sign in as the platform owner and call the LIVE activation-code API
const jar = new Map()
const ssr = createServerClient(env.NEXT_PUBLIC_SUPABASE_URL, env.NEXT_PUBLIC_SUPABASE_ANON_KEY, {
  cookies: {
    getAll: () => Array.from(jar, ([name, value]) => ({ name, value })),
    setAll: (l) => { for (const { name, value } of l) jar.set(name, value) },
  },
})
const { data: owner } = await admin
  .from('school_memberships')
  .select('user_id')
  .eq('role', 'platform_owner')
  .eq('is_active', true)
  .limit(1)
  .single()
const { data: ownerUser } = await admin.auth.admin.getUserById(owner.user_id)
const { error: signErr } = await ssr.auth.signInWithPassword({
  email: ownerUser.user.email,
  password: PASSWORD,
})
if (signErr) {
  console.error('sign-in failed:', signErr.message)
  process.exit(1)
}
const cookie = Array.from(jar, ([n, v]) => `${n}=${v}`).join('; ')

const res = await fetch(`${BASE}/api/activation-code`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json', Cookie: cookie },
  body: JSON.stringify({ student_id: student.id }),
})
const body = await res.json().catch(() => null)
console.log(`\nPOST ${BASE}/api/activation-code -> ${res.status}`)
console.log(body)
if (!res.ok || !body?.code) process.exit(1)

console.log(`\n=== ACTIVATION CODE for ${STUDENT_ID_NO}: ${body.code} ===`)
