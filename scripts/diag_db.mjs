import { createRequire } from 'node:module';
const req = createRequire('D:/Teachcross APP/apps/admin/package.json');
const { createClient } = req('@supabase/supabase-js');
const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
const c = createClient(url, key);
(async () => {
  for (const t of ['doubt_requests','session_bookings','mentor_subject_approvals','mentor_availability','ratings','mentor_assessments','mentor_desk_settings','students']) {
    const { count, error } = await c.from(t).select('*', { count: 'exact', head: true });
    console.log(t, error ? 'ERR ' + error.message : count);
  }
  const { data, error } = await c.from('doubt_requests').select('id,first_reply_at').limit(1);
  console.log('first_reply_at test:', error ? error.message : JSON.stringify(data));
  const { data: sb, error: e2 } = await c.from('session_bookings').select('id,refunded,allowance_minutes_used').limit(1);
  console.log('session refund cols:', e2 ? e2.message : JSON.stringify(sb));
})();
