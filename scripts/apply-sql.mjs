// Apply a .sql file to the linked Supabase project via the Management API.
// Env: SUPABASE_ACCESS_TOKEN, SUPABASE_PROJECT_REF. Arg: path to .sql
import { readFileSync } from 'node:fs';

const ref = process.env.SUPABASE_PROJECT_REF;
const token = process.env.SUPABASE_ACCESS_TOKEN;
const file = process.argv[2];
if (!ref || !token || !file) {
  console.error('Usage: SUPABASE_ACCESS_TOKEN=.. SUPABASE_PROJECT_REF=.. node apply-sql.mjs <file.sql>');
  process.exit(1);
}
const query = readFileSync(file, 'utf8');
const res = await fetch(`https://api.supabase.com/v1/projects/${ref}/database/query`, {
  method: 'POST',
  headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({ query }),
});
const text = await res.text();
console.log('HTTP', res.status);
console.log(text.slice(0, 2000));
if (!res.ok) process.exit(1);
