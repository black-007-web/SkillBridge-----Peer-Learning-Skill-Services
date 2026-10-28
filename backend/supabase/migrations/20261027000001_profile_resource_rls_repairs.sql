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

update storage.buckets
set allowed_mime_types = array(
  select distinct mime_type
  from unnest(coalesce(allowed_mime_types, '{}'::text[]) || array[
    'image/gif',
    'video/quicktime',
    'video/webm'
  ]) as mime_type
)
where id = 'course-resources';
