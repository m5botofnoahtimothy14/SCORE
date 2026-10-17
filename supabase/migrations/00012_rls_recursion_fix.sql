-- ============================================================
-- TeachCross: Migration 00012 — Fix RLS infinite recursion (42P17)
-- ============================================================
-- Two policy families cross-referenced each other, so Postgres
-- aborted every read with "infinite recursion detected":
--   * students  <-> class_enrollments
--   * announcements <-> announcement_recipients / _receipts
-- Fix: move the cross-table lookups into SECURITY DEFINER helper
-- functions (which run as the table owner and bypass RLS), then
-- rebuild the offending policies to call those helpers.
--
-- Also: a platform_owner is a global super admin — treat them as a
-- school admin for every school, so the DMS can see all data.
-- ============================================================

-- 1. Platform owner == school admin everywhere.
CREATE OR REPLACE FUNCTION public.tc_is_school_admin(p_school_id UUID)
RETURNS BOOLEAN AS $$
  SELECT public.tc_is_platform_owner()
      OR EXISTS (
        SELECT 1 FROM school_memberships
        WHERE user_id = auth.uid()
          AND school_id = p_school_id
          AND role IN ('school_admin', 'principal')
          AND is_active = TRUE
      )
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- 2. Student-set helpers (break students <-> class_enrollments).
CREATE OR REPLACE FUNCTION public.tc_my_student_ids()
RETURNS UUID[] AS $$
  SELECT COALESCE(ARRAY(SELECT id FROM students WHERE user_id = auth.uid()), '{}'::UUID[])
$$ LANGUAGE sql STABLE SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.tc_taught_student_ids()
RETURNS UUID[] AS $$
  SELECT COALESCE(ARRAY(
    SELECT ce.student_id
    FROM class_enrollments ce
    JOIN teaching_assignments ta ON ta.class_id = ce.class_id
    JOIN teachers t ON t.id = ta.teacher_id
    WHERE t.user_id = auth.uid() AND ce.unenrolled_at IS NULL
  ), '{}')
$$ LANGUAGE sql STABLE SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.tc_my_taught_class_ids()
RETURNS UUID[] AS $$
  SELECT COALESCE(ARRAY(
    SELECT DISTINCT ta.class_id
    FROM teaching_assignments ta
    JOIN teachers t ON t.id = ta.teacher_id
    WHERE t.user_id = auth.uid()
  ), '{}')
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- 3. Announcement helpers (break announcements <-> announcement_recipients).
CREATE OR REPLACE FUNCTION public.tc_is_announcement_recipient(p_announcement_id UUID)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM announcement_recipients
    WHERE announcement_id = p_announcement_id AND user_id = auth.uid()
  )
$$ LANGUAGE sql STABLE SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.tc_school_id_of_announcement(p_announcement_id UUID)
RETURNS UUID AS $$
  SELECT school_id FROM announcements WHERE id = p_announcement_id
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- 3b. Class id of an enrollment (keeps teacher view non-recursive).
CREATE OR REPLACE FUNCTION public.tc_is_student_in_my_class(p_student_id UUID)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1
    FROM class_enrollments ce
    JOIN teaching_assignments ta ON ta.class_id = ce.class_id
    JOIN teachers t ON t.id = ta.teacher_id
    WHERE ce.student_id = p_student_id
      AND t.user_id = auth.uid()
      AND ce.unenrolled_at IS NULL
  )
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- 4. Rebuild students policies.
DROP POLICY IF EXISTS students_teacher_view ON students;
CREATE POLICY students_teacher_view ON students FOR SELECT
  USING (
    school_id = ANY(public.tc_user_school_ids())
    AND public.tc_is_student_in_my_class(id)
  );

-- 5. Rebuild class_enrollments policies.
DROP POLICY IF EXISTS class_enrollments_teacher ON class_enrollments;
CREATE POLICY class_enrollments_teacher ON class_enrollments FOR SELECT
  USING (class_id = ANY(public.tc_my_taught_class_ids()));

DROP POLICY IF EXISTS class_enrollments_student ON class_enrollments;
CREATE POLICY class_enrollments_student ON class_enrollments FOR SELECT
  USING (student_id = ANY(public.tc_my_student_ids()));

-- 6. Rebuild announcements.
DROP POLICY IF EXISTS announcements_recipient ON announcements;
CREATE POLICY announcements_recipient ON announcements FOR SELECT
  USING (is_published = TRUE AND public.tc_is_announcement_recipient(id));

-- 7. Rebuild announcement_recipients admin policy.
DROP POLICY IF EXISTS ann_recipients_admin ON announcement_recipients;
CREATE POLICY ann_recipients_admin ON announcement_recipients FOR ALL
  USING (public.tc_is_school_admin(public.tc_school_id_of_announcement(announcement_id)));

-- 8. Rebuild announcement_receipts admin policy.
DROP POLICY IF EXISTS ann_receipts_admin ON announcement_receipts;
CREATE POLICY ann_receipts_admin ON announcement_receipts FOR SELECT
  USING (public.tc_is_school_admin(public.tc_school_id_of_announcement(announcement_id)));
