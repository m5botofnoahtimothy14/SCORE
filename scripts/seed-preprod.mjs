// Pre-prod seeder — mirrors supabase/seed.dev.sql row-for-row.
// Uses the service_role key; run once per environment.
// Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
import { createRequire } from 'node:module';
const requireFromAdmin = createRequire('D:/Teachcross APP/apps/admin/package.json');
const { createClient } = requireFromAdmin('@supabase/supabase-js');
const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});
const S = '11111111-1111-1111-1111-111111111111';
const Y = '22222222-2222-2222-2222-222222222222';
const C8A = '33333333-3333-3333-3333-333333333333';
const C8B = '44444444-4444-4444-4444-444444444444';

async function up(table, rows, onConflict) {
  const { error } = await supabase.from(table).upsert(rows, { onConflict });
  if (error) throw new Error(`${table}: ${error.message}`);
}
const id = (v) => v;

// 1. School + settings
await up('schools', [{ id: S, name: 'Demo Public School', code: 'DEMO', city: 'New Delhi', state: 'Delhi', country: 'India', is_active: true }], 'id');
await up('school_settings', [{ school_id: S, allow_student_id_only_login: false, require_activation_code: true, otp_provider: 'twilio', moderation_provider: 'openai', image_safety_provider: 'google_vision', max_file_size_mb: 10, retention_days: 365, timezone: 'Asia/Kolkata' }], 'school_id');
// 2. Year / subjects / classes
await up('academic_years', [{ id: Y, school_id: S, name: '2026-27', starts_on: '2026-04-01', ends_on: '2027-03-31', is_current: true }], 'id');
await up('subjects', [
  { school_id: S, name: 'Mathematics', code: 'MATH' },
  { school_id: S, name: 'Science', code: 'SCI' },
], 'school_id,name');
await up('classes', [
  { id: C8A, school_id: S, academic_year_id: Y, name: 'Grade 8-A', grade: '8', section: 'A', is_active: true },
  { id: C8B, school_id: S, academic_year_id: Y, name: 'Grade 8-B', grade: '8', section: 'B', is_active: true },
], 'id');
// 3. Rosters
await up('teachers', [
  { school_id: S, staff_id_no: 'T001', first_name: 'Asha', last_name: 'Sharma', phone: '+911234567890', email: 'asha@demo.edu', is_active: true, is_leadership: false },
  { school_id: S, staff_id_no: 'T002', first_name: 'Rahul', last_name: 'Verma', phone: '+911234567891', email: 'rahul@demo.edu', is_active: true, is_leadership: true },
], 'school_id,staff_id_no');
await up('students', [
  { school_id: S, student_id_no: 'S1001', first_name: 'Aarav', last_name: 'Kumar', is_active: true },
  { school_id: S, student_id_no: 'S1002', first_name: 'Diya', last_name: 'Singh', is_active: true },
  { school_id: S, student_id_no: 'S1003', first_name: 'Kabir', last_name: 'Mehta', is_active: true },
], 'school_id,student_id_no');
// 4. Resolve ids for joins
const { data: sts } = await supabase.from('students').select('id,student_id_no').eq('school_id', S);
const { data: tcs } = await supabase.from('teachers').select('id,staff_id_no').eq('school_id', S);
const { data: subs } = await supabase.from('subjects').select('id,code').eq('school_id', S);
const sid = Object.fromEntries(sts.map((s) => [s.student_id_no, s.id]));
const tid = Object.fromEntries(tcs.map((t) => [t.staff_id_no, t.id]));
const sub = Object.fromEntries(subs.map((s) => [s.code, s.id]));
await up('class_enrollments', [
  { school_id: S, class_id: C8A, student_id: sid.S1001 },
  { school_id: S, class_id: C8A, student_id: sid.S1002 },
  { school_id: S, class_id: C8B, student_id: sid.S1003 },
], 'class_id,student_id');
await up('teaching_assignments', [
  { school_id: S, teacher_id: tid.T001, class_id: C8A, subject_id: sub.MATH, is_class_teacher: true },
  { school_id: S, teacher_id: tid.T002, class_id: C8A, subject_id: sub.SCI, is_class_teacher: false },
  { school_id: S, teacher_id: tid.T002, class_id: C8B, subject_id: sub.SCI, is_class_teacher: false },
], 'teacher_id,class_id,subject_id');
// 5. Retention defaults
await up('data_retention_policies', [
  { school_id: S, data_type: 'messages', retention_days: 365 },
  { school_id: S, data_type: 'attachments', retention_days: 365 },
  { school_id: S, data_type: 'audit_events', retention_days: 1825 },
], 'school_id,data_type');

console.log('Seed complete: DEMO school, 2 classes, 2 teachers, 3 students.');
