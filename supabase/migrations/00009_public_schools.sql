-- ============================================================
-- Migration 00009 — Public school directory (unauthenticated discovery)
-- The enrollment flow needs school identification BEFORE any session
-- exists. Expose ONLY non-sensitive columns through a dedicated view
-- running as the table owner; the base `schools` table (phone, email)
-- stays RLS-protected with no anon access.
-- ============================================================

CREATE OR REPLACE VIEW public.public_schools AS
SELECT id, name, code, city, state, logo_url
FROM public.schools
WHERE is_active = TRUE;

-- Views run with owner privileges (not security_invoker), so this is a
-- deliberate, column-restricted public surface. Tighten by revoking and
-- re-granting explicitly.
REVOKE ALL ON public.public_schools FROM PUBLIC;
GRANT SELECT ON public.public_schools TO anon, authenticated;
