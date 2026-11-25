-- ============================================================================
-- Nexora backend — 006: stories overview/viewers, reels, group profile/requests, mutual groups
-- ============================================================================
alter table public.reels_cache add column if not exists category text;
create index if not exists reels_cache_cat_idx on public.reels_cache (category);

-- ---------- stories ----------
create or replace function public.get_story_viewers(p_story_id uuid)
returns table (viewer_id uuid, user_name text, user_image_url text, reaction text, viewed_at timestamptz, is_online boolean, last_seen timestamptz)
language sql stable security definer set search_path = public as $$
  select v.viewer_id, u.name, u.image_url, r.reaction, v.viewed_at,
         coalesce(p.is_online and p.updated_at > now() - interval '2 minutes', false), u.last_seen
    from public.story_views v
    join public.stories s on s.id = v.story_id and s.author_id = auth.uid()
    join public.users u on u.id = v.viewer_id
    left join public.story_reactions r on r.story_id = v.story_id and r.user_id = v.viewer_id
    left join public.user_presence p on p.user_id = v.viewer_id
   where v.story_id = p_story_id
   order by v.viewed_at desc;
$$;

create or replace function public.get_my_stories_overview()
returns table (story_id uuid, view_count int, reaction_count int, reactions jsonb)
language sql stable security definer set search_path = public as $$
  select s.id,
         (select count(*)::int from public.story_views v where v.story_id = s.id),
         (select count(*)::int from public.story_reactions r where r.story_id = s.id),
         (select coalesce(jsonb_agg(jsonb_build_object('user_id', u.id, 'user_name', u.name, 'user_image_url', u.image_url, 'reaction', r.reaction) order by r.created_at desc), '[]'::jsonb)
            from public.story_reactions r join public.users u on u.id = r.user_id where r.story_id = s.id)
    from public.stories s
   where s.author_id = auth.uid() and s.created_at > now() - interval '24 hours';
$$;

-- ---------- reels ----------
create or replace function public._reel_json(r public.reels_cache) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', r.id, 'youtube_video_id', r.youtube_video_id, 'title', coalesce(r.title, ''), 'description', r.description,
    'thumbnail_url', coalesce(r.thumbnail_url, ''), 'original_like_count', coalesce(r.original_like_count, 0),
    'original_view_count', coalesce(r.original_view_count, 0), 'published_at', coalesce(r.published_at, r.cached_at),
    'reel_channels', (select jsonb_build_object('id', c.id, 'youtube_channel_id', c.youtube_channel_id, 'channel_name', coalesce(c.channel_name, ''),
                                                 'channel_avatar_url', c.channel_avatar_url, 'is_active', c.is_active)
                        from public.reel_channels c where c.id = r.channel_id));
$$;

-- returns rows whose columns match ReelModel.fromMap (nested reel_channels object)
create or replace function public.get_balanced_reels_feed(
  limit_per_request int default 30, exclude_video_ids text[] default '{}',
  preferred_categories text[] default null, category_filter text default null)
returns table (id uuid, youtube_video_id text, title text, description text, thumbnail_url text,
               original_like_count bigint, original_view_count bigint, published_at timestamptz, reel_channels jsonb)
language sql stable security definer set search_path = public as $$
  select r.id, r.youtube_video_id, coalesce(r.title,''), r.description, coalesce(r.thumbnail_url,''),
         coalesce(r.original_like_count,0), coalesce(r.original_view_count,0), coalesce(r.published_at, r.cached_at),
         public._reel_json(r) -> 'reel_channels'
    from public.reels_cache r
    join public.reel_channels c on c.id = r.channel_id and c.is_active
   where not (r.youtube_video_id = any (coalesce(exclude_video_ids, '{}')))
     and (category_filter is null or category_filter = '' or r.category = category_filter)
   order by (case when preferred_categories is not null and r.category = any (preferred_categories) then 0 else 1 end), random()
   limit greatest(limit_per_request, 1);
$$;

