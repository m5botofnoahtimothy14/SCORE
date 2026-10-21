import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { invokeAsService } from '@/lib/supabase/server'
import { ADMIN_ROLES } from '@/lib/auth'

// POST /api/ml-scoring/run — recompute the moderation quality snapshot.
//
// The scoring itself runs in the `score-moderation` edge function (it needs
// the service role to read moderation_results and review cases). This route
// only authorises the caller and forwards the request.
export async function POST() {
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
    .in('role', ADMIN_ROLES)
    .limit(1)
    .maybeSingle()

  if (!membership) {
    return NextResponse.json({ error: 'forbidden' }, { status: 403 })
  }

  const { data, error } = await invokeAsService('score-moderation', {
    school_id: (membership as { school_id: string }).school_id,
  })

  if (error) {
    return NextResponse.json(
      { error: 'scoring_failed', detail: error.message },
      { status: 502 },
    )
  }

  return NextResponse.json({ success: true, result: data })
}
