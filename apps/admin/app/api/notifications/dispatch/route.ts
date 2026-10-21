import { NextResponse } from 'next/server'
import { createClient, invokeAsService } from '@/lib/supabase/server'

// POST /api/notifications/dispatch
// Drains pending notification_jobs for the caller's school through the
// dispatch-notifications edge function. Server-only: invokes with the
// service-role token, which the function trusts. Returns the real result
// so the UI never reports a fake success.
export async function POST() {
  try {
    const supabase = await createClient()
    const {
      data: { user },
    } = await supabase.auth.getUser()
    if (!user) return NextResponse.json({ error: 'unauthorized' }, { status: 401 })

    const { data: membership } = await supabase
      .from('school_memberships')
      .select('role, school_id')
      .eq('user_id', user.id)
      .eq('is_active', true)
      .in('role', ['platform_owner', 'school_admin', 'principal'])
      .order('joined_at', { ascending: true })
      .limit(1)
      .maybeSingle()
    if (!membership) return NextResponse.json({ error: 'forbidden' }, { status: 403 })

    const schoolId = (membership as { school_id: string }).school_id
    const { data, error } = await invokeAsService('dispatch-notifications', {
      school_id: schoolId,
    })
    if (error) {
      return NextResponse.json({ error: 'dispatch_failed', detail: error.message }, { status: 502 })
    }
    return NextResponse.json({ ok: true, result: data })
  } catch (e) {
    return NextResponse.json(
      { error: 'dispatch_failed', detail: e instanceof Error ? e.message : 'unknown error' },
      { status: 500 },
    )
  }
}
