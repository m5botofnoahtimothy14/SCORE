import { createHash, randomBytes } from 'crypto'
import { NextResponse } from 'next/server'
import { createClient, createServiceClient } from '@/lib/supabase/server'
import { logAudit } from '@/lib/audit'

export async function POST(req: Request) {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ success: false, error: 'unauthorized' }, { status: 401 })

  let teacherId: string | undefined
  try {
    teacherId = (await req.json()).teacher_id
  } catch {
    return NextResponse.json({ success: false, error: 'invalid_body' }, { status: 400 })
  }
  if (!teacherId) return NextResponse.json({ success: false, error: 'missing teacher_id' }, { status: 400 })

  const admin = createServiceClient()
  const { data: teacher } = await admin.from('teachers').select('id, school_id').eq('id', teacherId).maybeSingle()
  if (!teacher) return NextResponse.json({ success: false, error: 'not_found' }, { status: 404 })

  const { data: membership } = await supabase
    .from('school_memberships')
    .select('role')
    .eq('user_id', user.id)
    .eq('school_id', (teacher as { school_id: string }).school_id)
    .eq('is_active', true)
    .in('role', ['platform_owner', 'school_admin', 'principal'])
    .limit(1)
    .maybeSingle()
  if (!membership) return NextResponse.json({ success: false, error: 'forbidden' }, { status: 403 })

  const code = randomBytes(4).toString('hex').toUpperCase()
  const hash = createHash('sha256').update(code).digest('hex')
  const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString()

  const { error } = await admin.from('teacher_activation_credentials').upsert(
    {
      school_id: (teacher as { school_id: string }).school_id,
      teacher_id: teacherId,
      code: hash,
      expires_at: expiresAt,
      used_at: null,
      created_by: user.id,
    },
    { onConflict: 'teacher_id' }
  )
  if (error) return NextResponse.json({ success: false, error: 'issue_failed' }, { status: 500 })

  try {
    await logAudit(admin, user.id, {
      schoolId: (teacher as { school_id: string }).school_id,
      action: 'enrollment.code.issued',
      targetType: 'teacher',
      targetId: teacherId,
      outcome: 'success',
    })
  } catch (e) {
    console.error('audit write failed for teacher enrollment.code.issued:', e)
  }

  return NextResponse.json({ success: true, code, expires_at: expiresAt })
}