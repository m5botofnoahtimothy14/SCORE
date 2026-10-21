// Create the demo accounts for the walkthrough, and print the credentials.
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
const CLASS_ID = '33333333-3333-3333-3333-333333333333'

// ── Demo student ─────────────────────────────────────────────────
const STUDENT_ID_NO = 'S1001'

const { data: student } = await db
  .from('students')
  .select('id, student_id_no, first_name, last_name, is_active')
  .eq('student_id_no', STUDENT_ID_NO)
  .maybeSingle()

let studentRow = student
if (!studentRow) {
  const { data, error } = await db
    .from('students')
    .insert({
      school_id: SCHOOL,
      student_id_no: STUDENT_ID_NO,
      first_name: 'Aarav',
      last_name: 'Kumar',
      is_active: true,
    })
    .select('id, student_id_no')
    .single()
  if (error) {
    console.error('student create failed:', error.message)
    process.exit(1)
  }
  studentRow = data
  console.log('created student', STUDENT_ID_NO)
}

// make sure they are enrolled and active
await db.from('students').update({ is_active: true }).eq('id', studentRow.id)
const { data: enr } = await db
  .from('class_enrollments')
  .select('id')
  .eq('student_id', studentRow.id)
  .is('unenrolled_at', null)
  .maybeSingle()
if (!enr) {
  await db.from('class_enrollments').insert({
    student_id: studentRow.id,
    class_id: CLASS_ID,
    school_id: SCHOOL,
  })
  console.log('enrolled student in Grade 8-A')
}

// ── Demo teacher ─────────────────────────────────────────────────
const STAFF_ID_NO = 'T900'
const TEACHER_PHONE = '+919000000090'

const { data: teacher } = await db
  .from('teachers')
  .select('id, staff_id_no, first_name, last_name, phone, is_active')
  .eq('staff_id_no', STAFF_ID_NO)
  .maybeSingle()

let teacherRow = teacher
if (!teacherRow) {
  const { data, error } = await db
    .from('teachers')
    .insert({
      school_id: SCHOOL,
      staff_id_no: STAFF_ID_NO,
      first_name: 'Anita',
      last_name: 'Sharma',
      phone: TEACHER_PHONE,
      is_active: true,
      is_leadership: false,
    })
    .select('id, staff_id_no')
    .single()
  if (error) {
    console.error('teacher create failed:', error.message)
    process.exit(1)
  }
  teacherRow = data
  console.log('created teacher', STAFF_ID_NO)
}
await db.from('teachers').update({ is_active: true, phone: TEACHER_PHONE }).eq('id', teacherRow.id)

// Give the teacher a class so the teacher screens have content.
const { data: assign } = await db
  .from('teaching_assignments')
  .select('id')
  .eq('teacher_id', teacherRow.id)
  .maybeSingle()
if (!assign) {
  await db.from('teaching_assignments').insert({
    teacher_id: teacherRow.id,
    class_id: CLASS_ID,
    school_id: SCHOOL,
    subject: 'Mathematics',
  })
  console.log('assigned the teacher to Grade 8-A')
}

// ── Activation code for the student (issued through the live API) ──
const { createServerClient } = await import(
  '../apps/admin/node_modules/@supabase/ssr/dist/main/index.js'
)
const jar = new Map()
const ssr = createServerClient(env.NEXT_PUBLIC_SUPABASE_URL, env.NEXT_PUBLIC_SUPABASE_ANON_KEY, {
  cookies: {
    getAll: () => Array.from(jar, ([name, value]) => ({ name, value })),
    setAll: (l) => { for (const { name, value } of l) jar.set(name, value) },
  },
})
const { data: owner } = await db
  .from('school_memberships')
  .select('user_id')
  .eq('role', 'platform_owner')
  .eq('is_active', true)
  .limit(1)
  .single()
const { data: ownerUser } = await db.auth.admin.getUserById(owner.user_id)
const { error: signErr } = await ssr.auth.signInWithPassword({
  email: ownerUser.user.email,
  password: process.env.ADMIN_PASSWORD,
})
if (signErr) {
  console.error('sign-in failed:', signErr.message)
  process.exit(1)
}
const cookie = Array.from(jar, ([n, v]) => `${n}=${v}`).join('; ')

const res = await fetch('https://teachcross-admin.vercel.app/api/activation-code', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json', Cookie: cookie },
  body: JSON.stringify({ student_id: studentRow.id }),
})
const body = await res.json()
console.log('\nactivation-code API ->', res.status, body)

console.log('\n================ DEMO CREDENTIALS ================')
console.log('STUDENT')
console.log(`  School        : Demo Public School`)
console.log(`  Student ID    : ${STUDENT_ID_NO}`)
console.log(`  Activation code: ${body.code}`)
console.log(`  Expires       : ${body.expires_at}`)
console.log('\nTEACHER')
console.log(`  School        : Demo Public School`)
console.log(`  Staff ID      : ${STAFF_ID_NO}`)
console.log(`  Phone         : ${TEACHER_PHONE}`)
console.log(`  OTP           : (request it; the demo code is fixed)`)
console.log('==================================================')
