alter table public.profiles
  add column if not exists phone_number text,
  add column if not exists phone_verified_at timestamptz,
  add column if not exists bio text not null default '',
  add column if not exists social_links jsonb not null default '{}'::jsonb,
  add column if not exists position text not null default '',
  add column if not exists skills text[] not null default '{}';

alter table public.profiles
  drop constraint if exists profiles_social_links_object_check,
  add constraint profiles_social_links_object_check
    check (jsonb_typeof(social_links) = 'object'),
  drop constraint if exists profiles_bio_length_check,
  add constraint profiles_bio_length_check
    check (length(bio) <= 2000),
  drop constraint if exists profiles_position_length_check,
  add constraint profiles_position_length_check
    check (length(position) <= 160),
  drop constraint if exists profiles_skills_count_check,
  add constraint profiles_skills_count_check
    check (cardinality(skills) <= 30);

grant update (phone_number, bio, social_links, position, skills)
  on public.profiles to authenticated;

create or replace function public.clear_profile_phone_verification_on_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.phone_number is distinct from old.phone_number then
    new.phone_verified_at := null;
  end if;
  return new;
end;
$$;

create trigger profiles_clear_phone_verification_on_change
  before update of phone_number on public.profiles
  for each row execute function public.clear_profile_phone_verification_on_change();

drop policy if exists "Published courses are discoverable" on public.courses;
create policy "Published courses are discoverable"
  on public.courses for select to anon, authenticated
  using (status = 'published' or owner_id = (select auth.uid()) or public.is_admin());

drop policy if exists "Approved students enroll in published courses" on public.enrollments;
create policy "Approved students enroll in published courses"
  on public.enrollments for insert to authenticated
  with check (
    user_id = (select auth.uid()) and status = 'active'
    and public.is_approved_student()
    and exists (
      select 1 from public.courses c
      where c.id = course_id and c.status = 'published'
    )
  );

create or replace function public.can_manage_course(p_course_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.is_admin() or exists (
    select 1 from public.courses c
    where c.id = p_course_id and c.owner_id = (select auth.uid())
      and public.has_app_role((select auth.uid()), 'lecturer')
      and public.is_active_user() and public.is_verified_user()
      and c.status in ('draft', 'rejected', 'unpublished', 'published')
  );
$$;
revoke all on function public.can_manage_course(uuid) from public;
grant execute on function public.can_manage_course(uuid) to authenticated;

drop policy if exists "Owners and admins update courses" on public.courses;
create policy "Owners and admins update courses"
  on public.courses for update to authenticated
  using (
    public.is_admin()
    or (
      owner_id = (select auth.uid())
      and public.has_app_role((select auth.uid()), 'lecturer')
    )
  )
  with check (
    public.is_admin()
    or (
      owner_id = (select auth.uid())
      and public.has_app_role((select auth.uid()), 'lecturer')
    )
  );

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
  if not ((old.status = new.status and new.status in ('draft','rejected','unpublished','published'))
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

create or replace function public.discover_courses(
  p_search text default '',
  p_category text default null,
  p_level text default null,
  p_minimum_rating numeric default null,
  p_limit integer default 24,
  p_offset integer default 0
) returns table(course jsonb, average_rating numeric, review_count bigint)
language sql stable security definer set search_path = '' as $$
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
revoke all on function public.discover_courses(text,text,text,numeric,integer,integer) from public;
grant execute on function public.discover_courses(text,text,text,numeric,integer,integer) to anon, authenticated;
