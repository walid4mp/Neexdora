-- ============================================================================
-- Nexora backend — 004: read RPCs (chat list, feeds, profile posts, search, groups list)
-- Return shapes match what the Flutter models parse.
-- ============================================================================

-- ---------- chat list: one row per peer with last message + unread count ----------
create or replace function public.get_chats_with_last_message(current_user_id uuid)
returns table (
  id uuid, name text, image_url text, last_message text, last_message_type text,
  last_message_time timestamptz, last_message_sender_id uuid, last_message_is_read boolean,
  unread_count int, last_seen timestamptz, presence_privacy text)
language sql stable security definer set search_path = public as $$
  with mine as (
    select m.*, case when m.sender_id = current_user_id then m.receiver_id else m.sender_id end as peer_id
      from public.messages m
     where (m.sender_id = current_user_id or m.receiver_id = current_user_id)
       and not (current_user_id = any (m.deleted_for))
       and current_user_id = auth.uid()
  ), last_msg as (
    select distinct on (peer_id) * from mine order by peer_id, created_at desc, id desc
  ), unread as (
    select sender_id as peer_id, count(*)::int as n from mine
     where receiver_id = current_user_id and is_read = false group by sender_id
  )
  select u.id, u.name, u.image_url,
         coalesce(nullif(l.message_text, ''), nullif(l.caption, ''), '') as last_message,
         l.message_type, l.created_at, l.sender_id, l.is_read,
         coalesce(un.n, 0), u.last_seen, u.presence_privacy
    from last_msg l
    join public.users u on u.id = l.peer_id
    left join unread un on un.peer_id = l.peer_id
   where not public.is_blocked_between(current_user_id, u.id)
   order by l.created_at desc;
$$;

-- ---------- home feed ranking ----------
-- Score = recency decay + engagement + affinity (friends/following/own) ; "suggested" = public posts from strangers.
create or replace function public.get_ranked_home_feed(
  p_user_id uuid, p_limit int default 50, p_offset int default 0, p_as_of timestamptz default null)
returns table (post_id uuid, is_suggested_for_you boolean, as_of timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare t timestamptz := coalesce(p_as_of, now());
begin
  if p_user_id is distinct from auth.uid() then raise exception 'forbidden'; end if;
  return query
  select p.id,
         (p.author_id <> p_user_id and not connected) as suggested,
         t
    from (
      select p.*,
             (public.are_users_friends(p.author_id, p_user_id)
              or exists (select 1 from public.follows f where f.follower_id = p_user_id and f.following_id = p.author_id)) as connected
        from public.posts p
       where p.created_at <= t
         and p.created_at > t - interval '30 days'
         and p.group_id is null
         and public.can_view_post(p, p_user_id)
    ) p
   order by (
        exp(-extract(epoch from (t - p.created_at)) / 86400.0 / 2.0) * 10.0          -- recency (half-life ~1.4 days)
      + ln(1 + p.likes + 2 * p.comments)                                              -- engagement
      + case when p.author_id = p_user_id then 2.0 when p.connected then 4.0 else 0 end -- affinity
      + case when p.is_pinned then 0.5 else 0 end
   ) desc, p.id desc
   limit greatest(p_limit, 1) offset greatest(p_offset, 0);
end $$;

-- ---------- paginated id lists (keyset) ----------
create or replace function public.get_group_post_ids(
  p_group_id uuid, p_limit int default 16, p_before_created_at timestamptz default null, p_before_id uuid default null)
returns table (post_id uuid, post_created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select p.id, p.created_at
    from public.posts p
   where p.group_id = p_group_id
     and public.is_group_member(p_group_id, auth.uid())
     and (p_before_created_at is null or (p.created_at, p.id) < (p_before_created_at, p_before_id))
   order by p.created_at desc, p.id desc
   limit greatest(p_limit, 1);
$$;

create or replace function public.get_user_profile_post_ids(
  p_user_id uuid, p_limit int default 16, p_before_is_pinned boolean default null,
  p_before_created_at timestamptz default null, p_before_id uuid default null)
returns table (post_id uuid, post_is_pinned boolean, post_created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select p.id, p.is_pinned, p.created_at
    from public.posts p
   where p.author_id = p_user_id
     and p.group_id is null
     and public.can_view_post(p, auth.uid())
     and (p_before_created_at is null or (p.is_pinned, p.created_at, p.id) < (coalesce(p_before_is_pinned, false), p_before_created_at, p_before_id))
   order by p.is_pinned desc, p.created_at desc, p.id desc
   limit greatest(p_limit, 1);
$$;

create or replace function public.get_profile_media_count(p_user_id uuid)
returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from public.posts p
   where p.author_id = p_user_id and p.group_id is null
     and (p.image_url is not null or p.video_url is not null or p.gif_url is not null)
     and public.can_view_post(p, auth.uid());
$$;

create or replace function public.search_posts(p_query text, p_user_id uuid, p_limit int default 12, p_offset int default 0)
returns table (id uuid) language sql stable security definer set search_path = public as $$
  select p.id from public.posts p
   where p.text ilike '%' || replace(replace(trim(p_query), '%', '\%'), '_', '\_') || '%'
     and public.can_view_post(p, auth.uid())
   order by p.created_at desc, p.id desc
   limit greatest(p_limit, 1) offset greatest(p_offset, 0);
$$;

-- ---------- groups list ----------
create or replace function public.get_groups_member_counts(p_group_ids uuid[])
returns table (group_id uuid, members_count int) language sql stable security definer set search_path = public as $$
  select m.group_id, count(*)::int from public.group_members m
   where m.group_id = any (p_group_ids) and m.membership_status = 'active' group by m.group_id;
$$;

create or replace function public.get_my_groups(p_user_id uuid)
returns table (
  id uuid, name text, avatar_url text, title text, created_by uuid, created_at timestamptz, cover_url text,
  is_member boolean, last_message text, last_message_sender_id uuid, last_message_sender_name text,
  last_message_type text, last_message_at timestamptz, last_message_target_id uuid, last_message_target_name text,
  unread_count int, is_blocked boolean, is_muted boolean)
language sql stable security definer set search_path = public as $$
  select g.id, g.name, g.avatar_url, g.title, g.created_by, g.created_at, g.cover_url,
         true,
         coalesce(nullif(lm.text, ''), nullif(lm.caption, ''), ''),
         lm.sender_id, su.name, coalesce(lm.message_type, 'text'), lm.created_at, null::uuid, null::text,
         coalesce((select count(*)::int from public.group_messages gm
                    where gm.group_id = g.id and gm.sender_id is distinct from p_user_id
                      and gm.created_at > m.joined_at
                      and not (p_user_id = any (gm.deleted_for))
                      and not exists (select 1 from public.group_message_reads r where r.message_id = gm.id and r.user_id = p_user_id and r.read_at is not null)), 0),
         m.is_blocked, m.is_muted
    from public.group_members m
    join public.groups g on g.id = m.group_id
    left join lateral (select * from public.group_messages x where x.group_id = g.id and not (p_user_id = any (x.deleted_for))
                        order by x.created_at desc limit 1) lm on true
    left join public.users su on su.id = lm.sender_id
   where m.user_id = p_user_id and m.membership_status = 'active' and p_user_id = auth.uid()
   order by coalesce(lm.created_at, g.created_at) desc;
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
