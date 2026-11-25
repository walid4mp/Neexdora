-- ============================================================================
-- Nexora backend — 002: helper functions, Row Level Security, Realtime
-- ============================================================================

-- ---------- helpers (security definer => no RLS recursion) ----------
create or replace function public.is_group_member(p_group_id uuid, p_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from group_members
                 where group_id = p_group_id and user_id = p_user_id and membership_status = 'active');
$$;

create or replace function public.is_group_admin(p_group_id uuid, p_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from group_members
                 where group_id = p_group_id and user_id = p_user_id
                   and membership_status = 'active' and role in ('owner','admin'));
$$;

create or replace function public.are_users_friends(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from friendships f where f.status = 'accepted'
                 and ((f.requester_id = a and f.addressee_id = b) or (f.requester_id = b and f.addressee_id = a)));
$$;

create or replace function public.is_blocked_between(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from blocked_users
                 where (blocker_id = a and blocked_id = b) or (blocker_id = b and blocked_id = a));
$$;

create or replace function public.can_view_post(p_post public.posts, p_viewer uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when p_post.author_id = p_viewer then true
    when is_blocked_between(p_post.author_id, p_viewer) then false
    when p_post.group_id is not null then is_group_member(p_post.group_id, p_viewer)
    when p_post.privacy_type = 'public' then true
    when p_post.privacy_type = 'friends' then are_users_friends(p_post.author_id, p_viewer)
    else exists (select 1 from post_allowed_viewers v where v.post_id = p_post.id and v.user_id = p_viewer)
  end;
$$;

create or replace function public.can_view_story(p_story public.stories, p_viewer uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when p_story.author_id = p_viewer then true
    when is_blocked_between(p_story.author_id, p_viewer) then false
    when p_story.privacy_type = 'public' then true
    when p_story.privacy_type = 'friends' then are_users_friends(p_story.author_id, p_viewer)
    else exists (select 1 from story_allowed_viewers v where v.story_id = p_story.id and v.user_id = p_viewer)
  end;
$$;

-- ---------- enable RLS everywhere ----------
do $$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- ---------- users / presence ----------
drop policy if exists users_select on public.users;
create policy users_select on public.users for select to authenticated using (true);
drop policy if exists users_insert on public.users;
create policy users_insert on public.users for insert to authenticated with check (id = auth.uid());
drop policy if exists users_update on public.users;
create policy users_update on public.users for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists presence_select on public.user_presence;
create policy presence_select on public.user_presence for select to authenticated using (true);
drop policy if exists presence_write on public.user_presence;
create policy presence_write on public.user_presence for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------- social graph ----------
drop policy if exists fr_select on public.friendships;
create policy fr_select on public.friendships for select to authenticated using (requester_id = auth.uid() or addressee_id = auth.uid() or status = 'accepted');
drop policy if exists fr_insert on public.friendships;
create policy fr_insert on public.friendships for insert to authenticated with check (requester_id = auth.uid());
drop policy if exists fr_update on public.friendships;
create policy fr_update on public.friendships for update to authenticated using (addressee_id = auth.uid() or requester_id = auth.uid());
drop policy if exists fr_delete on public.friendships;
create policy fr_delete on public.friendships for delete to authenticated using (addressee_id = auth.uid() or requester_id = auth.uid());

drop policy if exists follows_select on public.follows;
create policy follows_select on public.follows for select to authenticated using (true);
drop policy if exists follows_write on public.follows;
create policy follows_write on public.follows for all to authenticated using (follower_id = auth.uid()) with check (follower_id = auth.uid());

drop policy if exists blocks_all on public.blocked_users;
create policy blocks_all on public.blocked_users for all to authenticated using (blocker_id = auth.uid()) with check (blocker_id = auth.uid());
drop policy if exists blocks_seen on public.blocked_users;
create policy blocks_seen on public.blocked_users for select to authenticated using (blocked_id = auth.uid());

-- ---------- groups ----------
drop policy if exists groups_select on public.groups;
create policy groups_select on public.groups for select to authenticated using (true);
drop policy if exists groups_insert on public.groups;
create policy groups_insert on public.groups for insert to authenticated with check (created_by = auth.uid());
drop policy if exists groups_update on public.groups;
create policy groups_update on public.groups for update to authenticated using (is_group_admin(id));
drop policy if exists groups_delete on public.groups;
create policy groups_delete on public.groups for delete to authenticated using (created_by = auth.uid());

drop policy if exists gm_select on public.group_members;
create policy gm_select on public.group_members for select to authenticated using (user_id = auth.uid() or is_group_member(group_id));
drop policy if exists gm_insert on public.group_members;
create policy gm_insert on public.group_members for insert to authenticated with check (is_group_admin(group_id) or user_id = auth.uid());
drop policy if exists gm_update on public.group_members;
create policy gm_update on public.group_members for update to authenticated using (user_id = auth.uid() or is_group_admin(group_id));
drop policy if exists gm_delete on public.group_members;
create policy gm_delete on public.group_members for delete to authenticated using (user_id = auth.uid() or is_group_admin(group_id));

drop policy if exists gjr_select on public.group_join_requests;
create policy gjr_select on public.group_join_requests for select to authenticated using (user_id = auth.uid() or is_group_admin(group_id));
drop policy if exists gjr_insert on public.group_join_requests;
create policy gjr_insert on public.group_join_requests for insert to authenticated with check (user_id = auth.uid());

-- ---------- posts & friends ----------
drop policy if exists posts_select on public.posts;
create policy posts_select on public.posts for select to authenticated using (can_view_post(posts));
drop policy if exists posts_insert on public.posts;
create policy posts_insert on public.posts for insert to authenticated with check (author_id = auth.uid());
drop policy if exists posts_update on public.posts;
create policy posts_update on public.posts for update to authenticated using (author_id = auth.uid());
drop policy if exists posts_delete on public.posts;
create policy posts_delete on public.posts for delete to authenticated using (author_id = auth.uid());

-- child tables of a post: visible if the post is visible
do $$
declare t text;
begin
  foreach t in array array['post_allowed_viewers','post_mentions'] loop
    execute format('drop policy if exists %1$s_sel on public.%1$s', t);
    execute format('create policy %1$s_sel on public.%1$s for select to authenticated using (exists (select 1 from posts p where p.id = post_id and (p.author_id = auth.uid() or can_view_post(p))))', t);
    execute format('drop policy if exists %1$s_wr on public.%1$s', t);
    execute format('create policy %1$s_wr on public.%1$s for all to authenticated using (exists (select 1 from posts p where p.id = post_id and p.author_id = auth.uid())) with check (exists (select 1 from posts p where p.id = post_id and p.author_id = auth.uid()))', t);
  end loop;
end $$;

drop policy if exists likes_sel on public.post_likes;
create policy likes_sel on public.post_likes for select to authenticated using (true);
drop policy if exists likes_wr on public.post_likes;
create policy likes_wr on public.post_likes for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists saved_all on public.saved_posts;
create policy saved_all on public.saved_posts for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists pshares_sel on public.post_shares;
create policy pshares_sel on public.post_shares for select to authenticated using (true);
drop policy if exists pshares_wr on public.post_shares;
create policy pshares_wr on public.post_shares for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists comments_sel on public.comments;
create policy comments_sel on public.comments for select to authenticated using (exists (select 1 from posts p where p.id = post_id and can_view_post(p)));
drop policy if exists comments_ins on public.comments;
create policy comments_ins on public.comments for insert to authenticated with check (author_id = auth.uid());
drop policy if exists comments_upd on public.comments;
create policy comments_upd on public.comments for update to authenticated using (author_id = auth.uid());
drop policy if exists comments_del on public.comments;
create policy comments_del on public.comments for delete to authenticated using (author_id = auth.uid() or exists (select 1 from posts p where p.id = post_id and p.author_id = auth.uid()));
drop policy if exists creact_sel on public.comment_reactions;
create policy creact_sel on public.comment_reactions for select to authenticated using (true);
drop policy if exists creact_wr on public.comment_reactions;
create policy creact_wr on public.comment_reactions for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists cmen_sel on public.comment_mentions;
create policy cmen_sel on public.comment_mentions for select to authenticated using (true);
drop policy if exists cmen_ins on public.comment_mentions;
create policy cmen_ins on public.comment_mentions for insert to authenticated with check (exists (select 1 from comments c where c.id = comment_id and c.author_id = auth.uid()));

-- ---------- stories ----------
drop policy if exists stories_sel on public.stories;
create policy stories_sel on public.stories for select to authenticated using (can_view_story(stories) and created_at > now() - interval '24 hours' or author_id = auth.uid());
drop policy if exists stories_wr on public.stories;
create policy stories_wr on public.stories for all to authenticated using (author_id = auth.uid()) with check (author_id = auth.uid());
do $$
declare t text;
begin
  foreach t in array array['story_videos','story_allowed_viewers','story_mentions'] loop
    execute format('drop policy if exists %1$s_sel on public.%1$s', t);
    execute format('create policy %1$s_sel on public.%1$s for select to authenticated using (exists (select 1 from stories s where s.id = story_id and (s.author_id = auth.uid() or can_view_story(s))))', t);
    execute format('drop policy if exists %1$s_wr on public.%1$s', t);
    execute format('create policy %1$s_wr on public.%1$s for all to authenticated using (exists (select 1 from stories s where s.id = story_id and s.author_id = auth.uid())) with check (exists (select 1 from stories s where s.id = story_id and s.author_id = auth.uid()))', t);
  end loop;
end $$;
drop policy if exists sviews_sel on public.story_views;
create policy sviews_sel on public.story_views for select to authenticated using (viewer_id = auth.uid() or exists (select 1 from stories s where s.id = story_id and s.author_id = auth.uid()));
drop policy if exists sviews_ins on public.story_views;
create policy sviews_ins on public.story_views for insert to authenticated with check (viewer_id = auth.uid());
drop policy if exists sreact_sel on public.story_reactions;
create policy sreact_sel on public.story_reactions for select to authenticated using (user_id = auth.uid() or exists (select 1 from stories s where s.id = story_id and s.author_id = auth.uid()));
drop policy if exists sreact_wr on public.story_reactions;
create policy sreact_wr on public.story_reactions for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------- 1:1 chat ----------
drop policy if exists msg_sel on public.messages;
create policy msg_sel on public.messages for select to authenticated using (sender_id = auth.uid() or receiver_id = auth.uid());
drop policy if exists msg_ins on public.messages;
create policy msg_ins on public.messages for insert to authenticated with check (sender_id = auth.uid() and not is_blocked_between(sender_id, receiver_id));
drop policy if exists msg_upd on public.messages;
create policy msg_upd on public.messages for update to authenticated using (sender_id = auth.uid() or receiver_id = auth.uid());
drop policy if exists msg_del on public.messages;
create policy msg_del on public.messages for delete to authenticated using (sender_id = auth.uid());

drop policy if exists mreq_sel on public.message_requests;
create policy mreq_sel on public.message_requests for select to authenticated using (sender_id = auth.uid() or receiver_id = auth.uid());
drop policy if exists mreq_ins on public.message_requests;
create policy mreq_ins on public.message_requests for insert to authenticated with check (sender_id = auth.uid());
drop policy if exists mreq_upd on public.message_requests;
create policy mreq_upd on public.message_requests for update to authenticated using (receiver_id = auth.uid() or sender_id = auth.uid());
drop policy if exists mreq_del on public.message_requests;
create policy mreq_del on public.message_requests for delete to authenticated using (receiver_id = auth.uid() or sender_id = auth.uid());

drop policy if exists mreact_sel on public.message_reactions;
create policy mreact_sel on public.message_reactions for select to authenticated using (exists (select 1 from messages m where m.id = message_id and (m.sender_id = auth.uid() or m.receiver_id = auth.uid())));
drop policy if exists mreact_wr on public.message_reactions;
create policy mreact_wr on public.message_reactions for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists typing_sel on public.typing_status;
create policy typing_sel on public.typing_status for select to authenticated using (true);
drop policy if exists typing_wr on public.typing_status;
create policy typing_wr on public.typing_status for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists cmute_all on public.chat_mutes;
create policy cmute_all on public.chat_mutes for all to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());

-- ---------- group chat ----------
drop policy if exists gmsg_sel on public.group_messages;
create policy gmsg_sel on public.group_messages for select to authenticated using (is_group_member(group_id));
drop policy if exists gmsg_ins on public.group_messages;
create policy gmsg_ins on public.group_messages for insert to authenticated with check (sender_id = auth.uid() and is_group_member(group_id));
drop policy if exists gmsg_upd on public.group_messages;
create policy gmsg_upd on public.group_messages for update to authenticated using (sender_id = auth.uid() or is_group_admin(group_id) or is_group_member(group_id));
drop policy if exists gmsg_del on public.group_messages;
create policy gmsg_del on public.group_messages for delete to authenticated using (sender_id = auth.uid() or is_group_admin(group_id));
drop policy if exists gmr_sel on public.group_message_reactions;
create policy gmr_sel on public.group_message_reactions for select to authenticated using (is_group_member(group_id));
drop policy if exists gmr_wr on public.group_message_reactions;
create policy gmr_wr on public.group_message_reactions for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid() and is_group_member(group_id));
drop policy if exists gmm_sel on public.group_message_mentions;
create policy gmm_sel on public.group_message_mentions for select to authenticated using (is_group_member(group_id));
drop policy if exists gmm_ins on public.group_message_mentions;
create policy gmm_ins on public.group_message_mentions for insert to authenticated with check (is_group_member(group_id));
drop policy if exists gmreads_sel on public.group_message_reads;
create policy gmreads_sel on public.group_message_reads for select to authenticated using (exists (select 1 from group_messages m where m.id = message_id and is_group_member(m.group_id)));
drop policy if exists gmreads_wr on public.group_message_reads;
create policy gmreads_wr on public.group_message_reads for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists gtyp_sel on public.group_typing_status;
create policy gtyp_sel on public.group_typing_status for select to authenticated using (is_group_member(group_id));
drop policy if exists gtyp_wr on public.group_typing_status;
create policy gtyp_wr on public.group_typing_status for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------- calls / notifications ----------
drop policy if exists calls_sel on public.calls;
create policy calls_sel on public.calls for select to authenticated using (caller_id = auth.uid() or receiver_id = auth.uid());
drop policy if exists calls_ins on public.calls;
create policy calls_ins on public.calls for insert to authenticated with check (caller_id = auth.uid());
drop policy if exists calls_upd on public.calls;
create policy calls_upd on public.calls for update to authenticated using (caller_id = auth.uid() or receiver_id = auth.uid());
drop policy if exists calls_del on public.calls;
create policy calls_del on public.calls for delete to authenticated using (caller_id = auth.uid() or receiver_id = auth.uid());

