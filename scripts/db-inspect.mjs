// Diagnostic: inspect live TeachCross data via PostgREST (service role).
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

const tables = [
  'schools', 'user_profiles', 'school_memberships', 'students', 'teachers',
  'classes', 'class_enrollments', 'conversations', 'conversation_members',
  'messages', 'message_receipts', 'attachments', 'announcements',
  'announcement_recipients', 'announcement_receipts', 'moderation_results',
  'moderation_review_cases', 'notification_devices', 'notification_jobs',
  'audit_events', 'staff_activation_records', 'rate_limit_events',
  'moderation_score_snapshots', 'conversation_scores', 'staff_add_requests',
  'safeguarding_incidents', 'support_tickets', 'support_questions',
  'school_settings', 'data_retention_policies', 'public_schools',
  'background_jobs', 'teaching_assignments', 'student_activation_credentials',
]

console.log('=== ROW COUNTS ===')
for (const t of tables) {
  const { count, error } = await db.from(t).select('*', { count: 'exact', head: true })
  console.log(`${t.padEnd(34)} ${error ? 'ERR ' + error.message : String(count).padStart(6)}`)
}

console.log('\n=== SCHOOLS ===')
const { data: schools } = await db.from('schools').select('id, name, code, is_active')
console.log(schools)

console.log('\n=== MEMBERSHIPS ===')
const { data: mem } = await db.from('school_memberships').select('user_id, school_id, role, is_active').limit(50)
console.log(mem)

console.log('\n=== USERS (auth) ===')
const { data: usersPage, error: uErr } = await db.auth.admin.listUsers({ page: 1, perPage: 50 })
if (uErr) console.log('ERR', uErr.message)
else
  for (const u of usersPage.users) {
    console.log(`${u.id}  ${u.email ?? '(anon)'}  confirmed=${u.email_confirmed_at ? 'yes' : 'no'}  ${u.created_at}`)
  }

console.log('\n=== RECENT MESSAGES ===')
const { data: msgs } = await db.from('messages').select('id, status, body, created_at, school_id').order('created_at', { ascending: false }).limit(10)
console.log(msgs)

console.log('\n=== RECENT MODERATION RESULTS ===')
const { data: mrs } = await db.from('moderation_results').select('id, verdict, school_id, processed_at, categories').order('processed_at', { ascending: false }).limit(10)
console.log(mrs)

console.log('\n=== REVIEW CASES ===')
const { data: rcs } = await db.from('moderation_review_cases').select('id, status, reason_code, moderation_result_id, created_at').order('created_at', { ascending: false }).limit(10)
console.log(rcs)

console.log('\n=== CONVERSATIONS ===')
const { data: convs } = await db.from('conversations').select('id, type, school_id, title').limit(20)
console.log(convs)
