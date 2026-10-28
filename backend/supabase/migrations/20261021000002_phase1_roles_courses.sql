-- Phase 1: role approval, course ownership/lifecycle, learning content,
-- reviews, announcements, support, and audit foundations.

alter table public.profiles
  add column if not exists account_status text not null default 'active',
  add column if not exists student_verification_status text not null default 'pending';
alter table public.profiles drop constraint if exists profiles_account_status_check;
alter table public.profiles add constraint profiles_account_status_check
  check (account_status in ('active', 'suspended', 'deactivated'));
alter table public.profiles drop constraint if exists profiles_student_verification_status_check;
alter table public.profiles add constraint profiles_student_verification_status_check
  check (student_verification_status in ('pending', 'approved', 'rejected'));

create or replace function public.has_app_role(p_user_id uuid, p_role text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.user_roles r
    where r.user_id = p_user_id and r.role = p_role
      and (p_user_id = (select auth.uid()) or exists (
        select 1 from public.user_roles ar join public.profiles ap on ap.id = ar.user_id
        where ar.user_id = (select auth.uid()) and ar.role = 'admin' and ap.account_status = 'active'
      ))
  );
$$;
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select public.has_app_role((select auth.uid()), 'admin');
$$;
create or replace function public.is_active_user()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid()) and p.account_status = 'active'
  );
$$;
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select public.is_active_user()
    and public.has_app_role((select auth.uid()), 'admin');
$$;
create or replace function public.is_approved_student()
returns boolean language sql stable security definer set search_path = '' as $$
  select public.is_active_user()
    and public.is_verified_user()
    and public.has_app_role((select auth.uid()), 'student')
    and exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid())
        and p.student_verification_status = 'approved'
    );
$$;
revoke all on function public.has_app_role(uuid, text) from public;
revoke all on function public.is_admin() from public;
revoke all on function public.is_active_user() from public;
revoke all on function public.is_approved_student() from public;
grant execute on function public.has_app_role(uuid, text) to authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.is_admin() to anon;
grant execute on function public.is_active_user() to authenticated;
grant execute on function public.is_approved_student() to authenticated;

create policy "Admins read profile directory"
  on public.profiles for select to authenticated using (public.is_admin());
create policy "Admins read all role assignments"
  on public.user_roles for select to authenticated using (public.is_admin());

create or replace function public.admin_set_account_status(
  p_user_id uuid, p_status text, p_reason text
) returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_admin() or p_status not in ('active', 'suspended', 'deactivated') then
    raise exception 'Administrator access required or invalid account status';
  end if;
  if p_status <> 'active' and public.has_app_role(p_user_id, 'admin')
     and (select count(*) from public.user_roles r join public.profiles p on p.id = r.user_id
          where r.role = 'admin' and p.account_status = 'active') <= 1 then
    raise exception 'The last active administrator cannot be suspended or deactivated';
  end if;
  update public.profiles set account_status = p_status where id = p_user_id;
  if not found then raise exception 'User profile not found'; end if;
  insert into public.audit_logs(actor_id, action, target_type, target_id, metadata)
    values(auth.uid(), 'account_status_changed', 'user', p_user_id::text,
      jsonb_build_object('status', p_status, 'reason', left(p_reason, 500)));
end;
$$;
revoke all on function public.admin_set_account_status(uuid,text,text) from public;
grant execute on function public.admin_set_account_status(uuid,text,text) to authenticated;

create or replace function public.admin_list_users(
  p_search text default '', p_limit integer default 50, p_offset integer default 0
) returns table (
  user_id uuid, email text, full_name text, roles text[], account_status text,
  student_verification_status text, created_at timestamptz
) language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'Administrator access required'; end if;
  return query
    select u.id, u.email::text, p.full_name,
      coalesce(array(select r.role from public.user_roles r where r.user_id = u.id order by r.role), '{}'::text[]),
      p.account_status, p.student_verification_status, u.created_at
    from auth.users u join public.profiles p on p.id = u.id
    where coalesce(p_search, '') = ''
      or u.email ilike '%' || trim(p_search) || '%'
      or p.full_name ilike '%' || trim(p_search) || '%'
    order by u.created_at desc
    limit greatest(1, least(coalesce(p_limit, 50), 100))
    offset greatest(coalesce(p_offset, 0), 0);
end;
$$;
revoke all on function public.admin_list_users(text,integer,integer) from public;
grant execute on function public.admin_list_users(text,integer,integer) to authenticated;

create table public.student_verification_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  student_number text not null check (length(trim(student_number)) between 2 and 40),
  department text not null check (length(trim(department)) between 2 and 120),
  program text not null check (length(trim(program)) between 2 and 120),
  evidence_path text,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected')),
  decision_reason text,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index student_verification_one_pending_per_user
  on public.student_verification_requests(user_id) where status = 'pending';
create index student_verification_status_created_idx
  on public.student_verification_requests(status, created_at desc);

create table public.lecturer_applications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  department text not null check (length(trim(department)) between 2 and 120),
  qualifications text not null check (length(trim(qualifications)) between 10 and 4000),
  experience text not null check (length(trim(experience)) between 10 and 4000),
  evidence_path text,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected')),
  decision_reason text,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index lecturer_application_one_pending_per_user
  on public.lecturer_applications(user_id) where status = 'pending';
create index lecturer_applications_status_created_idx
  on public.lecturer_applications(status, created_at desc);

