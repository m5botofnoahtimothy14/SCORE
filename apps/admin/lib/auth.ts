import { redirect } from 'next/navigation'
import { createClient } from './supabase/server'

// ── Two-tier administration ──────────────────────────────────
//   Super Admin  = platform_owner — the platform owner (Noah Timothy
//                  Keba Joseph). Full data + control across every school.
//   Admin        = school_admin / principal — a school's IT head.
//                  Scoped to their own school by RLS.
export type AdminRole = 'platform_owner' | 'school_admin' | 'principal'

export const ADMIN_ROLES: AdminRole[] = ['platform_owner', 'school_admin', 'principal']

export type AdminTier = 'super_admin' | 'admin'

export function tierOf(role: string): AdminTier {
  return role === 'platform_owner' ? 'super_admin' : 'admin'
}

export function roleLabel(role: string): string {
  switch (role) {
    case 'platform_owner':
      return 'Super Admin'
    case 'school_admin':
      return 'Admin'
    case 'principal':
      return 'Principal'
    default:
      return role
  }
}

export interface AdminContext {
  userId: string
  email?: string
  role: AdminRole
  tier: AdminTier
  schoolId: string
  schoolName: string
  schoolCode: string
  isPlatformOwner: boolean
  isSuperAdmin: boolean
  isSchoolAdmin: boolean
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
    .in('role', ADMIN_ROLES)
    .order('joined_at', { ascending: false })
    .limit(1)
    .maybeSingle()

  if (!membership) redirect('/auth/login?error=insufficient_permissions')

  const role = membership.role as AdminRole
  const school = membership.schools as unknown as { id: string; name: string; code: string }
  return {
    userId: user.id,
    email: user.email,
    role,
    tier: tierOf(role),
    schoolId: membership.school_id as string,
    schoolName: school?.name ?? 'TeachCross',
    schoolCode: school?.code ?? '',
    isPlatformOwner: role === 'platform_owner',
    isSuperAdmin: role === 'platform_owner',
    isSchoolAdmin: role === 'school_admin' || role === 'principal',
  }
}

// Super-Admin-only operations (platform-wide data + control).
export async function requireSuperAdmin(): Promise<AdminContext> {
  const ctx = await getAdminContext()
  if (!ctx.isSuperAdmin) redirect('/dashboard?error=forbidden')
  return ctx
}

// Back-compat alias.
export const requirePlatformOwner = requireSuperAdmin
