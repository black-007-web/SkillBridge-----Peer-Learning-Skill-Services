alter table public.profiles
  add column if not exists avatar_url text,
  add column if not exists updated_at timestamptz not null default now();

create table public.user_roles (
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null check (role in ('student', 'mentor', 'lecturer', 'admin')),
  created_at timestamptz not null default now(),
  primary key (user_id, role)
);

create table public.notification_preferences (
  user_id uuid primary key references auth.users (id) on delete cascade,
  email_notifications boolean not null default true,
  in_app_notifications boolean not null default true,
  updated_at timestamptz not null default now()
);

create table public.transactional_email_outbox (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  event_type text not null check (event_type in ('welcome')),
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  delivered_at timestamptz,
  attempts integer not null default 0,
  next_attempt_at timestamptz not null default now(),
  unique (user_id, event_type)
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  category text not null check (category in ('account', 'course', 'message', 'announcement', 'mentor')),
  title text not null,
  body text not null default '',
  created_at timestamptz not null default now(),
  read_at timestamptz,
  metadata jsonb not null default '{}'::jsonb
);
create index notifications_user_created_idx on public.notifications (user_id, created_at desc);

create function public.is_verified_user()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from auth.users
    where id = (select auth.uid())
      and email_confirmed_at is not null
  );
$$;
revoke all on function public.is_verified_user() from public;
grant execute on function public.is_verified_user() to authenticated;

alter table public.user_roles enable row level security;
alter table public.notification_preferences enable row level security;
alter table public.transactional_email_outbox enable row level security;
alter table public.notifications enable row level security;

revoke all on public.transactional_email_outbox from anon, authenticated;
grant select, update (attempts, next_attempt_at, delivered_at)
  on public.transactional_email_outbox to service_role;

create policy "Users read their own roles"
  on public.user_roles for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "Users manage their own notification preferences"
  on public.notification_preferences for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "Users create their own notification preferences"
  on public.notification_preferences for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "Users update their own notification preferences"
  on public.notification_preferences for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

grant select on public.user_roles to authenticated;
grant select on public.notification_preferences to authenticated;
grant insert (user_id, email_notifications, in_app_notifications, updated_at),
  update (email_notifications, in_app_notifications, updated_at)
  on public.notification_preferences to authenticated;
grant update (full_name, date_of_birth, avatar_url, address, nationality, gender, updated_at)
  on public.profiles to authenticated;

create policy "Users update their own profile"
  on public.profiles for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

drop policy "Users can read their own profile" on public.profiles;
create policy "Verified users read their own profile"
  on public.profiles for select to authenticated
  using ((select auth.uid()) = id and (select public.is_verified_user()));
drop policy "Users update their own profile" on public.profiles;
create policy "Verified users update their own profile"
  on public.profiles for update to authenticated
  using ((select auth.uid()) = id and (select public.is_verified_user()))
  with check ((select auth.uid()) = id and (select public.is_verified_user()));

drop policy "Users can read their own enrollments" on public.enrollments;
create policy "Verified users read their own enrollments"
  on public.enrollments for select to authenticated
  using ((select auth.uid()) = user_id and (select public.is_verified_user()));
drop policy "Users can enroll themselves in published courses" on public.enrollments;
create policy "Verified users enroll themselves in published courses"
  on public.enrollments for insert to authenticated
  with check (
    (select auth.uid()) = user_id
    and (select public.is_verified_user())
    and exists (
      select 1 from public.courses
      where courses.id = course_id and courses.is_published
    )
  );

drop policy "Users read their own roles" on public.user_roles;
create policy "Verified users read their own roles"
  on public.user_roles for select to authenticated
  using ((select auth.uid()) = user_id and (select public.is_verified_user()));
drop policy "Users manage their own notification preferences" on public.notification_preferences;
drop policy "Users create their own notification preferences" on public.notification_preferences;
drop policy "Users update their own notification preferences" on public.notification_preferences;
create policy "Verified users read their own notification preferences"
  on public.notification_preferences for select to authenticated
  using ((select auth.uid()) = user_id and (select public.is_verified_user()));
