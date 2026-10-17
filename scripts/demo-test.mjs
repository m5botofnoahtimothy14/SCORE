// Pre-prod demo verification — exercises the exact calls the mobile app makes.
// Env: SUPABASE_URL, SUPABASE_ANON_KEY
import { createRequire } from 'node:module';
const requireFromAdmin = createRequire('D:/Teachcross APP/apps/admin/package.json');
const { createClient } = requireFromAdmin('@supabase/supabase-js');

const url = process.env.SUPABASE_URL;
const anon = process.env.SUPABASE_ANON_KEY;
const S = '11111111-1111-1111-1111-111111111111';

const anonClient = createClient(url, anon, { auth: { persistSession: false } });

async function testStudent(code) {
  const { data: { session }, error: authErr } = await anonClient.auth.signInAnonymously();
  if (authErr) return console.log('STUDENT: anon sign-in FAILED ->', authErr.message);
  console.log('STUDENT: anon session ok:', session?.user?.id?.slice(0, 8));
  const { data, error } = await anonClient.functions.invoke('activate-student', {
    body: { school_id: S, student_id_no: 'S1001', activation_code: code },
  });
  console.log('STUDENT activate-student ->', error ? `ERR ${error.message}` : JSON.stringify(data));
  await anonClient.auth.signOut();
}

async function testTeacher() {
  const { error: authErr } = await anonClient.auth.signInAnonymously();
  if (authErr) return console.log('TEACHER: anon sign-in FAILED ->', authErr.message);
  const send = await anonClient.functions.invoke('send-otp', {
    body: { phone: '+911234567890', school_id: S, staff_id_no: 'T001' },
  });
  console.log('TEACHER send-otp ->', send.error ? `ERR ${send.error.message}` : JSON.stringify(send.data));
  const verify = await anonClient.functions.invoke('verify-otp', {
    body: { phone: '+911234567890', otp: '123456', school_id: S, staff_id_no: 'T001' },
  });
  console.log('TEACHER verify-otp ->', verify.error ? `ERR ${verify.error.message}` : JSON.stringify(verify.data));
  await anonClient.auth.signOut();
}

await testStudent(process.env.STUDENT_CODE);
await testTeacher();
