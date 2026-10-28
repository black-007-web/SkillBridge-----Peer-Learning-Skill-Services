begin;
create extension if not exists pgtap with schema extensions;
select plan(28);

select ok((select relrowsecurity from pg_class where oid = 'public.course_progress'::regclass),
  'course progress has RLS enabled');
select ok(has_table_privilege('authenticated', 'public.course_progress', 'SELECT'),
  'learners can query progress rows, subject to RLS');
select ok(not has_table_privilege('authenticated', 'public.course_progress', 'INSERT'),
  'clients cannot insert progress rows directly');
select ok(not has_table_privilege('authenticated', 'public.course_progress', 'UPDATE'),
  'clients cannot update progress rows directly');
select ok(not has_table_privilege('authenticated', 'public.course_progress', 'DELETE'),
  'clients cannot delete progress rows directly');

select ok((select relrowsecurity from pg_class where oid = 'public.user_roles'::regclass),
  'role assignments have RLS enabled');
select ok(not has_table_privilege('authenticated', 'public.user_roles', 'INSERT'),
  'clients cannot insert roles directly');
select ok(not has_table_privilege('authenticated', 'public.user_roles', 'UPDATE'),
  'clients cannot update roles directly');
select ok(not has_table_privilege('authenticated', 'public.user_roles', 'DELETE'),
  'clients cannot delete roles directly');

select ok((select relrowsecurity from pg_class where oid = 'public.audit_logs'::regclass),
  'audit records have RLS enabled');
select ok(not has_table_privilege('authenticated', 'public.audit_logs', 'INSERT'),
  'clients cannot insert audit records');
select ok(not has_table_privilege('authenticated', 'public.audit_logs', 'UPDATE'),
  'clients cannot update audit records');
select ok(not has_table_privilege('authenticated', 'public.audit_logs', 'DELETE'),
  'clients cannot delete audit records');

select ok(not has_function_privilege('anon', 'public.admin_assign_role(uuid,text,boolean,text)', 'EXECUTE'),
  'anonymous users cannot call role assignment');
select ok(has_function_privilege('authenticated', 'public.admin_assign_role(uuid,text,boolean,text)', 'EXECUTE'),
  'authenticated role assignment calls are gated by the admin function');
select ok(not has_function_privilege('anon', 'public.set_lesson_progress(uuid,boolean)', 'EXECUTE'),
  'anonymous users cannot modify lesson progress');
select ok(has_function_privilege('authenticated', 'public.set_lesson_progress(uuid,boolean)', 'EXECUTE'),
  'authenticated learners use the guarded progress function');
select ok(has_function_privilege('authenticated', 'public.course_progress_summary(uuid)', 'EXECUTE'),
  'authenticated learners can request their guarded progress summary');
select ok(has_function_privilege('authenticated', 'public.course_completed_lessons(uuid)', 'EXECUTE'),
  'authenticated learners can request their guarded completed lesson IDs');

select ok(not has_function_privilege('anon', 'public.lecturer_respond_to_course_review(uuid,text)', 'EXECUTE'),
  'anonymous users cannot respond to reviews');
select ok(has_function_privilege('authenticated', 'public.lecturer_respond_to_course_review(uuid,text)', 'EXECUTE'),
  'authenticated replies are validated by the lecturer response function');
select ok(not has_column_privilege('authenticated', 'public.course_reviews', 'lecturer_response', 'UPDATE'),
  'lecturers cannot bypass the response function with direct column updates');
select ok(has_function_privilege('authenticated', 'public.lecturer_course_insights(uuid)', 'EXECUTE'),
  'authenticated calls to lecturer insights are owner-checked');
select ok(has_function_privilege('authenticated', 'public.lecturer_course_roster(uuid)', 'EXECUTE'),
  'authenticated calls to the student roster are owner-checked');
select ok(not has_function_privilege('anon', 'public.lecturer_course_roster(uuid)', 'EXECUTE'),
  'anonymous users cannot access lecturer rosters');
select ok(has_function_privilege('anon', 'public.discover_courses(text,text,text,numeric,integer,integer)', 'EXECUTE'),
  'public course discovery is available to anonymous visitors');
select ok((select relrowsecurity from pg_class where oid = 'public.course_reviews'::regclass),
  'course reviews have RLS enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.resources'::regclass),
  'course resources have RLS enabled');

select * from finish();
rollback;
