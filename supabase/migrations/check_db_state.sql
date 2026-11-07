SELECT count(*) as subject_count, name FROM subjects WHERE lower(name) IN ('chemistry', 'physics', 'biology') GROUP BY name;
SELECT count(*) as enrollment_count FROM class_enrollments WHERE unenrolled_at IS NULL;
SELECT count(*) as student_count FROM students WHERE is_active = TRUE;