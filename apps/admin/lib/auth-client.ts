// Client-safe admin constants (no server-side imports).
export type AdminRole = 'platform_owner' | 'school_admin' | 'principal'

export const ADMIN_ROLES: AdminRole[] = ['platform_owner', 'school_admin', 'principal']

export type AdminTier = 'super_admin' | 'admin'

export function tierOf(role: string): AdminTier {
  return role === 'platform_owner' ? 'super_admin' : 'admin'
}

export function roleLabel(role: string): string {
  switch (role) {
    case 'platform_owner': return 'Super Admin'
    case 'school_admin': return 'Admin'
    case 'principal': return 'Principal'
    default: return role
  }
}
