import { NextResponse, type NextRequest } from 'next/server'
import { createServerClient } from '@supabase/ssr'

export async function middleware(request: NextRequest) {
  let supabaseResponse = NextResponse.next({ request })

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll()
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value))
          supabaseResponse = NextResponse.next({ request })
          cookiesToSet.forEach(({ name, value, options }) =>
            supabaseResponse.cookies.set(name, value, options)
          )
        },
      },
    }
  )

  // IMPORTANT: No code between createServerClient and auth.getUser()
  const { data: { user } } = await supabase.auth.getUser()

  const { pathname } = request.nextUrl

  // Allow auth routes
  if (pathname.startsWith('/auth')) {
    if (user) {
      // Already logged in — redirect to dashboard
      return NextResponse.redirect(new URL('/dashboard', request.url))
    }
    return supabaseResponse
  }

  // Protect all dashboard routes
  if (!user) {
    return NextResponse.redirect(new URL('/auth/login', request.url))
  }

  // Verify user has admin/school_admin role
  // (This is a secondary check — RLS is the primary security layer)
  const { data: membership } = await supabase
    .from('school_memberships')
    .select('role')
    .eq('user_id', user.id)
    .eq('is_active', true)
    .in('role', ['platform_owner', 'school_admin', 'principal'])
    .limit(1)
    .maybeSingle()

  if (!membership) {
    // User exists but has no admin role — forbidden
    await supabase.auth.signOut()
    return NextResponse.redirect(new URL('/auth/login?error=insufficient_permissions', request.url))
  }

  return supabaseResponse
}

export const config = {
  matcher: [
    '/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)',
  ],
}
