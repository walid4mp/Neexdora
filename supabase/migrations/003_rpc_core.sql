-- ============================================================================
-- Nexora backend — 003: core RPC functions (account, AI chat, groups, social,
-- reactions, reports, feedback, 2FA recovery codes, system status, telemetry)
-- All are SECURITY DEFINER with a fixed search_path and use auth.uid().
-- ============================================================================
create extension if not exists pgcrypto with schema extensions;

-- ---------- account ----------
create or replace function public.verify_current_user_password(p_password text)
returns boolean language plpgsql security definer set search_path = public, auth, extensions as $$
begin
  return exists (select 1 from auth.users
                 where id = auth.uid() and encrypted_password = crypt(p_password, encrypted_password));
end $$;

create or replace function public.soft_delete_user_account()
returns void language plpgsql security definer set search_path = public, auth as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  update public.users set is_deleted = true, deleted_at = now(), name = 'Deleted user',
         image_url = null, image_public_id = null, background_image_url = null, background_image_public_id = null,
         tagline = null, title = null, fcm_token = null, social_links = '[]'::jsonb, email = null
   where id = uid;
  delete from auth.sessions where user_id = uid;
  delete from auth.refresh_tokens where user_id = uid::text;
  update auth.users set email = 'deleted+' || uid || '@invalid.local', encrypted_password = null,
         banned_until = 'infinity' where id = uid;
end $$;

create or replace function public.cancel_email_change()
returns void language plpgsql security definer set search_path = public, auth as $$
begin
  update auth.users set email_change = '', email_change_token_new = '', email_change_token_current = '',
         email_change_sent_at = null, email_change_confirm_status = 0
   where id = auth.uid();
end $$;

create or replace function public.update_my_notification_prefs(p_push boolean, p_previews boolean, p_calls boolean)
returns void language sql security definer set search_path = public as $$
  update public.users set notif_push = p_push, notif_previews = p_previews, notif_calls = p_calls where id = auth.uid();
$$;

-- ---------- 2FA recovery codes (bcrypt hashes only) ----------
create or replace function public.generate_mfa_recovery_codes()
returns text[] language plpgsql security definer set search_path = public, extensions as $$
declare codes text[] := '{}'; c text; i int;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  delete from public.mfa_recovery_codes where user_id = auth.uid();
  for i in 1..10 loop
    c := upper(substr(encode(gen_random_bytes(5), 'hex'), 1, 5) || '-' || substr(encode(gen_random_bytes(5), 'hex'), 1, 5));
    codes := codes || c;
    insert into public.mfa_recovery_codes (user_id, code_hash) values (auth.uid(), crypt(c, gen_salt('bf')));
  end loop;
  return codes;
end $$;

create or replace function public.mfa_recovery_codes_remaining()
returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from public.mfa_recovery_codes where user_id = auth.uid() and used_at is null;
$$;

create or replace function public.clear_mfa_recovery_codes()
returns void language sql security definer set search_path = public as $$
  delete from public.mfa_recovery_codes where user_id = auth.uid();
$$;

-- Marks a code used (the client then removes the MFA factor / signs the user in).
create or replace function public.redeem_mfa_recovery_code(p_code text)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
declare r record;
begin
  for r in select id, code_hash from public.mfa_recovery_codes where user_id = auth.uid() and used_at is null loop
    if r.code_hash = crypt(upper(trim(p_code)), r.code_hash) then
      update public.mfa_recovery_codes set used_at = now() where id = r.id;
      return true;
    end if;
  end loop;
  return false;
end $$;

-- ---------- system status / telemetry / feedback / reports ----------
create or replace function public.compare_versions(a text, b text) returns int
language plpgsql immutable as $$
declare pa int[]; pb int[]; i int; x int; y int;
begin
  pa := string_to_array(regexp_replace(coalesce(a,'0'), '[^0-9.]', '', 'g'), '.')::int[];
  pb := string_to_array(regexp_replace(coalesce(b,'0'), '[^0-9.]', '', 'g'), '.')::int[];
  for i in 1..greatest(coalesce(array_length(pa,1),0), coalesce(array_length(pb,1),0)) loop
    x := coalesce(pa[i],0); y := coalesce(pb[i],0);
    if x < y then return -1; elsif x > y then return 1; end if;
  end loop;
  return 0;
