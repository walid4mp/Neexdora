-- ============================================================================
-- Nexora backend — 005: people (discover/search/friends/profile) + group members
-- ============================================================================

do $$ begin
  create type public.person_row as (
    id uuid, name text, email text, image_url text, image_public_id text,
    background_image_url text, background_image_public_id text, title text, tagline text,
    is_tagline_hidden boolean, last_seen timestamptz, presence_privacy text, presence_visible_to uuid[],
    social_links jsonb, is_deleted boolean, deleted_at timestamptz,
    friendship_status text, friendship_id uuid, is_following boolean, follows_me boolean,
    mutual_friends_count int, mutual_friends_preview jsonb, mutual_groups_count int,
    total_friends_count int, total_count int);
exception when duplicate_object then null; end $$;

create or replace function public._friend_ids(u uuid) returns setof uuid
language sql stable security definer set search_path = public as $$
  select case when requester_id = u then addressee_id else requester_id end
    from public.friendships where status = 'accepted' and (requester_id = u or addressee_id = u);
$$;

-- Core builder. mode: 'discover' | 'search' | 'friends_of'
create or replace function public._people(
  p_viewer uuid, p_mode text, p_query text, p_target uuid, p_limit int, p_offset int)
returns setof public.person_row language sql stable security definer set search_path = public as $$
  with base as (
    select u.*,
           fs.status as f_status, fs.fid as f_id,
           (case when p_mode = 'friends_of' then ft.fid else fs.fid end) as list_fid
      from public.users u
      left join lateral (
        select case when f.status = 'accepted' then 'accepted' when f.requester_id = p_viewer then 'pending_sent' else 'pending_received' end as status, f.id as fid
          from public.friendships f
         where f.status in ('accepted','pending')
           and ((f.requester_id = p_viewer and f.addressee_id = u.id) or (f.requester_id = u.id and f.addressee_id = p_viewer)) limit 1) fs on true
      left join lateral (
        select f.id as fid from public.friendships f
         where f.status = 'accepted' and p_target is not null
           and ((f.requester_id = p_target and f.addressee_id = u.id) or (f.requester_id = u.id and f.addressee_id = p_target)) limit 1) ft on true
     where u.id <> p_viewer and u.is_deleted = false and p_viewer = auth.uid()
       and not public.is_blocked_between(p_viewer, u.id)
       and (p_query is null or u.name ilike '%' || replace(replace(trim(p_query), '%', '\%'), '_', '\_') || '%')
       and case p_mode
             when 'discover'   then coalesce(fs.status, '') <> 'accepted'
             when 'friends_of' then ft.fid is not null
             else true end
  ), enriched as (
    select b.*,
      (select count(*)::int from (select x from public._friend_ids(p_viewer) x intersect select y from public._friend_ids(b.id) y) z) as mf_count,
      (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'name', x.name, 'image_url', x.image_url)), '[]'::jsonb)
         from (select uu.id, uu.name, uu.image_url from public.users uu
                where uu.id in (select a from public._friend_ids(p_viewer) a intersect select c from public._friend_ids(b.id) c) limit 3) x) as mf_preview,
      (select count(*)::int from public.group_members m1 join public.group_members m2 on m2.group_id = m1.group_id
        where m1.user_id = p_viewer and m2.user_id = b.id and m1.membership_status = 'active' and m2.membership_status = 'active') as mg_count,
      (select count(*)::int from public._friend_ids(b.id)) as tf_count
    from base b
  )
  select e.id, e.name, e.email, e.image_url, e.image_public_id, e.background_image_url, e.background_image_public_id,
         e.title, e.tagline, e.is_tagline_hidden, e.last_seen, e.presence_privacy, e.presence_visible_to, e.social_links,
         e.is_deleted, e.deleted_at,
         coalesce(e.f_status, 'none'), e.list_fid,
         exists (select 1 from public.follows f where f.follower_id = p_viewer and f.following_id = e.id),
         exists (select 1 from public.follows f where f.follower_id = e.id and f.following_id = p_viewer),
         e.mf_count, e.mf_preview, e.mg_count, e.tf_count,
         (count(*) over ())::int
    from enriched e
   order by case when p_mode = 'discover' then e.mf_count end desc nulls last, lower(e.name), e.id
   limit greatest(p_limit, 1) offset greatest(p_offset, 0);
$$;

create or replace function public.get_discover_people(p_current_user_id uuid, p_limit int default 20, p_offset int default 0)
returns setof public.person_row language sql stable security definer set search_path = public as $$
  select * from public._people(p_current_user_id, 'discover', null, null, p_limit, p_offset);
$$;
create or replace function public.search_people(p_query text, p_current_user_id uuid, p_limit int default 20, p_offset int default 0)
returns setof public.person_row language sql stable security definer set search_path = public as $$
  select * from public._people(p_current_user_id, 'search', p_query, null, p_limit, p_offset);
$$;
create or replace function public.get_user_friends(p_user_id uuid, p_limit int default 30, p_offset int default 0)
returns setof public.person_row language sql stable security definer set search_path = public as $$
  select * from public._people(auth.uid(), 'friends_of', null, p_user_id, p_limit, p_offset);
