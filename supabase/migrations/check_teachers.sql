SELECT count(*) as teacher_count FROM teachers;
SELECT count(*) as cred_count FROM teacher_activation_credentials;
SELECT id, staff_id_no, first_name, last_name, is_active, user_id FROM teachers LIMIT 5;