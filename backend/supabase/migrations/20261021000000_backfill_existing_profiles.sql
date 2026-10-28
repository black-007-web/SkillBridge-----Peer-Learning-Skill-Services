-- Users created before the profile trigger was installed need a profiles row.
-- Keep the captured registration values and let column defaults supply IDs/times.
insert into public.profiles (
  id,
  full_name,
  date_of_birth,
  phone_number,
  gender,
  nationality,
  address,
  terms_accepted_at,
  avatar_url
)
select
  u.id,
  coalesce(u.raw_user_meta_data ->> 'full_name', u.raw_user_meta_data ->> 'name', ''),
  nullif(u.raw_user_meta_data ->> 'date_of_birth', '')::date,
  nullif(u.raw_user_meta_data ->> 'phone_number', ''),
  nullif(u.raw_user_meta_data ->> 'gender', ''),
  coalesce(u.raw_user_meta_data ->> 'nationality', ''),
  coalesce(u.raw_user_meta_data ->> 'address', ''),
  nullif(u.raw_user_meta_data ->> 'terms_accepted_at', '')::timestamptz,
  null
from auth.users as u
left join public.profiles as p on p.id = u.id
where p.id is null
on conflict (id) do nothing;
