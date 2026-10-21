import { NextResponse } from 'next/server'
import { createClient, createServiceClient } from '@/lib/supabase/server'
import { logAudit } from '@/lib/audit'
import { ADMIN_ROLES } from '@/lib/auth'

// Super-Admin only: manage the school "Admin" (IT head) accounts.
// Every handler re-checks the caller's role server-side — the service
// client bypasses RLS, so this is the authorization boundary.
async function requireSuperAdmin() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: NextResponse.json({ error: 'unauthorized' }, { status: 401 }) }

  const { data: membership } = await supabase
    .from('school_memberships')
    .select('role')
    .eq('user_id', user.id)
    .eq('role', 'platform_owner')
    .eq('is_active', true)
    .limit(1)
    .maybeSingle()

  if (!membership) return { error: NextResponse.json({ error: 'forbidden' }, { status: 403 }) }
  return { user }
}

// GET /api/admins — all admin-role memberships with email + school.
export async function GET() {
  const gate = await requireSuperAdmin()
  if ('error' in gate) return gate.error

  const admin = createServiceClient()
  const { data: memberships, error } = await admin
    .from('school_memberships')
    .select('id, role, is_active, user_id, school_id, user_profiles(display_name), schools(name, code)')
    .in('role', ADMIN_ROLES)
    .order('joined_at', { ascending: false })
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  // Map user ids to emails. If the auth listing fails the rows are still
  // returned — the failure is reported instead of silently blanking emails.
  const emailById = new Map<string, string>()
  let emailLookupFailed = false
  try {
    let page = 1
    for (;;) {
      const { data: usersPage, error: usersErr } = await admin.auth.admin.listUsers({
        page,
        perPage: 1000,
      })
      if (usersErr) throw new Error(usersErr.message)
      for (const u of usersPage?.users ?? []) emailById.set(u.id, u.email ?? '')
      const total = usersPage?.total ?? 0
      if ((usersPage?.users?.length ?? 0) === 0 || page * 1000 >= total) break
      page += 1
    }
  } catch (e) {
    emailLookupFailed = true
    console.error('admin listUsers failed:', e)
  }

  const list = (memberships ?? []).map((m) => {
    const profile = m.user_profiles as unknown as { display_name: string } | { display_name: string }[] | null
    const school = m.schools as unknown as { name: string; code: string } | { name: string; code: string }[] | null
    const p = Array.isArray(profile) ? profile[0] : profile
    const s = Array.isArray(school) ? school[0] : school
    return {
      id: m.id as string,
      user_id: m.user_id as string,
      role: m.role as string,
      is_active: m.is_active as boolean,
      school_id: m.school_id as string,
      school_name: s?.name ?? '—',
      school_code: s?.code ?? '',
      display_name: p?.display_name ?? '',
      email: emailById.get(m.user_id as string) ?? '',
    }
  })
  return NextResponse.json({ admins: list, email_lookup_failed: emailLookupFailed })
}

