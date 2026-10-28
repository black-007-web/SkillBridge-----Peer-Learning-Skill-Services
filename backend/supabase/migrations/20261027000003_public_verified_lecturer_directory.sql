create or replace function public.public_verified_lecturers()
returns table (
  id uuid,
  full_name text,
  avatar_url text,
  bio text,
  social_links jsonb,
  "position" text,
  skills text[],
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    p.id,
    p.full_name,
    p.avatar_url,
    p.bio,
    p.social_links,
    p.position,
    p.skills,
    p.created_at
  from public.profiles p
  join auth.users u on u.id = p.id
  where p.account_status = 'active'
    and u.email_confirmed_at is not null
    and exists (
      select 1
      from public.user_roles r
      where r.user_id = p.id
        and r.role = 'lecturer'
    )
    and exists (
      select 1
      from public.lecturer_applications a
      where a.user_id = p.id
        and a.status = 'approved'
    )
  order by p.full_name, p.id;
$$;
revoke all on function public.public_verified_lecturers() from public;
grant execute on function public.public_verified_lecturers() to anon, authenticated;

create or replace function public.is_public_verified_lecturer_avatar(p_user_id text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when coalesce(p_user_id, '') ~*
      '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then exists (
      select 1
      from public.profiles p
      join auth.users u on u.id = p.id
      where p.id = p_user_id::uuid
        and p.account_status = 'active'
        and u.email_confirmed_at is not null
        and exists (
          select 1 from public.user_roles r
          where r.user_id = p.id and r.role = 'lecturer'
        )
        and exists (
          select 1 from public.lecturer_applications a
          where a.user_id = p.id and a.status = 'approved'
        )
    )
    else false
  end;
$$;
revoke all on function public.is_public_verified_lecturer_avatar(text) from public;
grant execute on function public.is_public_verified_lecturer_avatar(text)
  to anon, authenticated;

drop policy if exists "Public can read verified lecturer avatars" on storage.objects;
create policy "Public can read verified lecturer avatars"
  on storage.objects for select to anon, authenticated
  using (
    bucket_id = 'avatars'
    and public.is_public_verified_lecturer_avatar((storage.foldername(name))[1])
  );

notify pgrst, 'reload schema';
