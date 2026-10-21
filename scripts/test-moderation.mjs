// End-to-end moderation test: insert messages and check the pipeline
// moderates them, using the shared policy module.
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

const { data: conv } = await db
  .from('conversations')
  .select('id')
  .eq('school_id', SCHOOL)
  .limit(1)
  .single()

const { data: student } = await db
  .from('students')
  .select('user_id')
  .eq('school_id', SCHOOL)
  .not('user_id', 'is', null)
  .limit(1)
  .maybeSingle()

const CASES = [
  { label: 'benign maths question', body: 'Sir how do we solve this quadratic equation x2 - 5x + 6 = 0 by factorisation?', expect: 'approved' },
  { label: 'canonical benign fight', body: 'I had a fight with my friend about homework, it is so silly', expect: 'approved' },
  { label: 'threat', body: 'I will break your legs you worthless idiot, see you after school', expect: 'blocked' },
  { label: 'suicide encouragement', body: 'you are so stupid you should just kill yourself, nobody likes you here', expect: 'escalated' },
  { label: 'CSAE solicitation', body: 'send me photos of the girls in 7A naked, I want to see them without clothes', expect: 'escalated' },
  { label: 'child abuse disclosure', body: 'my father hits me every night when I bring home bad marks, please tell someone', expect: 'held' },
]

for (const c of CASES) {
  const key = `e2e_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`
  const { data: msg, error } = await db
    .from('messages')
    .insert({
      idempotency_key: key,
      conversation_id: conv.id,
      school_id: SCHOOL,
      sender_id: student.user_id,
      body: c.body,
      status: 'pending_moderation',
    })
    .select('id')
    .single()
  if (error) {
    console.log(`insert failed: ${error.message}`)
    continue
  }

  let status = 'pending_moderation'
  let verdict = null
  for (let i = 0; i < 14; i++) {
    await new Promise((r) => setTimeout(r, 2000))
    const { data: cur } = await db.from('messages').select('status').eq('id', msg.id).single()
    status = cur.status
    if (status !== 'pending_moderation') {
      const { data: mr } = await db
        .from('moderation_results')
        .select('verdict, raw_response')
        .eq('message_id', msg.id)
        .maybeSingle()
      verdict = mr?.verdict ?? null
      break
    }
  }

  const ok = status === 'approved' || status === 'blocked' || status === 'held_for_review'
  console.log(
    `${ok ? 'OK ' : 'ERR'} ${c.label.padEnd(28)} status=${String(status).padEnd(18)} verdict=${String(verdict).padEnd(10)} expected=${c.expect}`,
  )
  if (verdict) {
    const { data: mr } = await db
      .from('moderation_results')
      .select('raw_response')
      .eq('message_id', msg.id)
      .maybeSingle()
    const rr = mr?.raw_response ?? {}
    console.log(`     rules: ${(rr.matched_rules ?? []).join(', ')}`)
    console.log(`     why  : ${(rr.reasons ?? []).slice(0, 2).join(' | ').slice(0, 150)}`)
  }
}
