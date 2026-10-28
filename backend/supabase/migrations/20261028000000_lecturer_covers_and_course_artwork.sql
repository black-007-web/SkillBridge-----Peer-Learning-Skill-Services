alter table public.profiles
  add column if not exists cover_image_url text;

grant update (cover_image_url) on public.profiles to authenticated;

drop function if exists public.public_verified_lecturers();

create function public.public_verified_lecturers()
returns table (
  id uuid,
  full_name text,
  avatar_url text,
  cover_image_url text,
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
    p.cover_image_url,
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
  order by p.full_name, p.id;
$$;
revoke all on function public.public_verified_lecturers() from public;
grant execute on function public.public_verified_lecturers() to anon, authenticated;

notify pgrst, 'reload schema';
