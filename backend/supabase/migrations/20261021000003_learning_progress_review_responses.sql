-- Learner course progress and lecturer review replies.
-- Learner progress is private to the learner. Mutations go through RPCs so a
-- caller cannot mark another learner's lesson complete or bypass enrollment.
create table public.course_progress (
  user_id uuid not null references auth.users(id) on delete cascade,
  lesson_id uuid not null references public.lessons(id) on delete cascade,
  completed_at timestamptz not null default now(),
  primary key (user_id, lesson_id)
);
alter table public.course_progress enable row level security;
create policy "Learners read their own course progress" on public.course_progress
  for select to authenticated using (user_id = (select auth.uid()));
grant select on public.course_progress to authenticated;

create or replace function public.set_lesson_progress(p_lesson_id uuid, p_completed boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare v_course_id uuid;
begin
  if auth.uid() is null or not public.is_approved_student() then
    raise exception 'Approved student access required';
  end if;
  select m.course_id into v_course_id
    from public.lessons l join public.course_modules m on m.id = l.module_id
    where l.id = p_lesson_id;
  if v_course_id is null or not exists (
    select 1 from public.enrollments e where e.course_id = v_course_id
      and e.user_id = auth.uid() and e.status in ('active', 'completed')
  ) then raise exception 'Active course enrollment required'; end if;
  if p_completed then
    insert into public.course_progress(user_id, lesson_id)
      values(auth.uid(), p_lesson_id)
      on conflict (user_id, lesson_id) do nothing;
  else
    delete from public.course_progress where user_id = auth.uid() and lesson_id = p_lesson_id;
  end if;
end;
$$;
revoke all on function public.set_lesson_progress(uuid,boolean) from public;
grant execute on function public.set_lesson_progress(uuid,boolean) to authenticated;

create or replace function public.course_progress_summary(p_course_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_total integer; v_completed integer;
begin
  if auth.uid() is null or not public.is_approved_student() or not exists (
    select 1 from public.enrollments e where e.course_id = p_course_id
      and e.user_id = auth.uid() and e.status in ('active', 'completed')
  ) then raise exception 'Active course enrollment required'; end if;
  select count(*) into v_total from public.lessons l
    join public.course_modules m on m.id = l.module_id where m.course_id = p_course_id;
  select count(*) into v_completed from public.course_progress p
    join public.lessons l on l.id = p.lesson_id
    join public.course_modules m on m.id = l.module_id
    where m.course_id = p_course_id and p.user_id = auth.uid();
  return jsonb_build_object('total', v_total, 'completed', v_completed,
    'percentage', case when v_total = 0 then 0 else round(v_completed * 100.0 / v_total)::integer end);
end;
$$;
revoke all on function public.course_progress_summary(uuid) from public;
grant execute on function public.course_progress_summary(uuid) to authenticated;

create or replace function public.course_completed_lessons(p_course_id uuid)
returns uuid[] language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or not public.is_approved_student() or not exists (
    select 1 from public.enrollments e where e.course_id = p_course_id
      and e.user_id = auth.uid() and e.status in ('active', 'completed')
  ) then raise exception 'Active course enrollment required'; end if;
  return array(select p.lesson_id from public.course_progress p
    join public.lessons l on l.id = p.lesson_id
    join public.course_modules m on m.id = l.module_id
    where m.course_id = p_course_id and p.user_id = auth.uid());
end;
$$;
revoke all on function public.course_completed_lessons(uuid) from public;
grant execute on function public.course_completed_lessons(uuid) to authenticated;

-- Published-course owners can inspect feedback and reply without gaining
-- access to management operations on a published course.
create policy "Course lecturers read reviews for owned courses" on public.course_reviews
  for select to authenticated using (exists (
    select 1 from public.courses c where c.id = course_id and c.owner_id = (select auth.uid())
      and public.has_app_role((select auth.uid()), 'lecturer')
      and public.is_active_user() and public.is_verified_user()
  ));
create or replace function public.lecturer_respond_to_course_review(p_review_id uuid, p_response text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_course_id uuid;
  v_student_id uuid;
  v_previous_response text;
  v_response text := trim(p_response);
begin
  if not public.has_app_role(auth.uid(), 'lecturer') or not public.is_active_user()
    or not public.is_verified_user() then raise exception 'Verified lecturer access required'; end if;
  if length(v_response) not between 3 and 2000 then
    raise exception 'Response must contain between 3 and 2000 characters'; end if;
  select r.course_id, r.student_id, r.lecturer_response
    into v_course_id, v_student_id, v_previous_response from public.course_reviews r
    join public.courses c on c.id = r.course_id
    where r.id = p_review_id and c.owner_id = auth.uid();
  if v_course_id is null then raise exception 'Review not found for your course'; end if;
  update public.course_reviews set lecturer_response = v_response where id = p_review_id;
  if v_previous_response is distinct from v_response then
    insert into public.notifications(user_id, category, title, body, metadata)
      values(v_student_id, 'course', 'Your course review received a reply',
        left(v_response, 500), jsonb_build_object('course_id', v_course_id, 'review_id', p_review_id));
  end if;
  insert into public.audit_logs(actor_id, action, target_type, target_id, metadata)
    values(auth.uid(), 'course_review_responded', 'course_review', p_review_id::text,
      jsonb_build_object('course_id', v_course_id));
end;
$$;
revoke all on function public.lecturer_respond_to_course_review(uuid,text) from public;
grant execute on function public.lecturer_respond_to_course_review(uuid,text) to authenticated;

