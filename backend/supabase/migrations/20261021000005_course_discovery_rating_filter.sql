-- Public discovery result set with optional aggregate-rating filtering.
create or replace function public.discover_courses(
  p_search text default '',
  p_category text default null,
  p_level text default null,
  p_minimum_rating numeric default null,
  p_limit integer default 24,
  p_offset integer default 0
) returns table(course jsonb, average_rating numeric, review_count bigint)
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
      'id', c.id, 'title', c.title, 'description', c.description,
      'category', c.category, 'level', c.level, 'instructor', c.instructor,
      'owner_id', c.owner_id, 'status', c.status, 'visibility', c.visibility,
      'cover_image_path', c.cover_image_path, 'learning_outcomes', c.learning_outcomes,
      'prerequisites', c.prerequisites, 'estimated_minutes', c.estimated_minutes,
      'created_at', c.created_at, 'published_at', c.published_at,
      'is_published', c.is_published
    ), coalesce(r.average_rating, 0)::numeric,
    coalesce(r.review_count, 0)::bigint
  from public.courses c
  left join lateral (
    select avg(cr.rating)::numeric as average_rating, count(*)::bigint as review_count
    from public.course_reviews cr
    where cr.course_id = c.id and cr.status = 'published'
  ) r on true
  where c.status = 'published' and c.visibility = 'public'
    and (coalesce(trim(p_category), '') = '' or c.category = trim(p_category))
    and (coalesce(trim(p_level), '') = '' or c.level = trim(p_level))
    and (coalesce(trim(p_search), '') = '' or
      (c.title || ' ' || c.description || ' ' || c.category || ' ' || c.instructor)
        ilike '%' || replace(replace(replace(trim(p_search), '!', '!!'), '%', '!%'), '_', '!_') || '%' escape '!')
    and (p_minimum_rating is null or coalesce(r.average_rating, 0) >= p_minimum_rating)
  order by c.created_at desc, c.id desc
  limit greatest(1, least(coalesce(p_limit, 24), 100))
  offset greatest(coalesce(p_offset, 0), 0);
$$;
revoke all on function public.discover_courses(text,text,text,numeric,integer,integer) from public;
grant execute on function public.discover_courses(text,text,text,numeric,integer,integer) to anon, authenticated;
