alter table public.profiles
  add column date_of_birth date,
  add column gender text,
  add column nationality text not null default '',
  add column address text not null default '',
  add column terms_accepted_at timestamptz;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_date_of_birth date;
  v_terms_accepted_at timestamptz;
begin
  begin
    v_date_of_birth := nullif(new.raw_user_meta_data ->> 'date_of_birth', '')::date;
  exception when others then
    v_date_of_birth := null;
  end;

  begin
    v_terms_accepted_at := nullif(new.raw_user_meta_data ->> 'terms_accepted_at', '')::timestamptz;
  exception when others then
    v_terms_accepted_at := null;
  end;

  insert into public.profiles (
    id,
    full_name,
    date_of_birth,
    gender,
    nationality,
    address,
    terms_accepted_at
  )
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    v_date_of_birth,
    nullif(new.raw_user_meta_data ->> 'gender', ''),
    coalesce(new.raw_user_meta_data ->> 'nationality', ''),
    coalesce(new.raw_user_meta_data ->> 'address', ''),
    v_terms_accepted_at
  )
  on conflict (id) do nothing;
  return new;
end;
$$;