drop policy if exists gcalls_sel on public.group_calls;
create policy gcalls_sel on public.group_calls for select to authenticated using (is_group_member(group_id));
drop policy if exists gcalls_ins on public.group_calls;
create policy gcalls_ins on public.group_calls for insert to authenticated with check (is_group_member(group_id));
drop policy if exists gcalls_upd on public.group_calls;
create policy gcalls_upd on public.group_calls for update to authenticated using (is_group_member(group_id));

drop policy if exists notif_sel on public.notifications;
create policy notif_sel on public.notifications for select to authenticated using (receiver_id = auth.uid());
drop policy if exists notif_ins on public.notifications;
create policy notif_ins on public.notifications for insert to authenticated with check (sender_id = auth.uid());
drop policy if exists notif_upd on public.notifications;
create policy notif_upd on public.notifications for update to authenticated using (receiver_id = auth.uid());
drop policy if exists notif_del on public.notifications;
create policy notif_del on public.notifications for delete to authenticated using (receiver_id = auth.uid());

-- ---------- stickers ----------
drop policy if exists sp_sel on public.sticker_packs;
create policy sp_sel on public.sticker_packs for select to authenticated using (
  privacy_level = 'public' or owner_id = auth.uid()
  or (privacy_level = 'friends' and are_users_friends(owner_id, auth.uid()))
  or exists (select 1 from sticker_pack_shares s where s.pack_id = id and s.shared_with_user_id = auth.uid()));