-- Keep the institution domain in trusted database configuration so public Auth
-- signup cannot bypass the Flutter-side EDU_EMAIL_DOMAIN validation.
create table public.platform_settings (
  singleton boolean primary key default true check (singleton),
  edu_email_domain text check (edu_email_domain is null or
    (edu_email_domain = lower(trim(edu_email_domain))
      and edu_email_domain ~ '^[^@[:space:]]+(\.[^@[:space:]]+)+$'))
);
insert into public.platform_settings(singleton, edu_email_domain)
values (true, null) on conflict (singleton) do nothing;
alter table public.platform_settings enable row level security;
revoke all on public.platform_settings from anon, authenticated;

create or replace function public.enforce_student_email_domain()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_domain text;
begin
  if auth.role() = 'service_role' then return new; end if;
  select edu_email_domain into v_domain from public.platform_settings where singleton;
  if v_domain is null or length(trim(v_domain)) = 0 then
    raise exception 'Institution email domain is not configured';
  end if;
  if new.email is null or right(lower(new.email), length(v_domain) + 1) <> ('@' || lower(v_domain)) then
    raise exception 'Use an email address from the configured institution domain';
  end if;
  return new;
end;
$$;
drop trigger if exists enforce_student_email_domain_before_signup on auth.users;
create trigger enforce_student_email_domain_before_signup before insert on auth.users
  for each row execute function public.enforce_student_email_domain();

create or replace function public.create_student_verification_request_for_signup()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if coalesce(new.raw_user_meta_data ->> 'student_number', '') <> ''
     and coalesce(new.raw_user_meta_data ->> 'department', '') <> ''
     and coalesce(new.raw_user_meta_data ->> 'program', '') <> '' then
    insert into public.student_verification_requests(user_id, student_number, department, program)
      values(new.id, trim(new.raw_user_meta_data ->> 'student_number'),
        trim(new.raw_user_meta_data ->> 'department'), trim(new.raw_user_meta_data ->> 'program'))
      on conflict do nothing;
  end if;
  return new;
end;
$$;
drop trigger if exists on_auth_user_created_phase1 on auth.users;
create trigger on_auth_user_created_phase1 after insert on auth.users
  for each row execute function public.create_student_verification_request_for_signup();

alter table public.courses
  add column if not exists owner_id uuid references auth.users(id) on delete set null,
  add column if not exists status text not null default 'draft',
  add column if not exists visibility text not null default 'enrolled_students',
  add column if not exists cover_image_path text,
  add column if not exists learning_outcomes text not null default '',
  add column if not exists prerequisites text not null default '',
  add column if not exists estimated_minutes integer,
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists published_at timestamptz;
update public.courses
set status = case when is_published then 'published' else 'draft' end
where status = 'draft' and is_published;
update public.courses set visibility = 'public' where status = 'published';
alter table public.courses drop constraint if exists courses_status_check;
alter table public.courses add constraint courses_status_check
  check (status in ('draft', 'submitted', 'published', 'rejected', 'unpublished', 'archived'));
alter table public.courses drop constraint if exists courses_visibility_check;
alter table public.courses add constraint courses_visibility_check
  check (visibility in ('public', 'enrolled_students'));
alter table public.courses drop constraint if exists courses_estimated_minutes_check;
alter table public.courses add constraint courses_estimated_minutes_check
  check (estimated_minutes is null or estimated_minutes between 1 and 100000);
alter table public.courses drop constraint if exists courses_level_check;
alter table public.courses add constraint courses_level_check
  check (level in ('Beginner', 'Intermediate', 'Advanced', 'All levels'));
create index courses_owner_status_idx on public.courses(owner_id, status, updated_at desc);
create index courses_published_created_idx on public.courses(created_at desc) where status = 'published';

alter table public.enrollments
  add column if not exists status text not null default 'active',
  add column if not exists completed_at timestamptz;
alter table public.enrollments drop constraint if exists enrollments_status_check;
alter table public.enrollments add constraint enrollments_status_check
  check (status in ('active', 'completed', 'cancelled'));
alter table public.enrollments drop constraint if exists enrollments_user_id_course_id_key;
create unique index enrollments_one_current_per_course
  on public.enrollments(user_id, course_id) where status in ('active', 'completed');
create index enrollments_course_status_idx on public.enrollments(course_id, status);