create policy "Verified users create their own notification preferences"
  on public.notification_preferences for insert to authenticated
  with check ((select auth.uid()) = user_id and (select public.is_verified_user()));
create policy "Verified users update their own notification preferences"
  on public.notification_preferences for update to authenticated
  using ((select auth.uid()) = user_id and (select public.is_verified_user()))
  with check ((select auth.uid()) = user_id and (select public.is_verified_user()));

create policy "Verified users read their own notifications"
  on public.notifications for select to authenticated
  using ((select auth.uid()) = user_id and (select public.is_verified_user()));
create policy "Verified users mark their own notifications read"
  on public.notifications for update to authenticated
  using ((select auth.uid()) = user_id and (select public.is_verified_user()))
  with check ((select auth.uid()) = user_id and (select public.is_verified_user()));
grant select on public.notifications to authenticated;
grant update (read_at) on public.notifications to authenticated;

create function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger profiles_touch_updated_at
  before update on public.profiles
  for each row execute function public.touch_updated_at();
create trigger notification_preferences_touch_updated_at
  before update on public.notification_preferences
  for each row execute function public.touch_updated_at();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_dob date;
  v_terms_at timestamptz;
begin
  begin
    v_dob := nullif(new.raw_user_meta_data ->> 'date_of_birth', '')::date;
  exception when others then
    v_dob := null;
  end;
  begin
    v_terms_at := nullif(new.raw_user_meta_data ->> 'terms_accepted_at', '')::timestamptz;
  exception when others then
    v_terms_at := null;
  end;

  insert into public.profiles (
    id, full_name, date_of_birth, gender, nationality, address,
    terms_accepted_at, avatar_url
  ) values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name', ''),
    v_dob,
    nullif(new.raw_user_meta_data ->> 'gender', ''),
    coalesce(new.raw_user_meta_data ->> 'nationality', ''),
    coalesce(new.raw_user_meta_data ->> 'address', ''),
    v_terms_at,
    null
  ) on conflict (id) do nothing;

  insert into public.user_roles (user_id, role)
  values (new.id, 'student') on conflict do nothing;

  insert into public.notification_preferences (user_id)
  values (new.id) on conflict do nothing;

  insert into public.transactional_email_outbox (user_id, event_type, payload)
  values (
    new.id,
    'welcome',
    jsonb_build_object(
      'full_name', coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name', ''),
      'email', new.email,
      'registered_at', new.created_at
    )
  ) on conflict (user_id, event_type) do nothing;
  return new;
end;
$$;

create function public.validate_profile_date_of_birth()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.date_of_birth is not null
     and new.date_of_birth > (current_date - interval '13 years')::date then
    raise exception 'Users must be at least 13 years old';
  end if;
  return new;
end;
$$;
create trigger profiles_validate_date_of_birth
  before insert or update of date_of_birth on public.profiles
  for each row execute function public.validate_profile_date_of_birth();

create function public.notify_email_verified()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.email_confirmed_at is null and new.email_confirmed_at is not null then
    insert into public.notifications (user_id, category, title, body)
    values (new.id, 'account', 'Email verified', 'Your SkillBridge account is ready to use.');
  end if;
  return new;
end;
$$;
create trigger on_auth_email_verified
  after update of email_confirmed_at on auth.users
  for each row execute function public.notify_email_verified();

insert into public.user_roles (user_id, role)
select id, 'student' from auth.users
on conflict do nothing;
insert into public.notification_preferences (user_id)
select id from auth.users
on conflict do nothing;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', false, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy "Users read own avatar objects"
  on storage.objects for select to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text and (select public.is_verified_user()));
create policy "Users upload own avatar objects"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text and (select public.is_verified_user()));
create policy "Users replace own avatar objects"
  on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text and (select public.is_verified_user()))
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text and (select public.is_verified_user()));
create policy "Users remove own avatar objects"
  on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text and (select public.is_verified_user()));
