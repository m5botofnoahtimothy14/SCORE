// Print the roster (students / teachers / classes) for demo + testing.
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

const { data: students } = await db
  .from('students')
  .select('id, student_id_no, first_name, last_name, is_active, user_id')
  .order('student_id_no')
console.log('STUDENTS:')
for (const s of students ?? []) {
  console.log(`  ${s.student_id_no}  ${s.first_name} ${s.last_name}  active=${s.is_active}  user=${s.user_id ?? '-'}`)
}

const { data: teachers } = await db
  .from('teachers')
  .select('id, staff_id_no, first_name, last_name, phone, is_active, user_id')
  .order('staff_id_no')
console.log('\nTEACHERS:')
for (const t of teachers ?? []) {
  console.log(`  ${t.staff_id_no}  ${t.first_name} ${t.last_name}  phone=${t.phone ?? '-'}  active=${t.is_active}  user=${t.user_id ?? '-'}`)
}

const { data: classes } = await db.from('classes').select('id, name, grade, section')
console.log('\nCLASSES:')
for (const c of classes ?? []) console.log(`  ${c.id}  ${c.name}`)

const { data: enrollments } = await db
  .from('class_enrollments')
  .select('student_id, class_id, unenrolled_at')
console.log('\nENROLLMENTS:')
for (const e of enrollments ?? []) {
  console.log(`  student=${e.student_id} class=${e.class_id} unenrolled=${e.unenrolled_at ?? 'no'}`)
}
