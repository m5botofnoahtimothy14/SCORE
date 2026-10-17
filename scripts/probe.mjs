// Raw HTTP probe of edge functions to surface real error bodies.
const url = process.env.SUPABASE_URL;
const anon = process.env.SUPABASE_ANON_KEY;
const S = '11111111-1111-1111-1111-111111111111';

async function anonToken() {
  const r = await fetch(`${url}/auth/v1/signup`, {
    method: 'POST',
    headers: { apikey: anon, 'Content-Type': 'application/json' },
    body: JSON.stringify({ data: {}, gotrue_meta_security: {} }),
  });
  const j = await r.json();
  return j.access_token;
}

async function call(name, token, body) {
  const r = await fetch(`${url}/functions/v1/${name}`, {
    method: 'POST',
    headers: {
      apikey: anon,
      Authorization: `Bearer ${token ?? anon}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });
  const text = await r.text();
  console.log(`${name} [${r.status}] -> ${text}`);
}

const token = await anonToken();
console.log('anon token:', token ? 'ok' : 'MISSING');
await call('activate-student', token, {
  school_id: S,
  student_id_no: 'S1001',
  activation_code: process.env.STUDENT_CODE,
});
await call('send-otp', token, { phone: '+911234567890', school_id: S, staff_id_no: 'T001' });
await call('verify-otp', token, {
  phone: '+911234567890',
  otp: '123456',
  school_id: S,
  staff_id_no: 'T001',
});
