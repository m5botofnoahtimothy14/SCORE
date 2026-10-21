// Upload a test image and run it through the deployed moderate-image
// edge function, to prove the Cloud Vision path works end to end.
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

// A real 64x64 PNG on disk.
const png = readFileSync('C:/Users/Administrator/AppData/Local/Temp/opencode/sample.png')

const { data: student } = await db
  .from('students')
  .select('user_id')
  .eq('school_id', SCHOOL)
  .not('user_id', 'is', null)
  .limit(1)
  .maybeSingle()
const { data: conv } = await db
  .from('conversations')
  .select('id')
  .eq('school_id', SCHOOL)
  .limit(1)
  .single()

const path = `test/vision-${Date.now()}.png`
const { error: upErr } = await db.storage
  .from('attachments')
  .upload(path, png, { contentType: 'image/png', upsert: true })
if (upErr) {
  console.error('upload failed:', upErr.message)
  process.exit(1)
}
console.log('uploaded', path)

const { data: att, error: attErr } = await db
  .from('attachments')
  .insert({
    school_id: SCHOOL,
    uploader_id: student.user_id,
    message_id: null,
    type: 'image',
    file_name: 'vision-test.png',
    storage_path: path,
    mime_type: 'image/png',
    size_bytes: png.length,
    status: 'pending_scan',
  })
  .select('id, status')
  .single()
if (attErr) {
  console.error('attachment insert failed:', attErr.message)
  process.exit(1)
}
console.log('attachment', att.id, att.status)

// The trigger fires the edge function; give it time.
for (let i = 0; i < 12; i++) {
  await new Promise((r) => setTimeout(r, 2000))
  const { data: cur } = await db.from('attachments').select('status, scan_result').eq('id', att.id).single()
  if (cur.status !== 'pending_scan') {
    console.log(`t+${(i + 1) * 2}s status = ${cur.status}`)
    console.log('scan_result:', JSON.stringify(cur.scan_result, null, 2).slice(0, 900))
    const { data: mr } = await db
      .from('moderation_results')
      .select('verdict, provider, provider_error')
      .eq('attachment_id', att.id)
      .maybeSingle()
    console.log('moderation_result:', mr)
    break
  }
  if (i === 11) console.log('still pending after 24s — the trigger did not fire')
}
