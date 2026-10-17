// Call the activation RPCs directly with service role to surface the real PG error.
import { createRequire } from 'node:module';
const requireFromAdmin = createRequire('D:/Teachcross APP/apps/admin/package.json');
const { createClient } = requireFromAdmin('@supabase/supabase-js');

const url = process.env.SUPABASE_URL;
const svc = process.env.SUPABASE_SERVICE_ROLE_KEY;
const S = '11111111-1111-1111-1111-111111111111';
const supabase = createClient(url, svc, { auth: { persistSession: false } });

// Create a throwaway auth user to act as the device user.
const email = `probe_${Date.now()}@example.com`;
const { data: created, error: cErr } = await supabase.auth.admin.createUser({
  email,
  password: 'probe-password-123!',
  email_confirm: true,
});
if (cErr) { console.log('createUser ERR:', cErr.message); process.exit(1); }
const uid = created.user.id;
console.log('probe user:', uid);

const s = await supabase.rpc('activate_student', {
  p_school_id: S,
  p_student_id_no: 'S1002',
  p_activation_code: process.env.STUDENT_CODE,
  p_auth_user_id: uid,
});
console.log('activate_student ->', JSON.stringify(s));

const t = await supabase.rpc('activate_teacher', {
  p_school_id: S,
  p_staff_id_no: 'T001',
  p_auth_user_id: uid,
  p_phone: '+911234567890',
});
console.log('activate_teacher ->', JSON.stringify(t));

await supabase.auth.admin.deleteUser(uid);
