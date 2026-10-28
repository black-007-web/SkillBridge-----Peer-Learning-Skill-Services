-- Limited lecturer analytics and roster access for courses they own.
-- Roster results omit student email, verification evidence, and other private fields.
create or replace function public.lecturer_course_insights(p_course_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.has_app_role(auth.uid(), 'lecturer') or not public.is_active_user()
    or not public.is_verified_user() or not exists (
      select 1 from public.courses c where c.id = p_course_id and c.owner_id = auth.uid()
    ) then raise exception 'Verified course owner access required'; end if;
  return jsonb_build_object(
    'active_enrollments', (select count(*) from public.enrollments e where e.course_id = p_course_id and e.status = 'active'),
    'completed_enrollments', (select count(*) from public.enrollments e where e.course_id = p_course_id and e.status = 'completed'),
    'published_reviews', (select count(*) from public.course_reviews r where r.course_id = p_course_id and r.status = 'published'),
    'average_rating', coalesce((select round(avg(r.rating)::numeric, 2) from public.course_reviews r where r.course_id = p_course_id and r.status = 'published'), 0),
    'module_count', (select count(*) from public.course_modules m where m.course_id = p_course_id),
    'lesson_count', (select count(*) from public.lessons l join public.course_modules m on m.id = l.module_id where m.course_id = p_course_id),
    'resource_count', (select count(*) from public.resources r where r.course_id = p_course_id)
  );
end;
$$;
revoke all on function public.lecturer_course_insights(uuid) from public;
grant execute on function public.lecturer_course_insights(uuid) to authenticated;

create or replace function public.lecturer_course_roster(p_course_id uuid)
returns table(enrollment_id uuid, student_id uuid, full_name text, enrolled_at timestamptz, enrollment_status text)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.has_app_role(auth.uid(), 'lecturer') or not public.is_active_user()
    or not public.is_verified_user() or not exists (
      select 1 from public.courses c where c.id = p_course_id and c.owner_id = auth.uid()
    ) then raise exception 'Verified course owner access required'; end if;
  return query
    select e.id, e.user_id, coalesce(p.full_name, ''), e.enrolled_at, e.status
    from public.enrollments e join public.profiles p on p.id = e.user_id
    where e.course_id = p_course_id and e.status in ('active', 'completed')
    order by e.enrolled_at desc;
end;
$$;
revoke all on function public.lecturer_course_roster(uuid) from public;
grant execute on function public.lecturer_course_roster(uuid) to authenticated;
