begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

-- Fixed fixtures are isolated by the surrounding transaction and rolled back.
update public.platform_settings set edu_email_domain = 'test.edu' where singleton;
set local request.jwt.claim.role = 'service_role';
insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
  phone, phone_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at) values
  ('10000000-0000-4000-8000-000000000001','authenticated','authenticated','approved@test.edu','',now(),'+12025550101',now(),'{"provider":"email","providers":["email"]}','{"full_name":"Approved Learner"}',now(),now()),
  ('10000000-0000-4000-8000-000000000002','authenticated','authenticated','pending@test.edu','',now(),'+12025550102',now(),'{"provider":"email","providers":["email"]}','{"full_name":"Pending Learner"}',now(),now()),
  ('10000000-0000-4000-8000-000000000003','authenticated','authenticated','lecturer@test.edu','',now(),'+12025550103',now(),'{"provider":"email","providers":["email"]}','{"full_name":"Course Lecturer"}',now(),now()),
  ('10000000-0000-4000-8000-000000000004','authenticated','authenticated','other@test.edu','',now(),'+12025550104',now(),'{"provider":"email","providers":["email"]}','{"full_name":"Other Lecturer"}',now(),now()),
  ('10000000-0000-4000-8000-000000000005','authenticated','authenticated','suspended@test.edu','',now(),'+12025550105',now(),'{"provider":"email","providers":["email"]}','{"full_name":"Suspended Learner"}',now(),now()),
  ('10000000-0000-4000-8000-000000000006','authenticated','authenticated','metadata@test.edu','',now(),'+12025550106',now(),'{"provider":"email","providers":["email"],"role":"admin"}','{"full_name":"Role Metadata Attempt","role":"admin","app_role":"admin"}',now(),now());
update public.profiles set student_verification_status = 'approved'
  where id in ('10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000005');
update public.profiles set account_status = 'suspended'
  where id = '10000000-0000-4000-8000-000000000005';
insert into public.user_roles(user_id, role) values
  ('10000000-0000-4000-8000-000000000003','lecturer'),
  ('10000000-0000-4000-8000-000000000004','lecturer');
insert into public.courses(id, owner_id, title, description, category, level,
  instructor, status, visibility, is_published) values
  ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000003',
   'Public Test Course','Course for RLS tests','Testing','Beginner','Course Lecturer','published','public',true),
  ('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000003',
   'Restricted Test Course','Enrolled learners only','Testing','Beginner','Course Lecturer','published','enrolled_students',true),
  ('20000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000004',
   'Other Lecturer Draft','Private draft','Testing','Beginner','Other Lecturer','draft','enrolled_students',false);
insert into public.course_modules(id, course_id, title, position) values
  ('30000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','Module One',0),
  ('30000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000002','Private Module',0);
insert into public.lessons(id, module_id, title, body, position) values
  ('40000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001','Lesson One','Test lesson',0);
insert into public.enrollments(id, user_id, course_id, status) values
  ('50000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','active');

select plan(25);
set local role authenticated;
set local request.jwt.claim.role = 'authenticated';
set local request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';

select lives_ok($$update public.profiles
  set phone_number = '+12025550999', bio = 'Approved learner bio',
      social_links = '{"github":"https://github.com/learner"}',
      position = 'Student', skills = array['Flutter']
  where id = auth.uid()$$,
  'a verified user can save phone, bio, social links, position, and skills');
select is((select phone_verified_at from public.profiles where id = auth.uid()),
  null::timestamptz, 'changing the contact phone clears its verified timestamp');
select is((select bio from public.profiles where id = auth.uid()),
  'Approved learner bio', 'profile edits persist in the profiles row');

select is((select count(*) from public.courses where id = '20000000-0000-4000-8000-000000000001'),
  1::bigint, 'an approved learner can discover a published public course');
select is((select count(*) from public.courses where id = '20000000-0000-4000-8000-000000000002'),
  1::bigint, 'an unenrolled learner can discover a published enrollment-only course');
select is((select count(*) from public.course_modules where id = '30000000-0000-4000-8000-000000000002'),
  0::bigint, 'an unenrolled learner cannot read restricted course modules');
