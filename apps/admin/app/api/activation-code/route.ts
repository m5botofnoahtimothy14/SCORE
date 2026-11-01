import { randomBytes } from 'crypto'
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
  const { data: issued, error } = await supabase.rpc('issue_student_code', {
    p_student_id: studentId,
    p_plain_code: code,
    p_days_valid: 7,
  })
  if (error || !issued?.success) {
    const reason = issued?.error?.toString()
    const status = reason === 'forbidden' ? 403 : reason === 'student_not_found' ? 404 : 500
    return NextResponse.json({ success: false, error: reason ?? 'issue_failed' }, { status })
  }
  const expiresAt = issued.expires_at as string

  // The code is already valid at this point. An audit failure must not turn
  // a working code into a client-visible error, so it is reported but not
  // fatal.
  try {
    await logAudit(admin, user.id, {
      schoolId: (student as { school_id: string }).school_id,
      action: 'enrollment.code.issued',
      targetType: 'student',
      targetId: studentId,
      outcome: 'success',
    })
  } catch (e) {
    console.error('audit write failed for enrollment.code.issued:', e)
  }

  return NextResponse.json({ success: true, code, expires_at: expiresAt })
}
