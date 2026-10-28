alter table public.profiles
  add column if not exists phone_number text,
  add column if not exists phone_verified_at timestamptz;

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
      and phone_confirmed_at is not null
  );
$$;
revoke all on function public.is_verified_user() from public;
grant execute on function public.is_verified_user() to authenticated;

create function public.copy_signup_phone_to_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles
  set phone_number = nullif(new.raw_user_meta_data ->> 'phone_number', '')
  where id = new.id;
  return new;
end;
$$;
revoke all on function public.copy_signup_phone_to_profile() from public;

create trigger z_copy_signup_phone_to_profile
  after insert on auth.users
  for each row execute function public.copy_signup_phone_to_profile();

update public.profiles as p
set phone_number = coalesce(
      u.phone,
      nullif(u.raw_user_meta_data ->> 'phone_number', '')
    ),
    phone_verified_at = u.phone_confirmed_at
from auth.users as u
where p.id = u.id
  and (
    p.phone_number is null
    or (u.phone_confirmed_at is not null and p.phone_verified_at is null)
  )
  and coalesce(u.phone, nullif(u.raw_user_meta_data ->> 'phone_number', '')) is not null;

create function public.sync_verified_phone_to_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.phone_confirmed_at is null and new.phone_confirmed_at is not null then
    update public.profiles
    set phone_number = new.phone,
        phone_verified_at = new.phone_confirmed_at
    where id = new.id;
  end if;
  return new;
end;
$$;
revoke all on function public.sync_verified_phone_to_profile() from public;

create trigger on_auth_phone_verified
  after update of phone_confirmed_at on auth.users
  for each row execute function public.sync_verified_phone_to_profile();
