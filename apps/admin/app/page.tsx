import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'

// Root: send signed-in admins to the dashboard, everyone else to login.
export default async function Home() {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (user) redirect('/dashboard')
  redirect('/auth/login')
}