$$;
create or replace function public.search_friends(p_query text, p_user_id uuid, p_limit int default 30, p_offset int default 0)
returns setof public.person_row language sql stable security definer set search_path = public as $$
  select * from public._people(auth.uid(), 'friends_of', p_query, p_user_id, p_limit, p_offset);
$$;

-- Friends-of-self never includes the viewer; viewing your own list works because _people filters u.id <> viewer only.

create or replace function public.get_profile_overview(p_viewed_user_id uuid, p_current_user_id uuid)
returns table (posts_count int, followers_count int, following_count int, friends_count int, mutual_friends_count int,
               friendship_status text, friendship_id uuid, is_following boolean, follows_me boolean)
language sql stable security definer set search_path = public as $$
  select
    (select count(*)::int from public.posts p where p.author_id = p_viewed_user_id and p.group_id is null and public.can_view_post(p, auth.uid())),
    (select count(*)::int from public.follows where following_id = p_viewed_user_id),
    (select count(*)::int from public.follows where follower_id = p_viewed_user_id),
    (select count(*)::int from public._friend_ids(p_viewed_user_id)),
    case when p_viewed_user_id = p_current_user_id then 0 else
      (select count(*)::int from (select a from public._friend_ids(p_current_user_id) a intersect select c from public._friend_ids(p_viewed_user_id) c) z) end,
    coalesce((select case when f.status = 'accepted' then 'accepted' when f.requester_id = p_current_user_id then 'pending_sent' else 'pending_received' end
                from public.friendships f where f.status in ('accepted','pending')
                 and ((f.requester_id = p_current_user_id and f.addressee_id = p_viewed_user_id) or (f.requester_id = p_viewed_user_id and f.addressee_id = p_current_user_id)) limit 1), 'none'),
    (select f.id from public.friendships f where f.status in ('accepted','pending')
        and ((f.requester_id = p_current_user_id and f.addressee_id = p_viewed_user_id) or (f.requester_id = p_viewed_user_id and f.addressee_id = p_current_user_id)) limit 1),
    exists (select 1 from public.follows where follower_id = p_current_user_id and following_id = p_viewed_user_id),
    exists (select 1 from public.follows where follower_id = p_viewed_user_id and following_id = p_current_user_id)
   where p_current_user_id = auth.uid();
$$;

create or replace function public.get_profile_mutuals(p_viewed_user_id uuid)
returns table (mutual_friends_count int, mutual_friends_preview jsonb, mutual_groups_count int, mutual_groups_preview jsonb)
language sql stable security definer set search_path = public as $$
  with mf as (select a as id from public._friend_ids(auth.uid()) a intersect select c from public._friend_ids(p_viewed_user_id) c),
       mg as (select g.id, g.name from public.groups g
               where public.is_group_member(g.id, auth.uid()) and public.is_group_member(g.id, p_viewed_user_id))
  select (select count(*)::int from mf),
         (select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'name', u.name, 'image_url', u.image_url)), '[]'::jsonb)
            from (select * from public.users where id in (select id from mf) limit 5) u),
         (select count(*)::int from mg),
         (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name)), '[]'::jsonb) from (select * from mg limit 5) x);
$$;

-- ---------- group members / stats / search ----------
create or replace function public.get_group_members_paginated(p_group_id uuid, p_current_user_id uuid, p_page int default 0, p_page_size int default 30)
returns table (group_id uuid, user_id uuid, role text, joined_at timestamptz, user_name text, user_avatar text, total_count int)
language sql stable security definer set search_path = public as $$
  select m.group_id, m.user_id, m.role, m.joined_at, u.name, u.image_url, (count(*) over ())::int
    from public.group_members m join public.users u on u.id = m.user_id
   where m.group_id = p_group_id and m.membership_status = 'active'
     and public.is_group_member(p_group_id, auth.uid())
   order by case m.role when 'owner' then 0 when 'admin' then 1 else 2 end, lower(u.name), m.user_id
   limit greatest(p_page_size, 1) offset greatest(p_page, 0) * greatest(p_page_size, 1);
$$;

create or replace function public.get_group_header_stats(p_group_id uuid)
returns table (total_members int, online_count int) language sql stable security definer set search_path = public as $$
  select count(*)::int,
         count(*) filter (where p.is_online and p.updated_at > now() - interval '2 minutes')::int
    from public.group_members m left join public.user_presence p on p.user_id = m.user_id
   where m.group_id = p_group_id and m.membership_status = 'active' and public.is_group_member(p_group_id, auth.uid());
$$;

create or replace function public.search_my_groups(p_query text, p_user_id uuid, p_limit int default 20, p_offset int default 0)
returns table (
  id uuid, name text, avatar_url text, title text, created_by uuid, created_at timestamptz, cover_url text,
  is_member boolean, last_message text, last_message_sender_id uuid, last_message_sender_name text,
  last_message_type text, last_message_at timestamptz, last_message_target_id uuid, last_message_target_name text,
  unread_count int, is_blocked boolean, is_muted boolean)
language sql stable security definer set search_path = public as $$
  select * from public.get_my_groups(p_user_id) g
   where g.name ilike '%' || replace(replace(trim(p_query), '%', '\%'), '_', '\_') || '%'
   limit greatest(p_limit, 1) offset greatest(p_offset, 0);
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