// POST /api/admins — create a school Admin (auth user + profile + membership).
export async function POST(request: Request) {
  const gate = await requireSuperAdmin()
  if ('error' in gate) return gate.error
  const actor = gate.user

  const body = await request.json().catch(() => null)
  const email = typeof body?.email === 'string' ? body.email.trim().toLowerCase() : ''
  const password = typeof body?.password === 'string' ? body.password : ''
  const displayName = typeof body?.display_name === 'string' ? body.display_name.trim() : ''
  const schoolId = typeof body?.school_id === 'string' ? body.school_id : ''
  const role = body?.role === 'principal' ? 'principal' : 'school_admin'

  if (!email || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    return NextResponse.json({ error: 'invalid_email' }, { status: 400 })
  }
  if (password.length < 8) {
    return NextResponse.json({ error: 'weak_password' }, { status: 400 })
  }
  if (!schoolId) return NextResponse.json({ error: 'missing_school' }, { status: 400 })

  const admin = createServiceClient()

  const { data: school } = await admin.from('schools').select('id, name').eq('id', schoolId).maybeSingle()
  if (!school) return NextResponse.json({ error: 'school_not_found' }, { status: 404 })

  // Create the auth user (email pre-confirmed — the school signs them in).
  const { data: created, error: authErr } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { display_name: displayName || email },
  })
  if (authErr || !created.user) {
    const msg = authErr?.message ?? 'create_failed'
    const status = /already/i.test(msg) ? 409 : 500
    return NextResponse.json({ error: msg }, { status })
  }
  const userId = created.user.id

  // From here on a failure must not leave an orphaned auth user behind —
  // the address would be taken with no admin provisioned.
  const { error: profileErr } = await admin
    .from('user_profiles')
    .upsert({ id: userId, display_name: displayName || email.split('@')[0], is_active: true }, { onConflict: 'id' })
  if (profileErr) {
    await admin.auth.admin.deleteUser(userId).catch(() => undefined)
    return NextResponse.json({ error: profileErr.message }, { status: 500 })
  }

  const { error: memberErr } = await admin
    .from('school_memberships')
    .insert({ user_id: userId, school_id: schoolId, role, is_active: true })
  if (memberErr) {
    // Roll back the profile and the auth user so the admin can be retried.
    await admin.from('user_profiles').delete().eq('id', userId)
    await admin.auth.admin.deleteUser(userId).catch(() => undefined)
    return NextResponse.json({ error: memberErr.message }, { status: 500 })
  }

  try {
    await logAudit(admin, actor.id, {
      schoolId,
      action: 'admin.create',
      targetType: 'user',
      targetId: userId,
      outcome: 'success',
      metadata: { email, role, school: school.name },
    })
  } catch (e) {
    console.error('audit write failed for admin.create:', e)
  }

  return NextResponse.json({ success: true, user_id: userId })
}

// PATCH /api/admins { id, is_active } — enable/disable a membership.
export async function PATCH(request: Request) {
  const gate = await requireSuperAdmin()
  if ('error' in gate) return gate.error
  const actor = gate.user

  const body = await request.json().catch(() => null)
  const id = typeof body?.id === 'string' ? body.id : ''
  if (!id) return NextResponse.json({ error: 'missing_id' }, { status: 400 })

  const admin = createServiceClient()
  const { data: target } = await admin
    .from('school_memberships')
    .select('id, role, user_id, school_id, is_active')
    .eq('id', id)
    .maybeSingle()
  if (!target) return NextResponse.json({ error: 'not_found' }, { status: 404 })
  if (target.role === 'platform_owner') {
    return NextResponse.json({ error: 'cannot_modify_owner' }, { status: 400 })
  }

  const isActive = typeof body?.is_active === 'boolean' ? body.is_active : !target.is_active
  const { error } = await admin.from('school_memberships').update({ is_active: isActive }).eq('id', id)
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  // Suspending an admin must also lock them out of Supabase Auth, otherwise
  // the account stays live (the membership check would reject them, but the
  // credential would still be valid).
  if (!isActive) {
    try {
      await admin.auth.admin.updateUserById(target.user_id as string, {
        ban_duration: '876000h',
      })
    } catch (e) {
      console.error('failed to ban auth user:', e)
    }
  } else {
    try {
      await admin.auth.admin.updateUserById(target.user_id as string, { ban_duration: 'none' })
    } catch (e) {
      console.error('failed to unban auth user:', e)
    }
  }

  try {
    await logAudit(admin, actor.id, {
      schoolId: target.school_id as string,
      action: isActive ? 'admin.reactivate' : 'admin.deactivate',
      targetType: 'user',
      targetId: target.user_id as string,
      outcome: 'success',
    })
  } catch (e) {
    console.error('audit write failed for admin.deactivate:', e)
  }

  return NextResponse.json({ success: true, is_active: isActive })
}
