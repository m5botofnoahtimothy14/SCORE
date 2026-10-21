// Verify the FCM push pipeline end-to-end:
//   1. find a registered device
//   2. queue a notification job for its user
//   3. run dispatch-notifications
//   4. confirm the job reached "sent"
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

const { data: devices } = await db
  .from('notification_devices')
  .select('id, user_id, platform, is_active, last_seen_at, app_version')
  .eq('school_id', SCHOOL)
console.log('devices:', devices)

const active = (devices ?? []).filter((d) => d.is_active)
if (!active.length) {
  console.log('No active devices registered yet — the app must be launched once to register a token.')
  process.exit(0)
}

const device = active[0]
console.log(`\nusing device ${device.id} (user ${device.user_id}, ${device.platform})`)

const key = `push_test_${Date.now()}`
const { error: insErr } = await db.from('notification_jobs').insert({
  school_id: SCHOOL,
  recipient_id: device.user_id,
  type: 'message',
  title: 'TeachCross',
  body: 'Push pipeline test',
  data: { type: 'message', conversation_id: 'test' },
  idempotency_key: key,
})
if (insErr) {
  console.error('insert failed:', insErr.message)
  process.exit(1)
}
console.log('job queued')

const { data: res, error: fnErr } = await db.functions.invoke('dispatch-notifications', {
  body: { school_id: SCHOOL },
})
if (fnErr) {
  // supabase-js sends the legacy service_role JWT; the edge function may be
  // configured with the newer sb_secret key. Try each in turn.
  console.log('functions.invoke failed:', fnErr.message)
  for (const [label, cred] of [
    ['sb_secret', env.SUPABASE_SECRET_KEY_API],
    ['legacy JWT', env.SUPABASE_SERVICE_ROLE_KEY],
  ]) {
    if (!cred) continue
    const r = await fetch(`${env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/dispatch-notifications`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        apikey: cred,
        Authorization: `Bearer ${cred}`,
      },
      body: JSON.stringify({ school_id: SCHOOL }),
    })
    const t = await r.text()
    console.log(`  ${label}: ${r.status} ${t.slice(0, 300)}`)
    if (r.ok) break
  }
} else {
  console.log('dispatch result:', JSON.stringify(res))
}

const { data: job } = await db
  .from('notification_jobs')
  .select('id, status, sent_at, failed_at, failure_reason')
  .eq('idempotency_key', key)
  .maybeSingle()
console.log('job final state:', job)
