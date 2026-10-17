import { requireSuperAdmin } from '@/lib/auth'
import { AdminsClient } from './admins-client'

// Super Admin only — manage school IT-head "Admin" accounts.
export default async function AdminsPage() {
  await requireSuperAdmin()
  return <AdminsClient />
}
