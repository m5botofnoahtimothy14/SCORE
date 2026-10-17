// Push FCM service-account values from the Firebase Admin SDK JSON into
// Supabase edge-function secrets via the Management API.
// Env: SUPABASE_ACCESS_TOKEN, SUPABASE_PROJECT_REF. Arg: path to admin sdk json.
import { readFileSync } from 'node:fs';

const ref = process.env.SUPABASE_PROJECT_REF;
const token = process.env.SUPABASE_ACCESS_TOKEN;
const file = process.argv[2];
if (!ref || !token || !file) {
  console.error('Usage: SUPABASE_PROJECT_REF=.. SUPABASE_ACCESS_TOKEN=.. node set-fcm-secrets.mjs <admin-sdk.json>');
  process.exit(1);
}
const j = JSON.parse(readFileSync(file, 'utf8'));
const secrets = [
  { name: 'FCM_PROJECT_ID', value: j.project_id },
  { name: 'FCM_CLIENT_EMAIL', value: j.client_email },
  { name: 'FCM_PRIVATE_KEY', value: j.private_key },
];
const res = await fetch(`https://api.supabase.com/v1/projects/${ref}/secrets`, {
  method: 'POST',
  headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify(secrets),
});
console.log('HTTP', res.status, (await res.text()).slice(0, 500));
if (!res.ok) process.exit(1);