create table public.course_modules (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete cascade,
  title text not null check (length(trim(title)) between 2 and 180),
  description text not null default '',
  position integer not null default 0 check (position >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(course_id, position)
);
create table public.lessons (
  id uuid primary key default gen_random_uuid(),
  module_id uuid not null references public.course_modules(id) on delete cascade,
  title text not null check (length(trim(title)) between 2 and 180),
  body text not null default '',
  position integer not null default 0 check (position >= 0),
  duration_minutes integer check (duration_minutes is null or duration_minutes between 1 and 10000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(module_id, position)
);
create table public.resource_folders (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete cascade,
  parent_id uuid references public.resource_folders(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 160),
  position integer not null default 0 check (position >= 0),
  created_at timestamptz not null default now(),
  unique(course_id, parent_id, name)
);
create table public.resources (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete cascade,
  folder_id uuid references public.resource_folders(id) on delete set null,
  lesson_id uuid references public.lessons(id) on delete set null,
  title text not null check (length(trim(title)) between 1 and 180),
  resource_type text not null check (resource_type in ('pdf', 'document', 'image', 'video', 'link', 'other')),
  storage_path text,
  external_url text,
  mime_type text,
  file_size_bytes bigint check (file_size_bytes is null or file_size_bytes between 1 and 52428800),
  position integer not null default 0 check (position >= 0),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((resource_type = 'link' and external_url is not null and storage_path is null)
      or (resource_type <> 'link' and storage_path is not null and external_url is null)),
  check (external_url is null or external_url ~* '^https://')
);
create index resources_course_position_idx on public.resources(course_id, position);

create or replace function public.can_manage_course(p_course_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.is_admin() or exists (
    select 1 from public.courses c
    where c.id = p_course_id and c.owner_id = (select auth.uid())
      and public.has_app_role((select auth.uid()), 'lecturer')
      and public.is_active_user() and public.is_verified_user()
      and c.status in ('draft', 'rejected', 'unpublished')
  );
$$;
create or replace function public.can_access_course(p_course_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.is_admin()
    or public.can_manage_course(p_course_id)
    or exists (
      select 1 from public.courses c
      where c.id = p_course_id and c.owner_id = (select auth.uid())
        and public.has_app_role((select auth.uid()), 'lecturer')
        and public.is_active_user() and public.is_verified_user()
    )
    or (
      public.is_active_user() and public.is_verified_user()
      and exists (select 1 from public.courses c where c.id = p_course_id
        and c.status = 'published' and c.visibility = 'public')
    )
    or (
      public.is_approved_student()
      and exists (
        select 1 from public.enrollments e
        where e.course_id = p_course_id and e.user_id = (select auth.uid())
          and e.status in ('active', 'completed')
      )
    );
$$;
revoke all on function public.can_manage_course(uuid) from public;
revoke all on function public.can_access_course(uuid) from public;
grant execute on function public.can_manage_course(uuid) to authenticated;
grant execute on function public.can_access_course(uuid) to authenticated;

alter table public.courses enable row level security;
drop policy if exists "Anyone can read published courses" on public.courses;
create policy "Published courses are discoverable"
  on public.courses for select to anon, authenticated
  using ((status = 'published' and visibility = 'public') or owner_id = (select auth.uid()) or public.is_admin());
create policy "Enrolled students retain course access"
  on public.courses for select to authenticated
  using (public.can_access_course(id));
create policy "Approved lecturers create owned drafts"
  on public.courses for insert to authenticated
  with check (
    owner_id = (select auth.uid()) and status = 'draft' and not is_published
    and public.has_app_role((select auth.uid()), 'lecturer')
    and public.is_active_user() and public.is_verified_user()
  );
create policy "Owners and admins update courses"
  on public.courses for update to authenticated
  using (public.is_admin() or (owner_id = (select auth.uid()) and public.has_app_role((select auth.uid()), 'lecturer')))
  with check (public.is_admin() or (owner_id = (select auth.uid()) and not is_published));
create policy "Admins delete courses without enrollments"
  on public.courses for delete to authenticated
  using (public.is_admin() and not exists (select 1 from public.enrollments e where e.course_id = id));
grant insert, update, delete on public.courses to authenticated;

alter table public.course_modules enable row level security;
alter table public.lessons enable row level security;
alter table public.resource_folders enable row level security;
alter table public.resources enable row level security;
create policy "Course managers manage modules" on public.course_modules for all to authenticated
  using (public.can_manage_course(course_id)) with check (public.can_manage_course(course_id));
create policy "Course members read modules" on public.course_modules for select to authenticated
  using (public.can_access_course(course_id));
create policy "Course managers manage lessons" on public.lessons for all to authenticated
  using (exists (select 1 from public.course_modules m where m.id = module_id and public.can_manage_course(m.course_id)))
  with check (exists (select 1 from public.course_modules m where m.id = module_id and public.can_manage_course(m.course_id)));
create policy "Course members read lessons" on public.lessons for select to authenticated
  using (exists (select 1 from public.course_modules m where m.id = module_id and public.can_access_course(m.course_id)));
create policy "Course managers manage folders" on public.resource_folders for all to authenticated
  using (public.can_manage_course(course_id)) with check (public.can_manage_course(course_id));
create policy "Course members read folders" on public.resource_folders for select to authenticated
  using (public.can_access_course(course_id));
create policy "Course managers manage resources" on public.resources for all to authenticated
  using (public.can_manage_course(course_id))
  with check (public.can_manage_course(course_id) and created_by = (select auth.uid()));
create policy "Course members read resources" on public.resources for select to authenticated
  using (public.can_access_course(course_id));
grant select, insert, update, delete on public.course_modules, public.lessons,
  public.resource_folders, public.resources to authenticated;

alter table public.enrollments enable row level security;
drop policy if exists "Verified users read their own enrollments" on public.enrollments;
create policy "Users and course managers read enrollments" on public.enrollments for select to authenticated
  using (user_id = (select auth.uid()) or public.can_manage_course(course_id) or public.is_admin());
drop policy if exists "Verified users enroll themselves in published courses" on public.enrollments;
create policy "Approved students enroll in published courses" on public.enrollments for insert to authenticated
  with check (
    user_id = (select auth.uid()) and status = 'active'
    and public.is_approved_student()
    and exists (select 1 from public.courses c where c.id = course_id
      and c.status = 'published' and c.visibility = 'public')
  );
create policy "Students cancel own enrollment" on public.enrollments for update to authenticated
  using (user_id = (select auth.uid()) and status = 'active' and public.is_approved_student())
  with check (user_id = (select auth.uid()) and status = 'cancelled');
grant update (status) on public.enrollments to authenticated;

create table public.course_reviews (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete cascade,
  student_id uuid not null references auth.users(id) on delete cascade,
  rating smallint not null check (rating between 1 and 5),
  comment text not null check (length(trim(comment)) between 3 and 3000),
  status text not null default 'published' check (status in ('published', 'hidden', 'reported')),
  lecturer_response text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(course_id, student_id)
);
create index course_reviews_course_status_idx on public.course_reviews(course_id, status, created_at desc);
alter table public.course_reviews enable row level security;
create policy "Published reviews are public; owners and admins can inspect" on public.course_reviews for select to authenticated
  using (status = 'published' or student_id = (select auth.uid()) or public.can_manage_course(course_id) or public.is_admin());
create policy "Eligible students create their own review" on public.course_reviews for insert to authenticated
  with check (
    student_id = (select auth.uid()) and status = 'published' and lecturer_response is null
    and public.is_approved_student()
    and exists (select 1 from public.enrollments e where e.course_id = course_id and e.user_id = (select auth.uid()) and e.status in ('active', 'completed'))
  );
create policy "Authors edit their own review" on public.course_reviews for update to authenticated
  using (student_id = (select auth.uid()) and public.is_approved_student())
  with check (student_id = (select auth.uid()) and public.is_approved_student());
create policy "Admins moderate reviews" on public.course_reviews for update to authenticated
  using (public.is_admin()) with check (public.is_admin());
grant select on public.course_reviews to authenticated;
grant insert (course_id, student_id, rating, comment) on public.course_reviews to authenticated;
grant update (rating, comment) on public.course_reviews to authenticated;

create or replace function public.admin_moderate_course_review(
  p_review_id uuid, p_status text, p_reason text default ''
) returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_admin() or p_status not in ('published', 'hidden', 'reported') then
    raise exception 'Administrator access required or invalid review status';
  end if;
  update public.course_reviews set status = p_status where id = p_review_id;
  if not found then raise exception 'Review not found'; end if;
  insert into public.audit_logs(actor_id, action, target_type, target_id, metadata)
    values(auth.uid(), 'course_review_moderated', 'course_review', p_review_id::text,
      jsonb_build_object('status', p_status, 'reason', left(p_reason, 500)));
end;
$$;
revoke all on function public.admin_moderate_course_review(uuid,text,text) from public;
grant execute on function public.admin_moderate_course_review(uuid,text,text) to authenticated;

create or replace function public.course_review_summary(p_course_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or not public.is_active_user() or not public.is_verified_user() then
    raise exception 'An active verified account is required';
  end if;
  if not public.can_access_course(p_course_id) then
    raise exception 'Course access is required to read its rating summary';
  end if;
  return (select jsonb_build_object(
    'count', count(*),
    'average', coalesce(round(avg(rating)::numeric, 2), 0)
  ) from public.course_reviews where course_id = p_course_id and status = 'published');
end;
$$;
revoke all on function public.course_review_summary(uuid) from public;
grant execute on function public.course_review_summary(uuid) to authenticated;

create table public.course_review_reports (
  id uuid primary key default gen_random_uuid(),
  review_id uuid not null references public.course_reviews(id) on delete cascade,
  reporter_id uuid not null references auth.users(id) on delete cascade,
  reason text not null check (length(trim(reason)) between 5 and 2000),
  status text not null default 'open' check (status in ('open', 'resolved', 'dismissed')),
  handled_by uuid references auth.users(id) on delete set null,
  handled_at timestamptz,
  created_at timestamptz not null default now(),
  unique(review_id, reporter_id)
);
create index course_review_reports_status_created_idx
  on public.course_review_reports(status, created_at desc);
alter table public.course_review_reports enable row level security;
create policy "Users report published reviews once" on public.course_review_reports for insert to authenticated
  with check (reporter_id = (select auth.uid()) and public.is_active_user() and public.is_verified_user()
    and status = 'open' and handled_by is null and handled_at is null
    and exists (select 1 from public.course_reviews r where r.id = review_id and r.status = 'published' and r.student_id <> (select auth.uid())));
create policy "Reporters and admins read review reports" on public.course_review_reports for select to authenticated
  using (reporter_id = (select auth.uid()) or public.is_admin());
grant select on public.course_review_reports to authenticated;
grant insert (review_id, reporter_id, reason) on public.course_review_reports to authenticated;

create or replace function public.submit_course_review_report(p_review_id uuid, p_reason text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_report_id uuid;
begin
  if auth.uid() is null or not public.is_active_user() or not public.is_verified_user() then
    raise exception 'An active verified account is required';
  end if;
  insert into public.course_review_reports(review_id, reporter_id, reason)
    values(p_review_id, auth.uid(), trim(p_reason)) returning id into v_report_id;
  insert into public.audit_logs(actor_id, action, target_type, target_id, metadata)
    values(auth.uid(), 'course_review_reported', 'course_review', p_review_id::text,
      jsonb_build_object('report_id', v_report_id));
  return v_report_id;
end;
$$;
revoke all on function public.submit_course_review_report(uuid,text) from public;
grant execute on function public.submit_course_review_report(uuid,text) to authenticated;

create or replace function public.admin_resolve_course_review_report(
  p_report_id uuid, p_hide_review boolean, p_reason text default ''
) returns void language plpgsql security definer set search_path = '' as $$
declare v_review_id uuid;
begin
  if not public.is_admin() then raise exception 'Administrator access required'; end if;
  update public.course_review_reports set status = case when p_hide_review then 'resolved' else 'dismissed' end,
    handled_by = auth.uid(), handled_at = now()
    where id = p_report_id and status = 'open' returning review_id into v_review_id;
  if not found then raise exception 'Open report not found'; end if;
  if p_hide_review then update public.course_reviews set status = 'hidden' where id = v_review_id; end if;
  insert into public.audit_logs(actor_id, action, target_type, target_id, metadata)
    values(auth.uid(), 'course_review_report_resolved', 'course_review_report', p_report_id::text,
      jsonb_build_object('hide_review', p_hide_review, 'reason', left(p_reason, 500)));
end;
$$;
revoke all on function public.admin_resolve_course_review_report(uuid,boolean,text) from public;
grant execute on function public.admin_resolve_course_review_report(uuid,boolean,text) to authenticated;

create table public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null check (length(trim(title)) between 3 and 180),
  body text not null check (length(trim(body)) between 3 and 10000),
  audience text not null check (audience in ('everyone', 'students', 'lecturers')),
  status text not null default 'draft' check (status in ('draft', 'published', 'withdrawn')),
  author_id uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  published_at timestamptz,
  expires_at timestamptz
);
alter table public.announcements enable row level security;
create policy "Admins manage announcements" on public.announcements for all to authenticated
  using (public.is_admin()) with check (public.is_admin() and author_id = (select auth.uid()));
create policy "Users read published announcements" on public.announcements for select to authenticated
  using (status = 'published' and (expires_at is null or expires_at > now())
    and (audience = 'everyone'
      or (audience = 'students' and public.has_app_role((select auth.uid()), 'student'))
      or (audience = 'lecturers' and public.has_app_role((select auth.uid()), 'lecturer'))));
grant select on public.announcements to authenticated;
grant insert (title, body, audience, author_id, expires_at) on public.announcements to authenticated;
grant update (title, body, audience, expires_at) on public.announcements to authenticated;

create table public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete cascade,
  category text not null check (category in ('account', 'verification', 'course', 'resource', 'conduct', 'copyright', 'technical', 'suggestion', 'other')),
  subject text not null check (length(trim(subject)) between 3 and 180),
  description text not null check (length(trim(description)) between 10 and 6000),
  related_course_id uuid references public.courses(id) on delete set null,
  status text not null default 'open' check (status in ('open', 'in_progress', 'resolved', 'closed')),
  priority text not null default 'normal' check (priority in ('low', 'normal', 'high', 'urgent')),
  assigned_admin_id uuid references auth.users(id) on delete set null,
  resolution text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index support_tickets_status_created_idx on public.support_tickets(status, created_at desc);
create index support_tickets_reporter_idx on public.support_tickets(reporter_id, created_at desc);
alter table public.support_tickets enable row level security;
create policy "Users create own support tickets" on public.support_tickets for insert to authenticated
  with check (reporter_id = (select auth.uid()) and public.is_active_user() and public.is_verified_user() and status = 'open' and assigned_admin_id is null and resolution is null);
create policy "Users read own tickets and admins read all" on public.support_tickets for select to authenticated
  using ((reporter_id = (select auth.uid()) and public.is_active_user()) or public.is_admin());
create policy "Admins manage support tickets" on public.support_tickets for update to authenticated
  using (public.is_admin()) with check (public.is_admin());
grant select on public.support_tickets to authenticated;
grant insert (reporter_id, category, subject, description, related_course_id) on public.support_tickets to authenticated;
grant update on public.support_tickets to authenticated;

create or replace function public.audit_support_ticket_update()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'Administrator access required'; end if;
  insert into public.audit_logs(actor_id, action, target_type, target_id, metadata)
    values(auth.uid(), 'support_ticket_updated', 'support_ticket', new.id::text,
      jsonb_build_object('status', new.status, 'priority', new.priority,
        'assigned_admin_id', new.assigned_admin_id, 'resolution', left(coalesce(new.resolution, ''), 500)));
  return new;
end;
$$;
create trigger support_ticket_audit before update on public.support_tickets
  for each row execute function public.audit_support_ticket_update();

create table public.audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  target_type text not null,
  target_id text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index audit_logs_created_idx on public.audit_logs(created_at desc);
alter table public.audit_logs enable row level security;
create policy "Admins read audit logs" on public.audit_logs for select to authenticated using (public.is_admin());
grant select on public.audit_logs to authenticated;
revoke insert, update, delete on public.audit_logs from anon, authenticated;

create table public.announcement_deliveries (
  announcement_id uuid not null references public.announcements(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  notification_id uuid references public.notifications(id) on delete set null,
  delivered_at timestamptz not null default now(),
  primary key (announcement_id, user_id)
);
alter table public.announcement_deliveries enable row level security;
create policy "Users read own announcement deliveries" on public.announcement_deliveries for select to authenticated
  using (user_id = (select auth.uid()) or public.is_admin());
grant select on public.announcement_deliveries to authenticated;

-- Enforce account suspension and publication workflow independently of Flutter.
create or replace function public.guard_course_write()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if auth.role() = 'service_role' then
    new.is_published := new.status = 'published';
    return new;
  end if;
  if public.is_admin() then
    new.is_published := new.status = 'published';
    if tg_op = 'UPDATE' then
      if new.status = 'published' and old.status is distinct from 'published' then new.published_at := now(); end if;
      insert into public.audit_logs(actor_id, action, target_type, target_id, metadata)
        values (auth.uid(), 'course_moderated', 'course', new.id::text,
          jsonb_build_object('from', old.status, 'to', new.status));
    end if;
    return new;
  end if;
  if tg_op = 'INSERT' then
    if new.owner_id is distinct from auth.uid() or not public.has_app_role(auth.uid(), 'lecturer')
       or not public.is_active_user() or not public.is_verified_user() or new.status <> 'draft' then
      raise exception 'Only an active approved lecturer can create an owned draft';
    end if;
    new.is_published := false;
    return new;
  end if;
  if new.owner_id is distinct from old.owner_id or new.owner_id is distinct from auth.uid()
     or not public.has_app_role(auth.uid(), 'lecturer') or not public.is_active_user()
     or not public.is_verified_user() then raise exception 'You cannot change this course owner'; end if;
  if not ((old.status = new.status and new.status in ('draft','rejected','unpublished'))
      or (old.status = 'draft' and new.status = 'submitted')
      or (old.status = 'rejected' and new.status = 'draft')
      or (old.status = 'published' and new.status in ('unpublished','archived'))
      or (old.status = 'unpublished' and new.status in ('draft','archived'))) then
    raise exception 'This course status transition requires administrator approval';
  end if;
  new.is_published := new.status = 'published';
  return new;
end;
$$;
drop trigger if exists courses_guard_write on public.courses;
create trigger courses_guard_write before insert or update on public.courses
  for each row execute function public.guard_course_write();

create or replace function public.on_lecturer_application_decision()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status is distinct from new.status and new.status in ('approved', 'rejected') then
    new.reviewed_at := now();
    new.reviewed_by := auth.uid();
    if new.status = 'approved' then
      insert into public.user_roles(user_id, role) values(new.user_id, 'lecturer') on conflict do nothing;
    else
      delete from public.user_roles where user_id = new.user_id and role = 'lecturer';
    end if;
    insert into public.notifications(user_id, category, title, body, metadata)
      values(new.user_id, 'account', 'Lecturer application updated',
        case when new.status = 'approved' then 'Your lecturer application was approved.' else 'Your lecturer application was not approved.' end,
        jsonb_build_object('application_id', new.id, 'status', new.status));
    insert into public.audit_logs(actor_id, action, target_type, target_id, metadata)
      values(auth.uid(), 'lecturer_application_decided', 'lecturer_application', new.id::text,
        jsonb_build_object('status', new.status, 'reason', new.decision_reason));
  end if;
  return new;
end;
$$;
create trigger lecturer_application_decision before update on public.lecturer_applications
  for each row execute function public.on_lecturer_application_decision();

create or replace function public.on_student_verification_decision()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status is distinct from new.status and new.status in ('approved', 'rejected') then
    new.reviewed_at := now();
    new.reviewed_by := auth.uid();
    update public.profiles set student_verification_status = new.status where id = new.user_id;
    insert into public.notifications(user_id, category, title, body, metadata)
      values(new.user_id, 'account', 'Student verification updated',
        case when new.status = 'approved' then 'Your student verification was approved.' else coalesce(new.decision_reason, 'Your student verification was not approved.') end,
        jsonb_build_object('verification_request_id', new.id, 'status', new.status));
    insert into public.audit_logs(actor_id, action, target_type, target_id, metadata)
      values(auth.uid(), 'student_verification_decided', 'student_verification_request', new.id::text,
        jsonb_build_object('status', new.status, 'reason', new.decision_reason));
  end if;
  return new;
end;
$$;
create trigger student_verification_decision before update on public.student_verification_requests
  for each row execute function public.on_student_verification_decision();

create or replace function public.submit_lecturer_application(
  p_department text, p_qualifications text, p_experience text, p_evidence_path text default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if auth.uid() is null or not public.is_active_user() or not public.is_verified_user() then
    raise exception 'An active verified account is required';
  end if;
  if public.has_app_role(auth.uid(), 'lecturer') then raise exception 'This account is already a lecturer'; end if;
  insert into public.lecturer_applications(user_id, department, qualifications, experience, evidence_path)
    values(auth.uid(), trim(p_department), trim(p_qualifications), trim(p_experience), p_evidence_path)
    returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.submit_lecturer_application(text,text,text,text) from public;
grant execute on function public.submit_lecturer_application(text,text,text,text) to authenticated;

create or replace function public.submit_student_verification(
  p_student_number text, p_department text, p_program text, p_evidence_path text default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if auth.uid() is null or not public.is_active_user() or not public.is_verified_user() then
    raise exception 'An active verified account is required';
  end if;
  if not public.has_app_role(auth.uid(), 'student') then raise exception 'Student role required'; end if;
  if exists(select 1 from public.profiles where id = auth.uid() and student_verification_status = 'approved') then
    raise exception 'Student verification is already approved';
  end if;
  if exists(select 1 from public.student_verification_requests r where r.user_id = auth.uid() and r.status = 'pending') then
    raise exception 'A verification request is already pending';
  end if;
  insert into public.student_verification_requests(user_id, student_number, department, program, evidence_path)
    values(auth.uid(), trim(p_student_number), trim(p_department), trim(p_program), p_evidence_path)
    returning id into v_id;
  update public.profiles set student_verification_status = 'pending' where id = auth.uid();
  return v_id;
end;
$$;
revoke all on function public.submit_student_verification(text,text,text,text) from public;
grant execute on function public.submit_student_verification(text,text,text,text) to authenticated;

create or replace function public.admin_assign_role(p_user_id uuid, p_role text, p_grant boolean, p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_admin() or p_role not in ('student','lecturer','admin') then raise exception 'Administrator access required'; end if;
  if p_user_id = auth.uid() and p_role = 'admin' and not p_grant then raise exception 'You cannot revoke your own admin role'; end if;
  if p_role = 'admin' and not p_grant
     and exists (select 1 from public.user_roles where user_id = p_user_id and role = 'admin')
     and (select count(*) from public.user_roles r join public.profiles p on p.id = r.user_id
          where r.role = 'admin' and p.account_status = 'active' and r.user_id <> p_user_id) = 0 then
    raise exception 'The last active administrator cannot be removed';
  end if;
  if p_grant then
    insert into public.user_roles(user_id, role) values(p_user_id, p_role) on conflict do nothing;
  else
    delete from public.user_roles where user_id = p_user_id and role = p_role;
  end if;
  insert into public.audit_logs(actor_id, action, target_type, target_id, metadata)
    values(auth.uid(), case when p_grant then 'role_granted' else 'role_revoked' end,
      'user', p_user_id::text, jsonb_build_object('role', p_role, 'reason', left(p_reason, 500)));
end;
$$;
revoke all on function public.admin_assign_role(uuid,text,boolean,text) from public;
grant execute on function public.admin_assign_role(uuid,text,boolean,text) to authenticated;

create or replace function public.publish_announcement(p_announcement_id uuid)
returns integer language plpgsql security definer set search_path = '' as $$
declare v_announcement public.announcements%rowtype; v_count integer;
begin
  if not public.is_admin() then raise exception 'Administrator access required'; end if;
  update public.announcements set status = 'published', published_at = now()
    where id = p_announcement_id and status = 'draft' returning * into v_announcement;
  if not found then raise exception 'Draft announcement not found'; end if;
  with audience as (
    select u.id from auth.users u
    join public.profiles p on p.id = u.id
    where p.account_status = 'active' and u.email_confirmed_at is not null
      and (v_announcement.audience = 'everyone'
        or (v_announcement.audience = 'students' and public.has_app_role(u.id, 'student'))
        or (v_announcement.audience = 'lecturers' and public.has_app_role(u.id, 'lecturer')))
  ), inserted as (
    insert into public.announcement_deliveries(announcement_id, user_id)
    select v_announcement.id, a.id from audience a
    on conflict do nothing returning user_id
  ), notices as (
    insert into public.notifications(user_id, category, title, body, metadata)
    select i.user_id, 'announcement', v_announcement.title, v_announcement.body,
      jsonb_build_object('announcement_id', v_announcement.id)
    from inserted i returning id, user_id
  )
  update public.announcement_deliveries d set notification_id = n.id
    from notices n where d.announcement_id = v_announcement.id and d.user_id = n.user_id;
  get diagnostics v_count = row_count;
  insert into public.audit_logs(actor_id, action, target_type, target_id, metadata)
    values(auth.uid(), 'announcement_published', 'announcement', p_announcement_id::text,
      jsonb_build_object('audience', v_announcement.audience, 'recipient_count', v_count));
  return v_count;
end;
$$;
revoke all on function public.publish_announcement(uuid) from public;
grant execute on function public.publish_announcement(uuid) to authenticated;

create or replace function public.admin_platform_metrics()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'Administrator access required'; end if;
  return jsonb_build_object(
    'users_total', (select count(*) from auth.users),
    'users_active', (select count(*) from public.profiles where account_status = 'active'),
    'users_suspended', (select count(*) from public.profiles where account_status = 'suspended'),
    'students_total', (select count(*) from public.user_roles where role = 'student'),
    'students_pending', (select count(*) from public.profiles where student_verification_status = 'pending'),
    'students_approved', (select count(*) from public.profiles where student_verification_status = 'approved'),
    'lecturers_total', (select count(*) from public.user_roles where role = 'lecturer'),
    'lecturer_applications_pending', (select count(*) from public.lecturer_applications where status = 'pending'),
    'lecturer_applications_approved', (select count(*) from public.lecturer_applications where status = 'approved'),
    'courses_total', (select count(*) from public.courses),
    'courses_draft', (select count(*) from public.courses where status = 'draft'),
    'courses_submitted', (select count(*) from public.courses where status = 'submitted'),
    'courses_published', (select count(*) from public.courses where status = 'published'),
    'courses_archived', (select count(*) from public.courses where status = 'archived'),
    'enrollments_total', (select count(*) from public.enrollments where status in ('active','completed')),
    'distinct_enrolled_students', (select count(distinct user_id) from public.enrollments where status in ('active','completed')),
    'published_reviews', (select count(*) from public.course_reviews where status = 'published'),
    'average_course_rating', (select round(avg(rating)::numeric, 2) from public.course_reviews where status = 'published'),
    'support_open', (select count(*) from public.support_tickets where status in ('open','in_progress'))
  );
end;
$$;
revoke all on function public.admin_platform_metrics() from public;
grant execute on function public.admin_platform_metrics() to authenticated;

-- Notification recipients can only access their own rows; complete read state API.
drop policy if exists "Verified users read own notifications" on public.notifications;
create policy "Verified users read own notifications" on public.notifications for select to authenticated
  using (user_id = (select auth.uid()) and public.is_active_user() and public.is_verified_user());
drop policy if exists "Verified users mark their own notifications read" on public.notifications;
drop policy if exists "Users mark own notifications read" on public.notifications;
create policy "Users mark own notifications read" on public.notifications for update to authenticated
  using (user_id = (select auth.uid()) and public.is_active_user())
  with check (user_id = (select auth.uid()) and public.is_active_user());
grant update (read_at) on public.notifications to authenticated;

-- Keep related records from disappearing when a lecturer archives a course.
create or replace function public.touch_phase1_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin new.updated_at = now(); return new; end;
$$;
create trigger student_verification_touch_updated_at before update on public.student_verification_requests
  for each row execute function public.touch_phase1_updated_at();
create trigger lecturer_applications_touch_updated_at before update on public.lecturer_applications
  for each row execute function public.touch_phase1_updated_at();
create trigger courses_touch_updated_at before update on public.courses
  for each row execute function public.touch_phase1_updated_at();
create trigger course_modules_touch_updated_at before update on public.course_modules
  for each row execute function public.touch_phase1_updated_at();
create trigger lessons_touch_updated_at before update on public.lessons
  for each row execute function public.touch_phase1_updated_at();
create trigger resources_touch_updated_at before update on public.resources
  for each row execute function public.touch_phase1_updated_at();
create trigger course_reviews_touch_updated_at before update on public.course_reviews
  for each row execute function public.touch_phase1_updated_at();
create trigger support_tickets_touch_updated_at before update on public.support_tickets
  for each row execute function public.touch_phase1_updated_at();

-- Authenticated users may read their own application state, never decide it.
alter table public.student_verification_requests enable row level security;
alter table public.lecturer_applications enable row level security;
create policy "Users submit own student verification" on public.student_verification_requests for insert to authenticated
  with check (user_id = (select auth.uid()) and status = 'pending'
    and public.is_active_user() and public.is_verified_user()
    and public.has_app_role((select auth.uid()), 'student')
    and not exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.student_verification_status = 'approved'));
create policy "Users read own student verification" on public.student_verification_requests for select to authenticated
  using (user_id = (select auth.uid()) or public.is_admin());
create policy "Admins decide student verification" on public.student_verification_requests for update to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy "Users submit own lecturer application" on public.lecturer_applications for insert to authenticated
  with check (user_id = (select auth.uid()) and status = 'pending'
    and public.is_active_user() and public.is_verified_user()
    and not public.has_app_role((select auth.uid()), 'lecturer'));
create policy "Users and admins read lecturer applications" on public.lecturer_applications for select to authenticated
  using (user_id = (select auth.uid()) or public.is_admin());
create policy "Admins decide lecturer applications" on public.lecturer_applications for update to authenticated
  using (public.is_admin()) with check (public.is_admin());
grant select on public.student_verification_requests, public.lecturer_applications to authenticated;
grant insert (user_id, student_number, department, program, evidence_path)
  on public.student_verification_requests to authenticated;
grant insert (user_id, department, qualifications, experience, evidence_path)
  on public.lecturer_applications to authenticated;
grant update (status, decision_reason) on public.student_verification_requests to authenticated;
grant update (status, decision_reason) on public.lecturer_applications to authenticated;
revoke delete on public.student_verification_requests, public.lecturer_applications from anon, authenticated;

-- Provision verification requests for users who predate these workflows.
insert into public.student_verification_requests(user_id, student_number, department, program)
select p.id, trim(u.raw_user_meta_data ->> 'student_number'),
  trim(u.raw_user_meta_data ->> 'department'), trim(u.raw_user_meta_data ->> 'program')
from public.profiles p join auth.users u on u.id = p.id
where p.student_verification_status = 'pending'
  and coalesce(u.raw_user_meta_data ->> 'student_number', '') <> ''
  and coalesce(u.raw_user_meta_data ->> 'department', '') <> ''
  and coalesce(u.raw_user_meta_data ->> 'program', '') <> ''
  and not exists (select 1 from public.student_verification_requests r where r.user_id = p.id and r.status = 'pending')
  and public.has_app_role(p.id, 'student');

-- Private resources bucket. Course folder is the first path segment.
insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('course-resources', 'course-resources', false, 52428800,
  array['application/pdf','application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'application/vnd.ms-powerpoint','application/vnd.openxmlformats-officedocument.presentationml.presentation',
        'application/vnd.ms-excel','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'image/jpeg','image/png','image/webp','video/mp4','text/plain'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;
create or replace function public.can_access_course_storage(p_course_segment text)
returns boolean language sql stable security definer set search_path = '' as $$
  select case when p_course_segment ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then public.can_access_course(p_course_segment::uuid) else false end;
$$;
create or replace function public.can_manage_course_storage(p_course_segment text)
returns boolean language sql stable security definer set search_path = '' as $$
  select case when p_course_segment ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then public.can_manage_course(p_course_segment::uuid) else false end;
$$;
revoke all on function public.can_access_course_storage(text) from public;
revoke all on function public.can_manage_course_storage(text) from public;
grant execute on function public.can_access_course_storage(text) to authenticated;
grant execute on function public.can_manage_course_storage(text) to authenticated;
create policy "Lecturers upload owned course resources" on storage.objects for insert to authenticated
  with check (bucket_id = 'course-resources'
    and (storage.foldername(name))[2] = (select auth.uid())::text
    and public.can_manage_course_storage((storage.foldername(name))[1]));
create policy "Course participants read authorized resources" on storage.objects for select to authenticated
  using (bucket_id = 'course-resources'
    and public.can_access_course_storage((storage.foldername(name))[1]));
create policy "Lecturers update owned course resources" on storage.objects for update to authenticated
  using (bucket_id = 'course-resources'
    and (storage.foldername(name))[2] = (select auth.uid())::text
    and public.can_manage_course_storage((storage.foldername(name))[1]))
  with check (bucket_id = 'course-resources'
    and (storage.foldername(name))[2] = (select auth.uid())::text
    and public.can_manage_course_storage((storage.foldername(name))[1]));
create policy "Lecturers delete owned course resources" on storage.objects for delete to authenticated
  using (bucket_id = 'course-resources'
    and (storage.foldername(name))[2] = (select auth.uid())::text
    and public.can_manage_course_storage((storage.foldername(name))[1]));
