SELECT count(*) as subject_count FROM subjects WHERE lower(name) IN ('chemistry', 'physics', 'biology');
SELECT count(*) as enrollment_count FROM student_subject_enrollments;