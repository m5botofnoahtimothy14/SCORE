// ============================================================
// TeachCross bootstrap — one-time platform owner provisioning.
// SERVER-SIDE ONLY. Requires SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY.
// Refuses to run if platform owners already exist or BOOTSTRAP_ENABLED!=true.
//
// Usage:
//   BOOTSTRAP_ENABLED=true BOOTSTRAP_ADMIN_EMAIL=... BOOTSTRAP_ADMIN_PASSWORD=... \
//   BOOTSTRAP_SCHOOL_NAME=... BOOTSTRAP_SCHOOL_CODE=... node scripts/bootstrap.mjs
// ============================================================

const REQUIRED = [
  'SUPABASE_URL',
  'SUPABASE_SERVICE_ROLE_KEY',
  'BOOTSTRAP_ADMIN_EMAIL',
  'BOOTSTRAP_ADMIN_PASSWORD',
  'BOOTSTRAP_SCHOOL_NAME',
  'BOOTSTRAP_SCHOOL_CODE',
];

async function main() {
  if (process.env.BOOTSTRAP_ENABLED !== 'true') {
    console.error('Refusing: set BOOTSTRAP_ENABLED=true explicitly for this one-time run.');
    process.exit(1);
  }
  for (const k of REQUIRED) {
    if (!process.env[k]) {
      console.error(`Missing required env: ${k}`);
      process.exit(1);
    }
  }
  if ((process.env.BOOTSTRAP_ADMIN_PASSWORD ?? '').length < 16) {
    console.error('Refusing: BOOTSTRAP_ADMIN_PASSWORD must be at least 16 characters.');
    process.exit(1);
  }

  const { createRequire } = await import('node:module');
  const requireFromAdmin = createRequire('D:/Teachcross APP/apps/admin/package.json');
  const { createClient } = requireFromAdmin('@supabase/supabase-js');
  const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });

  // 1. Refuse re-bootstrap
  const { count } = await supabase
    .from('school_memberships')
    .select('*', { count: 'exact', head: true })
    .eq('role', 'platform_owner')
    .eq('is_active', true);
  if ((count ?? 0) > 0) {
    console.error('Refusing: a platform owner already exists. Bootstrap is disabled after first use.');
    process.exit(1);
  }

  // 2. Create school (or reuse by code)
  let schoolId;
  const { data: existing } = await supabase
    .from('schools')
    .select('id')
    .eq('code', process.env.BOOTSTRAP_SCHOOL_CODE)
    .maybeSingle();
  if (existing) {
    schoolId = existing.id;
    console.log(`Reusing school ${process.env.BOOTSTRAP_SCHOOL_CODE} (${schoolId})`);
  } else {
    const { data, error } = await supabase
      .from('schools')
      .insert({ name: process.env.BOOTSTRAP_SCHOOL_NAME, code: process.env.BOOTSTRAP_SCHOOL_CODE })
      .select('id')
      .single();
    if (error) throw error;
    schoolId = data.id;
    await supabase.from('school_settings').insert({ school_id: schoolId });
    console.log(`Created school (${schoolId})`);
  }

  // 3. Create auth user
  const { data: created, error: createErr } = await supabase.auth.admin.createUser({
    email: process.env.BOOTSTRAP_ADMIN_EMAIL,
    password: process.env.BOOTSTRAP_ADMIN_PASSWORD,
    email_confirm: true,
  });
  if (createErr) throw createErr;
  const userId = created.user.id;

  // 4. Profile + membership
  await supabase.from('user_profiles').upsert({ id: userId, display_name: 'Platform Owner', is_active: true });
  const { error: memErr } = await supabase.from('school_memberships').insert({
    user_id: userId, school_id: schoolId, role: 'platform_owner', is_active: true,
  });
  if (memErr) throw memErr;

  await supabase.from('audit_events').insert({
    school_id: schoolId, actor_id: userId, action: 'platform.bootstrap',
    target_type: 'school', target_id: schoolId, outcome: 'success',
  });

  console.log('Bootstrap complete. Admin can now sign in to the DMS.');
  console.log('IMPORTANT: unset BOOTSTRAP_ENABLED and rotate/remove the bootstrap password workflow.');
}

main().catch((e) => { console.error('Bootstrap failed:', e.message ?? e); process.exit(1); });