create or replace function public.search_reels(p_query text, p_limit int default 30, p_offset int default 0)
returns table (id uuid, youtube_video_id text, title text, description text, thumbnail_url text,
               original_like_count bigint, original_view_count bigint, published_at timestamptz, reel_channels jsonb)
language sql stable security definer set search_path = public as $$
  select r.id, r.youtube_video_id, coalesce(r.title,''), r.description, coalesce(r.thumbnail_url,''),
         coalesce(r.original_like_count,0), coalesce(r.original_view_count,0), coalesce(r.published_at, r.cached_at),
         public._reel_json(r) -> 'reel_channels'
    from public.reels_cache r join public.reel_channels c on c.id = r.channel_id and c.is_active
   where r.title ilike '%' || replace(replace(trim(p_query), '%', '\%'), '_', '\_') || '%'
      or c.channel_name ilike '%' || replace(replace(trim(p_query), '%', '\%'), '_', '\_') || '%'
   order by r.original_view_count desc nulls last
   limit greatest(p_limit, 1) offset greatest(p_offset, 0);
$$;

-- ---------- group profile / join requests / mutual groups ----------
create or replace function public.get_group_profile(p_group_id uuid)
returns table (id uuid, name text, title text, description text, avatar_url text, cover_url text, created_at timestamptz,
               created_by uuid, creator_name text, who_can_post text, members_count int, posts_count int, media_count int,
               is_member boolean, my_role text, my_request_status text, pending_requests_count int)
language sql stable security definer set search_path = public as $$
  select g.id, g.name, g.title, g.description, g.avatar_url, g.cover_url, g.created_at, g.created_by, cu.name, g.who_can_post,
         (select count(*)::int from public.group_members m where m.group_id = g.id and m.membership_status = 'active'),
         (select count(*)::int from public.posts p where p.group_id = g.id and public.is_group_member(g.id, auth.uid())),
         (select count(*)::int from public.posts p where p.group_id = g.id and public.is_group_member(g.id, auth.uid())
              and (p.image_url is not null or p.video_url is not null or p.gif_url is not null)),
         public.is_group_member(g.id, auth.uid()),
         (select m.role from public.group_members m where m.group_id = g.id and m.user_id = auth.uid() and m.membership_status = 'active'),
         (select r.status from public.group_join_requests r where r.group_id = g.id and r.user_id = auth.uid()),
         case when public.is_group_admin(g.id, auth.uid())
              then (select count(*)::int from public.group_join_requests r where r.group_id = g.id and r.status = 'pending') else 0 end
    from public.groups g left join public.users cu on cu.id = g.created_by
   where g.id = p_group_id;
$$;

create or replace function public.get_group_join_requests(p_group_id uuid)
returns table (id uuid, user_id uuid, user_name text, user_avatar text, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select r.id, r.user_id, u.name, u.image_url, r.created_at
    from public.group_join_requests r join public.users u on u.id = r.user_id
   where r.group_id = p_group_id and r.status = 'pending' and public.is_group_admin(p_group_id, auth.uid())
   order by r.created_at;
$$;

create or replace function public.get_mutual_groups(p_current_user_id uuid, p_other_user_id uuid)
returns table (id uuid, name text, avatar_url text, title text, created_by uuid, created_at timestamptz, cover_url text,
               members_count int)
language sql stable security definer set search_path = public as $$
  select g.id, g.name, g.avatar_url, g.title, g.created_by, g.created_at, g.cover_url,
         (select count(*)::int from public.group_members m where m.group_id = g.id and m.membership_status = 'active')
    from public.groups g
   where p_current_user_id = auth.uid()
     and public.is_group_member(g.id, p_current_user_id) and public.is_group_member(g.id, p_other_user_id)
   order by g.name;
$$;

do $$
declare r record;
begin
  for r in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.prosecdef loop
    execute format('revoke all on function %s from public', r.sig);
    execute format('grant execute on function %s to authenticated, service_role', r.sig);
  end loop;
end $$;
grant execute on function public.get_app_system_status(text) to anon;
grant execute on function public.incident_report_batch(jsonb) to anon;
