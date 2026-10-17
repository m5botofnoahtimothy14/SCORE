'use client'

import { LogOut } from 'lucide-react'

export function LogoutButton() {
  const handleLogout = async () => {
    const { createClient } = await import('@/lib/supabase/client')
    const supabase = createClient()
    await supabase.auth.signOut()
    window.location.href = '/auth/login'
  }
  return (
    <button onClick={handleLogout} className="text-slate-500 hover:text-red-400 transition-colors" title="Sign out">
      <LogOut className="w-4 h-4" />
    </button>
  )
}
