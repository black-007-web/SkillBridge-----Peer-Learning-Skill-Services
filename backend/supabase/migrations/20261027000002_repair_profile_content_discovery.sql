alter table public.profiles
  add column if not exists phone_number text,
  add column if not exists phone_verified_at timestamptz,
  add column if not exists bio text not null default '',
  add column if not exists social_links jsonb not null default '{}'::jsonb,
  add column if not exists position text not null default '',
  add column if not exists skills text[] not null default '{}';

grant update (phone_number, bio, social_links, position, skills)
  on public.profiles to authenticated;
grant insert (bio, social_links, position, skills)
  on public.profiles to authenticated;

create or replace function public.clear_profile_phone_verification_on_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.phone_number is distinct from old.phone_number then
    new.phone_verified_at := null;
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_clear_phone_verification_on_change
  on public.profiles;
create trigger profiles_clear_phone_verification_on_change
  before update of phone_number on public.profiles
  for each row execute function public.clear_profile_phone_verification_on_change();

drop policy if exists "Published courses are discoverable" on public.courses;
create policy "Published courses are discoverable"
  on public.courses for select to anon, authenticated
  using (status = 'published' or owner_id = (select auth.uid()) or public.is_admin());
grant select on public.courses to anon, authenticated;

drop policy if exists "Approved students enroll in published courses"
  on public.enrollments;
create policy "Approved students enroll in published courses"
  on public.enrollments for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and status = 'active'
    and public.is_approved_student()
    and exists (
      select 1 from public.courses c
      where c.id = course_id and c.status = 'published'
    )
  );

create or replace function public.can_manage_course(p_course_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_admin() or exists (
    select 1 from public.courses c
    where c.id = p_course_id
      and c.owner_id = (select auth.uid())
      and public.has_app_role((select auth.uid()), 'lecturer')
      and public.is_active_user()
      and public.is_verified_user()
      and c.status in ('draft', 'rejected', 'unpublished', 'published')
  );
$$;
revoke all on function public.can_manage_course(uuid) from public;
grant execute on function public.can_manage_course(uuid) to authenticated;

create or replace function public.can_manage_course_storage(p_course_segment text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_course_segment ~*
      '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then public.can_manage_course(p_course_segment::uuid)
    else false
  end;
$$;
revoke all on function public.can_manage_course_storage(text) from public;
grant execute on function public.can_manage_course_storage(text) to authenticated;

drop policy if exists "Lecturers upload owned course resources" on storage.objects;
create policy "Lecturers upload owned course resources"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'course-resources'
    and (storage.foldername(name))[2] = (select auth.uid())::text
    and public.can_manage_course_storage((storage.foldername(name))[1])
  );

drop policy if exists "Lecturers update owned course resources" on storage.objects;
create policy "Lecturers update owned course resources"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'course-resources'
    and (storage.foldername(name))[2] = (select auth.uid())::text
    and public.can_manage_course_storage((storage.foldername(name))[1])
  )
  with check (
    bucket_id = 'course-resources'
    and (storage.foldername(name))[2] = (select auth.uid())::text
    and public.can_manage_course_storage((storage.foldername(name))[1])
  );

drop policy if exists "Lecturers delete owned course resources" on storage.objects;
create policy "Lecturers delete owned course resources"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'course-resources'
    and (storage.foldername(name))[2] = (select auth.uid())::text
    and public.can_manage_course_storage((storage.foldername(name))[1])
  );

update storage.buckets
set allowed_mime_types = (
  select array_agg(distinct allowed.mime_type)
  from unnest(
    coalesce(allowed_mime_types, '{}'::text[]) || array[
      'image/gif',
      'video/quicktime',
      'video/webm'
    ]
  ) as allowed(mime_type)
)
where id = 'course-resources';

create or replace function public.discover_courses(
  p_search text default '',
  p_category text default null,
  p_level text default null,
  p_minimum_rating numeric default null,
  p_limit integer default 24,
  p_offset integer default 0
) returns table(course jsonb, average_rating numeric, review_count bigint)
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
      'id', c.id, 'title', c.title, 'description', c.description,
      'category', c.category, 'level', c.level, 'instructor', c.instructor,
      'owner_id', c.owner_id, 'status', c.status, 'visibility', c.visibility,
      'cover_image_path', c.cover_image_path, 'learning_outcomes', c.learning_outcomes,
      'prerequisites', c.prerequisites, 'estimated_minutes', c.estimated_minutes,
      'created_at', c.created_at, 'published_at', c.published_at,
      'is_published', c.is_published
    ), coalesce(r.average_rating, 0)::numeric,
    coalesce(r.review_count, 0)::bigint
  from public.courses c
  left join lateral (
    select avg(cr.rating)::numeric as average_rating, count(*)::bigint as review_count
    from public.course_reviews cr
    where cr.course_id = c.id and cr.status = 'published'
  ) r on true
  where c.status = 'published'
    and (coalesce(trim(p_category), '') = '' or c.category = trim(p_category))
    and (coalesce(trim(p_level), '') = '' or c.level = trim(p_level))
    and (coalesce(trim(p_search), '') = '' or
      (c.title || ' ' || c.description || ' ' || c.category || ' ' || c.instructor)
        ilike '%' || replace(replace(replace(trim(p_search), '!', '!!'), '%', '!%'), '_', '!_') || '%' escape '!')
    and (p_minimum_rating is null or coalesce(r.average_rating, 0) >= p_minimum_rating)
  order by c.created_at desc, c.id desc
  limit greatest(1, least(coalesce(p_limit, 24), 100))
  offset greatest(coalesce(p_offset, 0), 0);
$$;
revoke all on function public.discover_courses(text,text,text,numeric,integer,integer)
  from public;
grant execute on function public.discover_courses(text,text,text,numeric,integer,integer)
  to anon, authenticated;

notify pgrst, 'reload schema';
