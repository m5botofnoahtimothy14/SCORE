import { redirect } from 'next/navigation'
import { createClient } from './supabase/server'

export type AdminRole = 'platform_owner' | 'school_admin' | 'principal'

export interface AdminContext {
  userId: string
  email?: string
  role: AdminRole
  schoolId: string
  schoolName: string
  schoolCode: string
  isPlatformOwner: boolean
}

// Server-side gate: signed in + holds an admin role. Redirects otherwise.
export async function getAdminContext(): Promise<AdminContext> {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) redirect('/auth/login')

  const { data: membership } = await supabase
    .from('school_memberships')
    .select('role, school_id, schools(id, name, code)')
    .eq('user_id', user.id)
    .eq('is_active', true)
    .in('role', ['platform_owner', 'school_admin', 'principal'])
    .order('joined_at', { ascending: false })
    .limit(1)
    .maybeSingle()

  if (!membership) redirect('/auth/login?error=insufficient_permissions')

  const school = membership.schools as unknown as { id: string; name: string; code: string }
  return {
    userId: user.id,
    email: user.email,
    role: membership.role as AdminRole,
    schoolId: membership.school_id as string,
    schoolName: school?.name ?? 'TeachCross',
    schoolCode: school?.code ?? '',
    isPlatformOwner: membership.role === 'platform_owner',
  }
}

// Require platform ownership for platform-only operations.
export async function requirePlatformOwner(): Promise<AdminContext> {
  const ctx = await getAdminContext()
  if (!ctx.isPlatformOwner) redirect('/dashboard?error=forbidden')
  return ctx
}
