-- Phone numbers are profile contact data; account verification uses email OTP.
drop trigger if exists on_auth_phone_verified on auth.users;
drop function if exists public.sync_verified_phone_to_profile();
alter table public.profiles drop column if exists phone_verified_at;

create or replace function public.is_verified_user()
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
