// Verify the admin DMS can read core tables as platform_owner.
import { createRequire } from 'node:module';
const req = createRequire('D:/Teachcross APP/apps/admin/package.json');
const { createClient } = req('@supabase/supabase-js');
const c = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_ANON_KEY, { auth: { persistSession: false } });

const { data: a, error: e } = await c.auth.signInWithPassword({
  email: 'noahtimothykeba@gmail.com', password: 'teachcrossnoahdev1',
});
if (e) { console.log('LOGIN FAIL:', e.message); process.exit(0); }
console.log('login ok, uid', a.user.id.slice(0, 8));

for (const tbl of ['schools', 'students', 'teachers', 'classes', 'school_memberships', 'user_profiles', 'announcements']) {
  const { count, error } = await c.from(tbl).select('*', { count: 'exact', head: true });
  console.log(error ? `  x ${tbl}: ${error.message}` : `  v ${tbl}: ${count} rows`);
}
const { data: st, error: se } = await c.from('students').select('id, student_id_no, first_name, last_name, school_id').limit(3);
console.log('students sample:', se ? se.message : JSON.stringify(st));
const { data: prof } = await c.from('user_profiles').select('id, display_name').eq('id', a.user.id).maybeSingle();
console.log('my profile:', JSON.stringify(prof));
const { data: mem } = await c.from('school_memberships').select('role, school_id').eq('user_id', a.user.id);
console.log('my memberships:', JSON.stringify(mem));
