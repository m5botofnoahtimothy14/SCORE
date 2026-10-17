-- ============================================================
-- TeachCross: live-backend RLS / enforcement checks (staging only).
-- Run as an UNPRIVILEGED test user via psql after `supabase db push`
-- and seed.dev.sql. Every check documents the expected outcome.
-- Replace <TEST_JWT_*> with tokens of a student / teacher / outsider.
-- ============================================================

-- How to run (example):
--   psql "$DATABASE_URL" -v student_jwt='<JWT>' -f tests/rls_checks.sql

-- 0. Sanity: tables exist ------------------------------------------------
SELECT 'schools' AS tbl, count(*) FROM schools;

-- 1. Student sees ONLY their own student row ------------------------------
-- SET LOCAL request.jwt.claims ... (via authenticated REST is preferred)
-- Expect: SELECT * FROM students returns exactly 1 row for the test student.
-- (Execute as student JWT:)
--   SELECT count(*) FROM students;  -- must equal 1

-- 2. Student cannot SELECT another school's classes -------------------------
--   SELECT * FROM classes WHERE school_id = '<OTHER_SCHOOL>'; -- 0 rows

-- 3. Student INSERT into messages in a foreign conversation fails -----------
--   INSERT INTO messages(idempotency_key, conversation_id, school_id, sender_id, body)
--   VALUES ('check-1', '<FOREIGN_CONV>', '<S1>', auth.uid(), 'x'); -- ERROR (RLS)

-- 4. Forged sender_id fails -------------------------------------------------
--   INSERT INTO messages(idempotency_key, conversation_id, school_id, sender_id, body)
--   VALUES ('check-2', '<OWN_CONV>', '<S1>', '<OTHER_USER>', 'x'); -- ERROR (RLS)

-- 5. Audit table is read-only for app roles ----------------------------------
--   UPDATE audit_events SET outcome='tampered'; -- 0 rows / ERROR (no policy)
--   DELETE FROM audit_events;                  -- 0 rows / ERROR (no policy)

-- 6. Teacher cannot read unassigned student's row -----------------------------
--   (as teacher JWT) SELECT * FROM students WHERE id='<UNASSIGNED>'; -- 0 rows

-- 7. Announcements: student sees only rows where they are a recipient --------
--   SELECT * FROM announcements; -- only published + recipient rows

-- 8. Storage: anonymous GET on attachments object URL returns 403/404 ---------
--   (verify via curl with anon key against a known private path)

-- Record results in docs/TESTING.md evidence table before release.
SELECT 'rls_checks.sql loaded — execute numbered checks as documented' AS status;