drop policy if exists sp_wr on public.sticker_packs;
create policy sp_wr on public.sticker_packs for all to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
drop policy if exists st_sel on public.stickers;
create policy st_sel on public.stickers for select to authenticated using (exists (select 1 from sticker_packs p where p.id = pack_id));
drop policy if exists st_wr on public.stickers;
create policy st_wr on public.stickers for all to authenticated using (exists (select 1 from sticker_packs p where p.id = pack_id and p.owner_id = auth.uid())) with check (exists (select 1 from sticker_packs p where p.id = pack_id and p.owner_id = auth.uid()));
drop policy if exists sps_sel on public.sticker_pack_shares;
create policy sps_sel on public.sticker_pack_shares for select to authenticated using (shared_with_user_id = auth.uid() or exists (select 1 from sticker_packs p where p.id = pack_id and p.owner_id = auth.uid()));
drop policy if exists sps_wr on public.sticker_pack_shares;
create policy sps_wr on public.sticker_pack_shares for all to authenticated using (exists (select 1 from sticker_packs p where p.id = pack_id and p.owner_id = auth.uid())) with check (exists (select 1 from sticker_packs p where p.id = pack_id and p.owner_id = auth.uid()));

-- ---------- reels (read-only for clients; fill via service role / edge function) ----------
drop policy if exists reelch_sel on public.reel_channels;
create policy reelch_sel on public.reel_channels for select to authenticated using (true);
drop policy if exists reelc_sel on public.reels_cache;
create policy reelc_sel on public.reels_cache for select to authenticated using (true);