end $$;

create or replace function public.get_app_system_status(p_app_version text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare s public.app_system_control; active boolean;
begin
  select * into s from public.app_system_control where id = 1;
  active := s.maintenance_enabled
            and (s.maintenance_starts_at is null or s.maintenance_starts_at <= now())
            and (s.maintenance_ends_at   is null or s.maintenance_ends_at   >  now());
  return jsonb_build_object(
    'ok', true,
    'maintenance_enabled', s.maintenance_enabled,
    'maintenance_active', active,
    'maintenance_bypassed', false,
    'maintenance_message', s.maintenance_message,
    'maintenance_starts_at', s.maintenance_starts_at,
    'maintenance_ends_at', s.maintenance_ends_at,
    'min_supported_version', s.min_supported_version,
    'recommended_version', s.recommended_version,
    'update_required', p_app_version is not null and s.min_supported_version is not null and compare_versions(p_app_version, s.min_supported_version) < 0,
    'update_recommended', p_app_version is not null and s.recommended_version is not null and compare_versions(p_app_version, s.recommended_version) < 0,
    'banner_message', s.banner_message,
    'banner_severity', s.banner_severity,
    'is_caller_suspended', false,
    'suspension_reason', null,
    'suspension_expires_at', null,
    'server_time', now());
end $$;
grant execute on function public.get_app_system_status(text) to anon, authenticated;

create or replace function public.get_my_feedback_quota()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'used', count(*),
    'limit', 3,
    'resets_at', case when count(*) >= 3 then min(created_at) + interval '24 hours' else null end)
  from public.user_feedbacks where user_id = auth.uid() and created_at > now() - interval '24 hours';
$$;

create or replace function public.enforce_feedback_quota() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from public.user_feedbacks where user_id = new.user_id and created_at > now() - interval '24 hours') >= 3 then
    raise exception 'feedback_quota_exceeded' using errcode = 'P0001';
  end if;
  return new;
end $$;
drop trigger if exists trg_feedback_quota on public.user_feedbacks;
create trigger trg_feedback_quota before insert on public.user_feedbacks for each row execute function public.enforce_feedback_quota();

