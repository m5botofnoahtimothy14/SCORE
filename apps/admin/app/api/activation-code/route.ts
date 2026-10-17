import { createHash, randomBytes } from 'crypto'
import { NextResponse } from 'next/server'
import { createClient, createServiceClient } from '@/lib/supabase/server'
import { logAudit } from '@/lib/audit'

// POST /api/activation-code { student_id } — issue/rotate a one-time
// student activation code. Code is shown ONCE in the response; only its
// SHA-256 hash is stored (verified server-side by activate_student()).
export async function POST(req: Request) {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ success: false, error: 'unauthorized' }, { status: 401 })

  let studentId: string | undefined
  try {
    studentId = (await req.json()).student_id
  } catch {
    return NextResponse.json({ success: false, error: 'invalid_body' }, { status: 400 })
  }
  if (!studentId) return NextResponse.json({ success: false, error: 'missing student_id' }, { status: 400 })

  const admin = createServiceClient()
  const { data: student } = await admin.from('students').select('id, school_id').eq('id', studentId).maybeSingle()
  if (!student) return NextResponse.json({ success: false, error: 'not_found' }, { status: 404 })

  // Caller must administer THIS school.
  const { data: membership } = await supabase
    .from('school_memberships')
    .select('role')
    .eq('user_id', user.id)
    .eq('school_id', (student as { school_id: string }).school_id)
    .eq('is_active', true)
    .in('role', ['platform_owner', 'school_admin', 'principal'])
    .limit(1)
    .maybeSingle()
  if (!membership) return NextResponse.json({ success: false, error: 'forbidden' }, { status: 403 })

  const code = randomBytes(4).toString('hex').toUpperCase() // 8 chars, shown once
  const hash = createHash('sha256').update(code).digest('hex')
  const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString()

  const { error } = await admin.from('student_activation_credentials').upsert(
    {
      school_id: (student as { school_id: string }).school_id,
      student_id: studentId,
      code: hash,
      expires_at: expiresAt,
      used_at: null,
      created_by: user.id,
    },
    { onConflict: 'student_id' }
  )
  if (error) return NextResponse.json({ success: false, error: 'issue_failed' }, { status: 500 })

  await logAudit(admin, user.id, {
    schoolId: (student as { school_id: string }).school_id,
    action: 'enrollment.code.issued',
    targetType: 'student',
    targetId: studentId,
    outcome: 'success',
  })

  return NextResponse.json({ success: true, code, expires_at: expiresAt })
}
