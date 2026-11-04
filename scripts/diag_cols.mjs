import { createRequire } from 'node:module';
const req = createRequire('D:/Teachcross APP/apps/admin/package.json');
const { createClient } = req('@supabase/supabase-js');
const c = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);
(async () => {
  for (const tbl of ['doubt_requests','session_bookings','students']) {
    const { data, error } = await c.from('information_schema.columns').select('column_name').eq('table_schema','public').eq('table_name',tbl);
    console.log(tbl, error ? 'ERR ' + error.message : (data||[]).map(x=>x.column_name).join(', '));
  }
})();
