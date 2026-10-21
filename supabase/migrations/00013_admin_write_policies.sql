-- ============================================================
-- TeachCross: Migration 00013 — Restore write policies used by the DMS
-- ============================================================
-- Two tables were read/updated by the admin dashboard but had no INSERT
-- policy, so client-side writes were silently rejected by RLS:
--   * audit_events       - every privileged mutation writes an audit row
--                          (lib/audit.ts throws when it fails, so the UI
--                          reported a false failure after the real mutation
--                          had already succeeded).
--   * school_settings    - creating a school inserts its settings row;
--                          without this the Settings page 404s for new schools.
-- ============================================================

-- AUDIT_EVENTS - append-only audit trail. Admins may append rows for their
-- own school, and only as themselves (actor_id must be the caller).
-- tc_is_school_admin() implicitly allows platform_owner for every school.
DROP POLICY IF EXISTS audit_events_insert ON audit_events;
DROP POLICY IF EXISTS audit_events_insert ON audit_events;
CREATE POLICY audit_events_insert ON audit_events FOR INSERT
  WITH CHECK (
    actor_id = auth.uid()
    AND public.tc_is_school_admin(school_id)
  );

-- SCHOOL_SETTINGS - admins of the school may create the settings row.
DROP POLICY IF EXISTS school_settings_insert ON school_settings;
DROP POLICY IF EXISTS school_settings_insert ON school_settings;
CREATE POLICY school_settings_insert ON school_settings FOR INSERT
  WITH CHECK (public.tc_is_school_admin(school_id));
