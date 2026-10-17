// Diagnose the exact queries the Flutter app runs after activation.
// Env: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY
import { createRequire } from 'node:module';
import { createHash, randomBytes } from 'node:crypto';
const requireFromAdmin = createRequire('D:/Teachcross APP/apps/admin/package.json');
const { createClient } = requireFromAdmin('@supabase/supabase-js');

const URL = process.env.SUPABASE_URL;
const S = '11111111-1111-1111-1111-111111111111';
const admin = createClient(URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
const anon = createClient(URL, process.env.SUPABASE_ANON_KEY, { auth: { persistSession: false } });

function log(label, res) {
  if (res.error) console.log(`  ✗ ${label}: ${res.error.message} (code ${res.error.code})`);
  else console.log(`  ✓ ${label}: ${JSON.stringify(res.data)}`);
}
function boom(e, label) { console.log(`  ✗✗ ${label} THREW: ${e?.message ?? e}`); }

// --- fresh code for S1002 ---
const { data: stu } = await admin.from('students').select('id, school_id').eq('student_id_no', 'S1002').maybeSingle();
await admin.from('student_activation_credentials').delete().eq('student_id', stu.id);
await admin.from('students').update({ user_id: null }).eq('id', stu.id);
const code = randomBytes(4).toString('hex').toUpperCase();
await admin.from('student_activation_credentials').insert({
  school_id: stu.school_id, student_id: stu.id,
  code: createHash('sha256').update(code).digest('hex'),
  expires_at: new Date(Date.now() + 7 * 864e5).toISOString(),
});
console.log(`Fresh code for S1002: ${code}\n`);

const { data: auth, error: aErr } = await anon.auth.signInAnonymously();
if (aErr) { console.log('signInAnonymously FAILED:', aErr.message); process.exit(1); }
const me = auth.user.id;
console.log('anon user:', me.slice(0, 8), '\n');

console.log('activate-student:');
const act = await anon.functions.invoke('activate-student', {
  body: { school_id: S, student_id_no: 'S1002', activation_code: code },
});
log('activate', act);

console.log('\nPROFILE screen queries:');
let p1, p2, p3, p4;
try { p1 = await anon.from('user_profiles').select().eq('id', me).maybeSingle(); log('user_profiles', p1); } catch (e) { boom(e, 'user_profiles'); }
try { p2 = await anon.from('school_memberships').select('role, school_id, schools(name)').eq('user_id', me).eq('is_active', true).order('joined_at', { ascending: false }).limit(1).maybeSingle(); log('school_memberships+schools', p2); } catch (e) { boom(e, 'school_memberships'); }
try {
  p3 = await anon.from('students').select('id').eq('user_id', me).eq('school_id', p2?.data?.school_id).maybeSingle(); log('students', p3);
  if (p3?.data) { p4 = await anon.from('class_enrollments').select('classes(name)').eq('student_id', p3.data.id).is('unenrolled_at', null).limit(1).maybeSingle(); log('class_enrollments+classes', p4); }
} catch (e) { boom(e, 'students/enrollments'); }

console.log('\nHOME screen extra queries:');
try { const cm = await anon.from('conversation_members').select('conversation_id, last_read_at').eq('user_id', me).is('removed_at', null); log('conversation_members', cm); } catch (e) { boom(e, 'conversation_members'); }
try {
  const anns = await anon.from('announcement_recipients').select('announcement_id, announcements!inner(id, title, body, category, published_at)').eq('user_id', me).order('announcement_id', { ascending: false }).limit(3);
  log('announcement_recipients', anns);
} catch (e) { boom(e, 'announcement_recipients'); }

console.log('\nDIRECTORY query (co-school member profiles):');
try { const d = await anon.from('user_profiles').select('id, display_name').limit(5); log('user_profiles list', d); } catch (e) { boom(e, 'directory'); }

await anon.auth.signOut();
console.log('\nDone.');