select lives_ok($$insert into public.enrollments(user_id,course_id,status)
  values ('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000002','active')$$,
  'an approved learner can enroll in a published enrollment-only course');
select is((select count(*) from public.course_modules where id = '30000000-0000-4000-8000-000000000002'),
  1::bigint, 'an enrolled learner can read restricted course modules');
select lives_ok($$select public.set_lesson_progress('40000000-0000-4000-8000-000000000001', true)$$,
  'an approved enrolled learner can mark an accessible lesson complete');
select is((public.course_progress_summary('20000000-0000-4000-8000-000000000001')->>'completed')::integer,
  1, 'the learner progress summary counts their completed lesson');
select throws_ok($$insert into public.user_roles(user_id,role)
  values ('10000000-0000-4000-8000-000000000001','admin')$$,
  '42501', null, 'an approved learner cannot assign a role to themselves');

set local request.jwt.claim.sub = '10000000-0000-4000-8000-000000000002';
select throws_ok($$insert into public.enrollments(user_id,course_id,status)
  values ('10000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000001','active')$$,
  '42501', null, 'a pending learner cannot enroll');
select throws_ok($$select public.set_lesson_progress('40000000-0000-4000-8000-000000000001', true)$$,
  'P0001', 'Approved student access required', 'a pending learner cannot record progress');

set local request.jwt.claim.sub = '10000000-0000-4000-8000-000000000003';
select is((select count(*) from public.courses where id = '20000000-0000-4000-8000-000000000003'),
  0::bigint, 'a lecturer cannot see another lecturer draft');
select is((with changed as (update public.courses set title = 'Unauthorized edit'
  where id = '20000000-0000-4000-8000-000000000003' returning 1)
  select count(*) from changed), 0::bigint,
  'a lecturer cannot update a course owned by someone else');
select is((select count(*) from public.lecturer_course_roster('20000000-0000-4000-8000-000000000001')),
  1::bigint, 'a course owner can see the limited roster for their course');
select lives_ok($$update public.courses set title = 'Updated published course'
  where id = '20000000-0000-4000-8000-000000000001'$$,
  'a course owner can update published course details');
select lives_ok($$update public.course_modules set title = 'Updated module'
  where id = '30000000-0000-4000-8000-000000000001'$$,
  'a course owner can update published course content');
select lives_ok($$insert into public.course_modules(course_id, title, position)
  values ('20000000-0000-4000-8000-000000000001','New module',1)$$,
  'a course owner can add content to a published course');
select lives_ok($$insert into public.resources(course_id, title, resource_type,
  storage_path, file_size_bytes, created_by)
  values ('20000000-0000-4000-8000-000000000001','Course PDF','pdf',
    '20000000-0000-4000-8000-000000000001/10000000-0000-4000-8000-000000000003/course.pdf',
    100, auth.uid())$$,
  'a course owner can save resource metadata for an uploaded file');
select throws_ok($$select public.lecturer_course_roster('20000000-0000-4000-8000-000000000003')$$,
  'P0001', 'Verified course owner access required', 'a lecturer cannot read another lecturer roster');

set local request.jwt.claim.sub = '10000000-0000-4000-8000-000000000005';
select throws_ok($$select public.set_lesson_progress('40000000-0000-4000-8000-000000000001', true)$$,
  'P0001', 'Approved student access required', 'a suspended learner cannot record course progress');

set local request.jwt.claim.sub = '10000000-0000-4000-8000-000000000006';
select ok(not public.has_app_role('10000000-0000-4000-8000-000000000006', 'admin'),
  'signup role metadata cannot promote an account to administrator');

reset role;
set local role anon;
set local request.jwt.claim.role = 'anon';
select is((select count(*) from public.discover_courses('', null, null, null, 24, 0) d
  where d.course->>'id' = '20000000-0000-4000-8000-000000000001'),
  1::bigint, 'anonymous discovery returns a published public course');
select is((select count(*) from public.discover_courses('', null, null, null, 24, 0) d
  where d.course->>'id' = '20000000-0000-4000-8000-000000000002'),
  1::bigint, 'anonymous discovery includes published enrollment-only courses');
reset role;
select * from finish();
rollback;