create or replace function public.submit_report(p_target_type text, p_target_id text, p_reason_code text, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  insert into public.reports (reporter_id, target_type, target_id, reason_code, note)
  values (auth.uid(), p_target_type, p_target_id, p_reason_code, nullif(trim(p_note), ''));
end $$;

create or replace function public.incident_report_batch(p_reports jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare r jsonb; n int := 0;
begin
  for r in select * from jsonb_array_elements(coalesce(p_reports, '[]'::jsonb)) loop
    insert into public.incident_reports (user_id, payload) values (auth.uid(), r); n := n + 1;
  end loop;
  return n;
end $$;
grant execute on function public.incident_report_batch(jsonb) to anon, authenticated;

-- ---------- chat helpers ----------
create or replace function public.is_chat_muted(p_owner uuid, p_peer uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select is_muted from public.chat_mutes where owner_id = p_owner and peer_id = p_peer), false);
$$;

create or replace function public.are_users_connected(user_a uuid, user_b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.are_users_friends(user_a, user_b)
      or exists (select 1 from public.follows f where (f.follower_id = user_a and f.following_id = user_b)
                                                   or (f.follower_id = user_b and f.following_id = user_a));
$$;

create or replace function public.toggle_message_reaction(p_message_id uuid, p_conversation_id text, p_emoji text)
returns void language plpgsql security definer set search_path = public as $$
declare cur text;
begin
  if not exists (select 1 from public.messages m where m.id = p_message_id and auth.uid() in (m.sender_id, m.receiver_id)) then
    raise exception 'forbidden'; end if;
  select reaction into cur from public.message_reactions where message_id = p_message_id and user_id = auth.uid();
  if cur is null then
    insert into public.message_reactions (message_id, user_id, reaction, conversation_id) values (p_message_id, auth.uid(), p_emoji, p_conversation_id);
  elsif cur = p_emoji then
    delete from public.message_reactions where message_id = p_message_id and user_id = auth.uid();
  else
    update public.message_reactions set reaction = p_emoji where message_id = p_message_id and user_id = auth.uid();
  end if;
end $$;

-- ---------- AI assistant ----------
create or replace function public.create_ai_chat_session(p_first_message text default null)
returns setof public.ai_chat_sessions language plpgsql security definer set search_path = public as $$
declare t text := left(nullif(trim(coalesce(p_first_message,'')), ''), 40);
begin
  return query insert into public.ai_chat_sessions (user_id, title, title_is_auto)
    values (auth.uid(), coalesce(t, 'New chat'), true) returning *;
end $$;

create or replace function public.rename_ai_chat_session(p_session_id uuid, p_title text)
returns void language sql security definer set search_path = public as $$
  update public.ai_chat_sessions set title = left(trim(p_title), 80), title_is_auto = false, updated_at = now()
   where id = p_session_id and user_id = auth.uid();
$$;

create or replace function public.delete_ai_chat_session(p_session_id uuid)
returns void language sql security definer set search_path = public as $$
  delete from public.ai_chat_sessions where id = p_session_id and user_id = auth.uid();
$$;

create or replace function public.append_ai_chat_message(
  p_session_id uuid, p_role text, p_content text,
  p_attachment_type text default null, p_attachment_url text default null,
  p_provider text default null, p_model text default null, p_degraded boolean default false,
  p_request_id text default null, p_file_name text default null, p_file_size_bytes bigint default null,
  p_duration_seconds int default null, p_reply_to_message_id uuid default null,
  p_reply_to_message_text text default null, p_reply_to_sender_role text default null,
  p_reply_to_media_type text default null, p_reply_to_media_url text default null)
returns setof public.ai_chat_messages language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.ai_chat_sessions where id = p_session_id and user_id = auth.uid()) then
    raise exception 'session_not_found'; end if;
  -- idempotent on request_id (client retries)
  if p_request_id is not null and exists (select 1 from public.ai_chat_messages where session_id = p_session_id and request_id = p_request_id and role = p_role) then
    return query select * from public.ai_chat_messages where session_id = p_session_id and request_id = p_request_id and role = p_role limit 1;
    return;
  end if;
  update public.ai_chat_sessions set message_count = message_count + 1, last_message_at = now(),
         last_message_preview = left(p_content, 120), updated_at = now(),
         active_provider = coalesce(p_provider, active_provider), active_model = coalesce(p_model, active_model)
   where id = p_session_id;
  return query insert into public.ai_chat_messages (session_id, user_id, role, content, attachment_type, attachment_url,
      provider, model, degraded, request_id, file_name, file_size_bytes, duration_seconds,
      reply_to_message_id, reply_to_message_text, reply_to_sender_role, reply_to_media_type, reply_to_media_url)
    values (p_session_id, auth.uid(), p_role, coalesce(p_content,''), p_attachment_type, p_attachment_url,
      p_provider, p_model, coalesce(p_degraded,false), p_request_id, p_file_name, p_file_size_bytes, p_duration_seconds,
      p_reply_to_message_id, p_reply_to_message_text, p_reply_to_sender_role, p_reply_to_media_type, p_reply_to_media_url)
    returning *;
end $$;

-- ---------- groups ----------
create or replace function public.create_group_with_members(
  p_creator_id uuid, p_name text, p_avatar_url text default null, p_avatar_public_id text default null, p_member_ids uuid[] default '{}')
returns setof public.groups language plpgsql security definer set search_path = public as $$
declare g public.groups; m uuid;
begin
  if p_creator_id is distinct from auth.uid() then raise exception 'forbidden'; end if;
  insert into public.groups (name, avatar_url, avatar_public_id, created_by) values (trim(p_name), p_avatar_url, p_avatar_public_id, auth.uid()) returning * into g;
  insert into public.group_members (group_id, user_id, role) values (g.id, auth.uid(), 'owner');
  foreach m in array coalesce(p_member_ids, '{}') loop
    if m <> auth.uid() and not public.is_blocked_between(auth.uid(), m) then
      insert into public.group_members (group_id, user_id, role) values (g.id, m, 'member') on conflict do nothing;
    end if;
  end loop;
  return next g;
end $$;

create or replace function public.delete_group_permanently(p_group_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.groups where id = p_group_id and created_by = auth.uid())
     and not exists (select 1 from public.group_members where group_id = p_group_id and user_id = auth.uid() and role = 'owner') then
    raise exception 'forbidden'; end if;
  delete from public.groups where id = p_group_id;
end $$;

create or replace function public.promote_group_member_to_admin(p_group_id uuid, p_target_user_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_group_admin(p_group_id, auth.uid()) then raise exception 'forbidden'; end if;
  update public.group_members set role = 'admin' where group_id = p_group_id and user_id = p_target_user_id and role = 'member' and membership_status = 'active';
end $$;

create or replace function public.demote_group_admin(p_group_id uuid, p_target_user_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.group_members where group_id = p_group_id and user_id = auth.uid() and role = 'owner') then raise exception 'forbidden'; end if;
  update public.group_members set role = 'member' where group_id = p_group_id and user_id = p_target_user_id and role = 'admin';
end $$;

create or replace function public.generate_group_invite_link(p_group_id uuid, p_expires_in_hours int default null)
returns table (invite_hash text, invite_expires_at timestamptz, invite_join_count int)
language plpgsql security definer set search_path = public, extensions as $$
declare h text := encode(gen_random_bytes(12), 'hex');
begin
  if not public.is_group_admin(p_group_id, auth.uid()) then raise exception 'forbidden'; end if;
  return query update public.groups g
     set invite_hash = h, invite_join_count = 0,
         invite_expires_at = case when p_expires_in_hours is null then null else now() + make_interval(hours => p_expires_in_hours) end
   where g.id = p_group_id
  returning g.invite_hash, g.invite_expires_at, g.invite_join_count;
end $$;

create or replace function public.revoke_group_invite_link(p_group_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_group_admin(p_group_id, auth.uid()) then raise exception 'forbidden'; end if;
  update public.groups set invite_hash = null, invite_expires_at = null where id = p_group_id;
end $$;

create or replace function public.get_group_invite_preview(p_invite_hash text)
returns table (is_valid boolean, group_id uuid, group_name text, group_title text, group_avatar_url text, member_count int, is_already_member boolean)
language plpgsql stable security definer set search_path = public as $$
declare g public.groups;
begin
  select * into g from public.groups where invite_hash = p_invite_hash and (invite_expires_at is null or invite_expires_at > now());
  if g.id is null then return query select false, null::uuid, null::text, null::text, null::text, 0, false; return; end if;
  return query select true, g.id, g.name, g.title, g.avatar_url,
    (select count(*)::int from public.group_members m where m.group_id = g.id and m.membership_status = 'active'),
    public.is_group_member(g.id, auth.uid());
end $$;

create or replace function public.join_group_via_invite(p_invite_hash text)
returns setof public.groups language plpgsql security definer set search_path = public as $$
declare g public.groups;
begin
  select * into g from public.groups where invite_hash = p_invite_hash and (invite_expires_at is null or invite_expires_at > now());
  if g.id is null then raise exception 'invite_invalid_or_expired'; end if;
  if exists (select 1 from public.group_members where group_id = g.id and user_id = auth.uid() and (is_blocked or membership_status = 'banned')) then
    raise exception 'blocked_from_group'; end if;
  insert into public.group_members (group_id, user_id, role, membership_status, left_at)
  values (g.id, auth.uid(), 'member', 'active', null)
  on conflict (group_id, user_id) do update set membership_status = 'active', left_at = null, joined_at = now();
  update public.groups set invite_join_count = invite_join_count + 1 where id = g.id;
  return next g;
end $$;

create or replace function public.request_join_group(p_group_id uuid)
returns text language plpgsql security definer set search_path = public as $$
begin
  if public.is_group_member(p_group_id, auth.uid()) then return 'accepted'; end if;
  if exists (select 1 from public.group_members where group_id = p_group_id and user_id = auth.uid() and (is_blocked or membership_status = 'banned')) then
    raise exception 'blocked_from_group'; end if;
  insert into public.group_join_requests (group_id, user_id, status) values (p_group_id, auth.uid(), 'pending')
  on conflict (group_id, user_id) do update set status = 'pending', created_at = now(), reviewed_by = null, reviewed_at = null;
  return 'pending';
end $$;

create or replace function public.review_join_request(p_request_id uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
declare r public.group_join_requests;
begin
  select * into r from public.group_join_requests where id = p_request_id;
  if r.id is null or not public.is_group_admin(r.group_id, auth.uid()) then raise exception 'forbidden'; end if;
  update public.group_join_requests set status = p_status, reviewed_by = auth.uid(), reviewed_at = now() where id = p_request_id;
  if p_status = 'accepted' then
    insert into public.group_members (group_id, user_id, role) values (r.group_id, r.user_id, 'member')
    on conflict (group_id, user_id) do update set membership_status = 'active', left_at = null;
  end if;
end $$;

create or replace function public.get_group_fcm_tokens(p_group_id uuid, p_exclude_user_id uuid default null, p_respect_mute boolean default true)
returns table (user_id uuid, fcm_token text) language sql stable security definer set search_path = public as $$
  select u.id, u.fcm_token
    from public.group_members m join public.users u on u.id = m.user_id
   where m.group_id = p_group_id and m.membership_status = 'active'
     and (p_exclude_user_id is null or m.user_id <> p_exclude_user_id)
     and (not p_respect_mute or not m.is_muted)
     and u.fcm_token is not null and u.is_deleted = false
     and public.is_group_member(p_group_id, auth.uid());
$$;

create or replace function public.mark_group_messages_read(p_group_id uuid, p_user_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_user_id is distinct from auth.uid() then raise exception 'forbidden'; end if;
  insert into public.group_message_reads (message_id, user_id, delivered_at, read_at)
  select m.id, p_user_id, now(), now() from public.group_messages m
   where m.group_id = p_group_id and m.sender_id is distinct from p_user_id
  on conflict (message_id, user_id) do update set read_at = coalesce(group_message_reads.read_at, now());
end $$;

-- ---------- posts / stories ----------
create or replace function public.set_post_pinned(p_post_id uuid, p_pinned boolean)
returns void language sql security definer set search_path = public as $$
  update public.posts set is_pinned = p_pinned where id = p_post_id and author_id = auth.uid();
$$;

create or replace function public.increment_post_link_share_count(p_post_id uuid)
returns int language sql security definer set search_path = public as $$
  update public.posts set link_share_count = link_share_count + 1 where id = p_post_id returning link_share_count;
$$;

create or replace function public.toggle_post_share(p_post_id uuid)
returns table (is_shared boolean, shares_count int) language plpgsql security definer set search_path = public as $$
declare was boolean;
begin
  was := exists (select 1 from public.post_shares where post_id = p_post_id and user_id = auth.uid());
  if was then delete from public.post_shares where post_id = p_post_id and user_id = auth.uid();
  else insert into public.post_shares (post_id, user_id) values (p_post_id, auth.uid()); end if;
  return query select not was, (select count(*)::int from public.post_shares where post_id = p_post_id);
end $$;

create or replace function public.toggle_story_reaction(p_story_id uuid, p_reaction text)
returns text language plpgsql security definer set search_path = public as $$
declare cur text;
begin
  select reaction into cur from public.story_reactions where story_id = p_story_id and user_id = auth.uid();
  if cur = p_reaction then delete from public.story_reactions where story_id = p_story_id and user_id = auth.uid(); return null; end if;
  insert into public.story_reactions (story_id, user_id, reaction) values (p_story_id, auth.uid(), p_reaction)
  on conflict (story_id, user_id) do update set reaction = excluded.reaction, created_at = now();
  return p_reaction;
end $$;

create or replace function public.mark_story_viewed(p_story_id uuid)
returns void language sql security definer set search_path = public as $$
  insert into public.story_views (story_id, viewer_id)
  select p_story_id, auth.uid() where exists (select 1 from public.stories s where s.id = p_story_id and s.author_id <> auth.uid())
  on conflict (story_id, viewer_id) do nothing;
$$;

create or replace function public.add_comment_with_mentions(
  p_post_id uuid, p_author_id uuid, p_text text, p_parent_comment_id uuid default null, p_comment_type text default 'text',
  p_image_url text default null, p_video_url text default null, p_voice_url text default null, p_file_url text default null,
  p_file_name text default null, p_file_size_bytes bigint default null, p_duration_seconds int default null,
  p_image_public_id text default null, p_video_public_id text default null, p_voice_public_id text default null,
  p_file_public_id text default null, p_mentions jsonb default '[]'::jsonb)
returns setof public.comments language plpgsql security definer set search_path = public as $$
declare c public.comments; mm jsonb;
begin
  if p_author_id is distinct from auth.uid() then raise exception 'forbidden'; end if;
  insert into public.comments (post_id, author_id, parent_comment_id, text, comment_type, image_url, video_url, voice_url, file_url, file_name,
      file_size_bytes, duration_seconds, image_public_id, video_public_id, voice_public_id, file_public_id)
  values (p_post_id, p_author_id, p_parent_comment_id, p_text, coalesce(p_comment_type,'text'), p_image_url, p_video_url, p_voice_url, p_file_url, p_file_name,
      p_file_size_bytes, p_duration_seconds, p_image_public_id, p_video_public_id, p_voice_public_id, p_file_public_id)
  returning * into c;
  for mm in select * from jsonb_array_elements(coalesce(p_mentions, '[]'::jsonb)) loop
    insert into public.comment_mentions (comment_id, mentioned_user_id, start_index, end_index)
    values (c.id, (mm->>'mentioned_user_id')::uuid, (mm->>'start_index')::int, (mm->>'end_index')::int);
  end loop;
  return next c;
end $$;

-- ---------- stickers ----------
create or replace function public.create_user_sticker_pack(p_title text, p_privacy_level text, p_stickers jsonb, p_friend_ids uuid[] default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare pid uuid; s jsonb; i int := 0; f uuid;
begin
  insert into public.sticker_packs (owner_id, title, privacy_level) values (auth.uid(), trim(p_title), p_privacy_level) returning id into pid;
  for s in select * from jsonb_array_elements(coalesce(p_stickers, '[]'::jsonb)) loop
    insert into public.stickers (pack_id, image_url, sort_order, size_bytes, is_animated, format)
    values (pid, s->>'image_url', i, (s->>'size_bytes')::bigint, coalesce((s->>'is_animated')::boolean, false), s->>'format');
    i := i + 1;
  end loop;
  if p_privacy_level = 'private' and p_friend_ids is not null then
    foreach f in array p_friend_ids loop
      insert into public.sticker_pack_shares (pack_id, shared_with_user_id) values (pid, f) on conflict do nothing;
    end loop;
  end if;
  return pid;
end $$;

-- every RPC above is callable by logged-in users only (except the explicit anon grants)
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
