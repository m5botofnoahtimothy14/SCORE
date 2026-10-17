// Issue a one-time student activation code (same logic as /api/activation-code).
// Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY. Args: STUDENT_ID_NO.
// Prints the code ONCE — share it with the student, then forget it.
import { createRequire } from 'node:module';
import { createHash, randomBytes } from 'node:crypto';
const requireFromAdmin = createRequire('D:/Teachcross APP/apps/admin/package.json');
const { createClient } = requireFromAdmin('@supabase/supabase-js');

const sidNo = process.argv[2];
if (!sidNo) {
  console.error('Usage: node issue-code.mjs <STUDENT_ID_NO>');
  process.exit(1);
}
const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});
const { data: student, error: sErr } = await supabase
  .from('students')
  .select('id, school_id, first_name, last_name')
  .eq('student_id_no', sidNo)
  .maybeSingle();
if (sErr || !student) {
  console.error('Student not found.');
  process.exit(1);
}
const code = randomBytes(4).toString('hex').toUpperCase();
const hash = createHash('sha256').update(code).digest('hex');
const { error } = await supabase.from('student_activation_credentials').upsert(
  {
    school_id: student.school_id,
    student_id: student.id,
    code: hash,
    expires_at: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
    used_at: null,
    created_by: null,
  },
  { onConflict: 'student_id' }
);
if (error) {
  console.error('Issue failed:', error.message);
  process.exit(1);
}
await supabase.from('audit_events').insert({
  school_id: student.school_id,
  action: 'enrollment.code.issued',
  target_type: 'student',
  target_id: student.id,
  outcome: 'success',
});
console.log(`CODE for ${student.first_name} ${student.last_name} (${sidNo}): ${code}`);