-- ---------- AI assistant (owner only) ----------
drop policy if exists ais_all on public.ai_chat_sessions;
create policy ais_all on public.ai_chat_sessions for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists aim_all on public.ai_chat_messages;
create policy aim_all on public.ai_chat_messages for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------- reports / feedback / system / 2FA / telemetry ----------
drop policy if exists rep_ins on public.reports;
create policy rep_ins on public.reports for insert to authenticated with check (reporter_id = auth.uid());
drop policy if exists fb_sel on public.user_feedbacks;
create policy fb_sel on public.user_feedbacks for select to authenticated using (user_id = auth.uid());
drop policy if exists fb_ins on public.user_feedbacks;
create policy fb_ins on public.user_feedbacks for insert to authenticated with check (user_id = auth.uid());
drop policy if exists sys_sel on public.app_system_control;
create policy sys_sel on public.app_system_control for select to anon, authenticated using (true);
-- hide admin-only column from clients
revoke all on public.user_feedbacks from anon, authenticated;
grant select (id, user_id, category, message, rating, image_url, audio_url, audio_duration_seconds, contact_method, status, admin_response, responded_at, created_at) on public.user_feedbacks to authenticated;
grant insert (user_id, category, message, rating, image_url, audio_url, audio_duration_seconds, contact_method) on public.user_feedbacks to authenticated;
-- mfa_recovery_codes, incident_reports: no client policies (accessed only via SECURITY DEFINER RPCs)

-- ---------- Realtime publication ----------
do $$
declare t text;
begin
  foreach t in array array['messages','message_reactions','typing_status','chat_mutes','group_messages','group_message_reactions',
    'group_message_reads','group_typing_status','group_members','group_calls','calls','notifications','user_presence','users',
    'posts','post_likes','comments','story_views','friendships','follows','message_requests','blocked_users','groups'] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;
-- full row payloads for UPDATE/DELETE events the client listens to
alter table public.messages replica identity full;
alter table public.group_messages replica identity full;
alter table public.calls replica identity full;
alter table public.group_calls replica identity full;
alter table public.group_members replica identity full;
alter table public.chat_mutes replica identity full;
