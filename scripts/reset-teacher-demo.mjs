// Reset demo state so a clean teacher/student demo can be run.
// - Clears T001 activation record + phone rate-limit bucket
// - Unlinks probe users from T001
// Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
import { createRequire } from 'node:module';
const requireFromAdmin = createRequire('D:/Teachcross APP/apps/admin/package.json');
const { createClient } = requireFromAdmin('@supabase/supabase-js');
const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});
const S = '11111111-1111-1111-1111-111111111111';

const { data: t } = await supabase
  .from('teachers')
  .select('id')
  .eq('school_id', S)
  .eq('staff_id_no', 'T001')
  .single();
if (t) {
  await supabase.from('staff_activation_records').delete().eq('teacher_id', t.id);
  await supabase.from('teachers').update({ user_id: null }).eq('id', t.id);
  console.log('T001 activation record cleared, user_id unlinked');
}
await supabase.from('rate_limit_events').delete().eq('key', 'otp:+911234567890');
console.log('rate-limit bucket for +911234567890 cleared');
