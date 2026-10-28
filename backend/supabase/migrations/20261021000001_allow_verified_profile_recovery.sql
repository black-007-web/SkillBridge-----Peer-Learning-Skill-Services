-- Allow a verified user to repair a missing profile row for their own Auth ID.
-- This remains restricted to the authenticated user and verified-email policy.
grant insert (
  id,
  full_name,
  date_of_birth,
  phone_number,
  gender,
  nationality,
  address,
  terms_accepted_at,
  avatar_url,
  updated_at
)
on public.profiles to authenticated;

drop policy if exists "Verified users create their own profile"
  on public.profiles;
create policy "Verified users create their own profile"
  on public.profiles for insert to authenticated
  with check (
    (select auth.uid()) = id
    and (select public.is_verified_user())
  );
