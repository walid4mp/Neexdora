-- ============================================================================
-- Nexora backend — 001: core schema (tables, indexes, triggers)
-- Derived from the Flutter client (lib/core/utilities/supabase_constants.dart
-- and the services/models). Run in Supabase SQL Editor, or `supabase db push`.
-- ============================================================================

-- ---------- users (profile row mirrored from auth.users) ----------
create table if not exists public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  name text,
  email text,
  image_url text,
  image_public_id text,
  background_image_url text,
  background_image_public_id text,
  title text,
  tagline text,
  is_tagline_hidden boolean not null default false,
  last_seen timestamptz,
  is_typing_to uuid,
  theme text,
  fcm_token text,
  is_deleted boolean not null default false,
  deleted_at timestamptz,
  presence_privacy text not null default 'everyone' check (presence_privacy in ('everyone','friends','specific','nobody')),
  presence_visible_to uuid[] not null default '{}',
  social_links jsonb not null default '{}'::jsonb,   -- JSON OBJECT (the app casts it to Map)
  username text,
  bio text,
  notif_push boolean not null default true,
  notif_previews boolean not null default true,
  notif_calls boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists users_name_idx on public.users (lower(name));

create table if not exists public.user_presence (
  user_id uuid primary key references public.users(id) on delete cascade,
  is_online boolean not null default false,
  last_seen timestamptz,
  updated_at timestamptz not null default now()
);

-- ---------- social graph ----------
create table if not exists public.friendships (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.users(id) on delete cascade,
  addressee_id uuid not null references public.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','rejected')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  unique (requester_id, addressee_id),
  check (requester_id <> addressee_id)
);
create index if not exists friendships_addressee_idx on public.friendships (addressee_id, status);

create table if not exists public.follows (
  id uuid primary key default gen_random_uuid(),
  follower_id uuid not null references public.users(id) on delete cascade,
  following_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (follower_id, following_id)
);
create index if not exists follows_following_idx on public.follows (following_id);

create table if not exists public.blocked_users (
  id uuid primary key default gen_random_uuid(),
  blocker_id uuid not null references public.users(id) on delete cascade,
  blocked_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (blocker_id, blocked_id)
);

-- ---------- groups ----------
create table if not exists public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  avatar_url text,
  avatar_public_id text,
  cover_url text,
  cover_public_id text,
  who_can_post text not null default 'everyone',
  created_by uuid references public.users(id) on delete set null,
  title text,
  invite_hash text unique,
  invite_expires_at timestamptz,
  invite_join_count int not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.group_members (
  group_id uuid not null references public.groups(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner','admin','member')),
  joined_at timestamptz not null default now(),
  is_muted boolean not null default false,
  membership_status text not null default 'active' check (membership_status in ('active','left','removed','banned')),
  left_at timestamptz,
  is_blocked boolean not null default false,
  blocked_at timestamptz,
  primary key (group_id, user_id)
);
create index if not exists group_members_user_idx on public.group_members (user_id, membership_status);

create table if not exists public.group_join_requests (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','rejected')),
  created_at timestamptz not null default now(),
  reviewed_by uuid references public.users(id),
  reviewed_at timestamptz,
  unique (group_id, user_id)
);

-- ---------- posts / stories ----------
create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.users(id) on delete cascade,
  text text not null default '',
  image_url text, video_url text, gif_url text,
  image_public_id text, video_public_id text, file_public_id text,
  media_width int, media_height int,
  background_theme text,
  shared_post_id uuid references public.posts(id) on delete set null,
  shared_reel_id text,
  is_pinned boolean not null default false,
  privacy_type text not null default 'public' check (privacy_type in ('public','friends','private')),
  group_id uuid references public.groups(id) on delete cascade,
  likes int not null default 0,
  comments int not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists posts_author_idx on public.posts (author_id, created_at desc);
create index if not exists posts_created_idx on public.posts (created_at desc, id);
create index if not exists posts_group_idx on public.posts (group_id, created_at desc);

create table if not exists public.post_allowed_viewers (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  primary key (post_id, user_id)
);
create table if not exists public.post_likes (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  reaction text,
  created_at timestamptz not null default now(),
  unique (post_id, user_id)
);
create table if not exists public.saved_posts (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (post_id, user_id)
);
create table if not exists public.post_shares (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (post_id, user_id)
);
alter table public.posts add column if not exists link_share_count int not null default 0;
create table if not exists public.post_mentions (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  mentioned_user_id uuid not null references public.users(id) on delete cascade,
  start_index int, end_index int,
  created_at timestamptz not null default now()
);

create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  author_id uuid not null references public.users(id) on delete cascade,
  parent_comment_id uuid references public.comments(id) on delete cascade,
  text text not null default '',
  comment_type text not null default 'text',
  image_url text, video_url text, voice_url text, file_url text, file_name text,
  file_size_bytes bigint, duration_seconds int,
  image_public_id text, video_public_id text, voice_public_id text, file_public_id text,
  is_edited boolean not null default false,
  updated_at timestamptz,
  reply_count int not null default 0,
  reaction_count int not null default 0,
  relevance_score double precision not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists comments_post_idx on public.comments (post_id, created_at);
create index if not exists comments_parent_idx on public.comments (parent_comment_id);
create table if not exists public.comment_reactions (
  comment_id uuid not null references public.comments(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  emoji text not null,
  created_at timestamptz not null default now(),
  primary key (comment_id, user_id)
);
create table if not exists public.comment_mentions (
  id uuid primary key default gen_random_uuid(),
  comment_id uuid not null references public.comments(id) on delete cascade,
  mentioned_user_id uuid not null references public.users(id) on delete cascade,
  start_index int, end_index int,
  created_at timestamptz not null default now()
);

create table if not exists public.stories (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.users(id) on delete cascade,
  image_url text, video_url text, content_text text, background_color text, caption text,
  image_public_id text, video_public_id text, video_duration_seconds int,
  privacy_type text not null default 'public' check (privacy_type in ('public','friends','private')),
  created_at timestamptz not null default now()
);
create index if not exists stories_author_idx on public.stories (author_id, created_at desc);
create table if not exists public.story_videos (
  id uuid primary key default gen_random_uuid(),
  story_id uuid not null references public.stories(id) on delete cascade,
  video_url text, created_at timestamptz not null default now()
);
create table if not exists public.story_allowed_viewers (
  story_id uuid not null references public.stories(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  primary key (story_id, user_id)
);
create table if not exists public.story_views (
  id uuid primary key default gen_random_uuid(),
  story_id uuid not null references public.stories(id) on delete cascade,
  viewer_id uuid not null references public.users(id) on delete cascade,
  viewed_at timestamptz not null default now(),
  unique (story_id, viewer_id)
);
create table if not exists public.story_reactions (
  id uuid primary key default gen_random_uuid(),
  story_id uuid not null references public.stories(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  reaction text not null,
  created_at timestamptz not null default now(),
  unique (story_id, user_id)
);
create table if not exists public.story_mentions (
  id uuid primary key default gen_random_uuid(),
  story_id uuid not null references public.stories(id) on delete cascade,
  mentioned_user_id uuid not null references public.users(id) on delete cascade,
  start_index int, end_index int,
  created_at timestamptz not null default now()
);

-- ---------- 1:1 chat ----------
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.users(id) on delete cascade,
  receiver_id uuid not null references public.users(id) on delete cascade,
  conversation_id text,
  message_text text,
  message_type text not null default 'text',
  image_url text, video_url text, voice_url text, file_url text, file_name text,
  file_size_bytes bigint, duration_seconds int, caption text,
  image_public_id text, video_public_id text, voice_public_id text, file_public_id text,
  is_read boolean not null default false,
  read_at timestamptz,
  delivered_at timestamptz,
  is_edited boolean not null default false,
  updated_at timestamptz,
  reaction text,
  reply_to_message_id uuid,
  reply_to_text text, reply_to_message_type text, reply_to_sender_id uuid, reply_to_media_url text,
  reply_to_story_id uuid, reply_to_story_author_id uuid, reply_to_story_type text,
  reply_to_story_media_url text, reply_to_story_text text, reply_to_story_bg_color text,
  reply_to_story_duration_seconds int,
  forwarded_from_user_id uuid, forwarded_from_user_name text, forwarded_from_user_avatar text,
  deleted_for uuid[] not null default '{}',
  client_message_id text,
  created_at timestamptz not null default now()
);
create index if not exists messages_conv_idx on public.messages (conversation_id, created_at desc);
create index if not exists messages_receiver_idx on public.messages (receiver_id, is_read);
create unique index if not exists messages_client_id_uq on public.messages (sender_id, client_message_id) where client_message_id is not null;

create table if not exists public.message_requests (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.users(id) on delete cascade,
  receiver_id uuid not null references public.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','rejected')),
  created_at timestamptz not null default now(),
  unique (sender_id, receiver_id)
);
create table if not exists public.message_reactions (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  reaction text not null,
  conversation_id text,
  created_at timestamptz not null default now(),
  unique (message_id, user_id)
);
create table if not exists public.typing_status (
  chat_id text not null,
  user_id uuid not null references public.users(id) on delete cascade,
  is_typing boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (chat_id, user_id)
);
create table if not exists public.chat_mutes (
  owner_id uuid not null references public.users(id) on delete cascade,
  peer_id uuid not null references public.users(id) on delete cascade,
  is_muted boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (owner_id, peer_id)
);

-- ---------- group chat ----------
create table if not exists public.group_messages (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  sender_id uuid references public.users(id) on delete set null,
  text text not null default '',
  message_type text not null default 'text',
  image_url text, video_url text, voice_url text, file_url text, file_name text,
  file_size_bytes bigint, duration_seconds int, caption text,
  image_public_id text, video_public_id text, voice_public_id text, file_public_id text,
  reply_to_id uuid,
  is_edited boolean not null default false,
  updated_at timestamptz,
  deleted_for uuid[] not null default '{}',
  client_message_id text,
  created_at timestamptz not null default now()
);
create index if not exists group_messages_idx on public.group_messages (group_id, created_at desc);
create unique index if not exists group_messages_client_id_uq on public.group_messages (sender_id, client_message_id) where client_message_id is not null;
create table if not exists public.group_message_reactions (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.group_messages(id) on delete cascade,
  group_id uuid references public.groups(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  reaction text not null,
  unique (message_id, user_id)
);
create table if not exists public.group_message_mentions (
  id uuid primary key default gen_random_uuid(),
  group_message_id uuid not null references public.group_messages(id) on delete cascade,
  group_id uuid references public.groups(id) on delete cascade,
  mentioned_user_id uuid not null references public.users(id) on delete cascade,
  start_index int, end_index int,
  created_at timestamptz not null default now()
);
create table if not exists public.group_message_reads (
  message_id uuid not null references public.group_messages(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  delivered_at timestamptz,
  read_at timestamptz,
  primary key (message_id, user_id)
);
create table if not exists public.group_typing_status (
  group_id uuid not null references public.groups(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  is_typing boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

-- ---------- calls ----------
create table if not exists public.calls (
  call_id text primary key,
  caller_id uuid not null references public.users(id) on delete cascade,
  caller_name text, caller_avatar text,
  receiver_id uuid not null references public.users(id) on delete cascade,
  receiver_name text, receiver_avatar text,
  status text not null default 'dialing' check (status in ('dialing','ringing','accepted','rejected','ended','busy')),
  type text not null default 'audio' check (type in ('audio','video')),
  start_time timestamptz,
  created_at timestamptz not null default now()
);
create table if not exists public.group_calls (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  call_id text,
  call_type text not null default 'audio',
  status text not null default 'ringing',
  initiator_id uuid references public.users(id) on delete set null,
  initiator_name text, initiator_avatar text, group_avatar_url text,
  target_user_ids uuid[] not null default '{}',
  participant_count int not null default 0,
  ringing boolean not null default true,
  ended boolean not null default false,
  duration int,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  last_heartbeat_at timestamptz
);
create index if not exists group_calls_group_idx on public.group_calls (group_id, started_at desc);

-- ---------- notifications ----------
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  receiver_id uuid not null references public.users(id) on delete cascade,
  sender_id uuid references public.users(id) on delete set null,
  type text not null default 'general',
  title text, body text,
  reference_id text,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists notifications_receiver_idx on public.notifications (receiver_id, created_at desc);

-- ---------- stickers ----------
create table if not exists public.sticker_packs (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references public.users(id) on delete cascade,
  title text not null, cover_url text not null default '',
  sticker_count int not null default 0, total_size_bytes bigint not null default 0,
  sort_order int not null default 0, has_animated boolean not null default false,
  privacy_level text not null default 'public' check (privacy_level in ('public','private','friends')),
  created_at timestamptz not null default now()
);
create table if not exists public.stickers (
  id uuid primary key default gen_random_uuid(),
  pack_id uuid not null references public.sticker_packs(id) on delete cascade,
  image_url text not null, sort_order int not null default 0, size_bytes bigint,
  is_animated boolean not null default false, format text,
  created_at timestamptz not null default now()
);
create table if not exists public.sticker_pack_shares (
  id uuid primary key default gen_random_uuid(),
  pack_id uuid not null references public.sticker_packs(id) on delete cascade,
  shared_with_user_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (pack_id, shared_with_user_id)
);

-- ---------- reels ----------
create table if not exists public.reel_channels (
  id uuid primary key default gen_random_uuid(),
  youtube_channel_id text unique not null,
  channel_name text, channel_avatar_url text,
  is_active boolean not null default true
);
create table if not exists public.reels_cache (
  id uuid primary key default gen_random_uuid(),
  youtube_video_id text unique not null,
  channel_id uuid references public.reel_channels(id) on delete set null,
  title text, description text, thumbnail_url text,
  original_like_count bigint, original_view_count bigint,
  published_at timestamptz, cached_at timestamptz not null default now()
);

-- ---------- AI assistant ----------
create table if not exists public.ai_chat_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  title text not null default 'New chat',
  title_is_auto boolean not null default true,
  active_provider text, active_model text,
  last_message_preview text, last_message_at timestamptz,
  message_count int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.ai_chat_messages (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.ai_chat_sessions(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  role text not null check (role in ('user','assistant','system')),
  content text not null default '',
  attachment_type text, attachment_url text, file_name text, file_size_bytes bigint, duration_seconds int,
  provider text, model text, degraded boolean not null default false, request_id text,
  status text not null default 'sent',
  reply_to_message_id uuid, reply_to_message_text text, reply_to_sender_role text,
  reply_to_media_type text, reply_to_media_url text,
  created_at timestamptz not null default now()
);
create index if not exists ai_msgs_session_idx on public.ai_chat_messages (session_id, created_at);

-- ---------- reports / feedback / system / 2FA / telemetry ----------
create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.users(id) on delete cascade,
  target_type text not null, target_id text not null, reason_code text not null, note text,
  status text not null default 'open', created_at timestamptz not null default now()
);
create table if not exists public.user_feedbacks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  category text not null default 'other' check (category in ('bug','feature','inquiry','rating','appreciation','other')),
  message text not null default '',
  rating int check (rating between 1 and 5),
  image_url text, audio_url text, audio_duration_seconds int, contact_method text,
  status text not null default 'pending' check (status in ('pending','in_progress','resolved','closed')),
  admin_response text, responded_at timestamptz, responded_by uuid,
  created_at timestamptz not null default now()
);
create table if not exists public.app_system_control (
  id int primary key default 1 check (id = 1),
  maintenance_enabled boolean not null default false,
  maintenance_message text,
  maintenance_starts_at timestamptz,
  maintenance_ends_at timestamptz,
  min_supported_version text,
  recommended_version text,
  banner_message text,
  banner_severity text not null default 'info',
  updated_at timestamptz not null default now()
);
insert into public.app_system_control (id) values (1) on conflict do nothing;
create table if not exists public.mfa_recovery_codes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  code_hash text not null, used_at timestamptz,
  created_at timestamptz not null default now()
);
create table if not exists public.incident_reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid, payload jsonb not null, created_at timestamptz not null default now()
);

-- ---------- triggers ----------
-- 1) create a profile row whenever an auth user signs up
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.users (id, name, email, image_url)
  values (new.id,
          coalesce(new.raw_user_meta_data->>'name', new.raw_user_meta_data->>'full_name', split_part(new.email,'@',1)),
          new.email,
          coalesce(new.raw_user_meta_data->>'avatar_url', new.raw_user_meta_data->>'picture'))
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- 2) denormalised counters
create or replace function public.bump_post_likes() returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then update public.posts set likes = likes + 1 where id = new.post_id;
  else update public.posts set likes = greatest(likes - 1, 0) where id = old.post_id; end if;
  return null;
end $$;
drop trigger if exists trg_post_likes on public.post_likes;
create trigger trg_post_likes after insert or delete on public.post_likes for each row execute function public.bump_post_likes();

create or replace function public.bump_post_comments() returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    update public.posts set comments = comments + 1 where id = new.post_id;
    if new.parent_comment_id is not null then update public.comments set reply_count = reply_count + 1 where id = new.parent_comment_id; end if;
  else
    update public.posts set comments = greatest(comments - 1, 0) where id = old.post_id;
    if old.parent_comment_id is not null then update public.comments set reply_count = greatest(reply_count - 1, 0) where id = old.parent_comment_id; end if;
  end if;
  return null;
end $$;
drop trigger if exists trg_post_comments on public.comments;
create trigger trg_post_comments after insert or delete on public.comments for each row execute function public.bump_post_comments();

create or replace function public.bump_comment_reactions() returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then update public.comments set reaction_count = reaction_count + 1 where id = new.comment_id;
  elsif tg_op = 'DELETE' then update public.comments set reaction_count = greatest(reaction_count - 1, 0) where id = old.comment_id; end if;
  return null;
end $$;
drop trigger if exists trg_comment_reactions on public.comment_reactions;
create trigger trg_comment_reactions after insert or delete on public.comment_reactions for each row execute function public.bump_comment_reactions();

create or replace function public.bump_sticker_pack() returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    update public.sticker_packs set sticker_count = sticker_count + 1, total_size_bytes = total_size_bytes + coalesce(new.size_bytes,0),
      has_animated = has_animated or new.is_animated, cover_url = case when cover_url = '' then new.image_url else cover_url end where id = new.pack_id;
  else
    update public.sticker_packs set sticker_count = greatest(sticker_count - 1, 0), total_size_bytes = greatest(total_size_bytes - coalesce(old.size_bytes,0),0) where id = old.pack_id;
  end if;
  return null;
end $$;
drop trigger if exists trg_sticker_pack on public.stickers;
create trigger trg_sticker_pack after insert or delete on public.stickers for each row execute function public.bump_sticker_pack();

-- never let NULL text reach the app (it casts these columns to non-null String)
create or replace function public.coalesce_text() returns trigger language plpgsql as $$
begin new.text := coalesce(new.text, ''); return new; end $$;
drop trigger if exists trg_text_posts on public.posts;
create trigger trg_text_posts before insert or update on public.posts for each row execute function public.coalesce_text();
drop trigger if exists trg_text_comments on public.comments;
create trigger trg_text_comments before insert or update on public.comments for each row execute function public.coalesce_text();
drop trigger if exists trg_text_gmsgs on public.group_messages;
create trigger trg_text_gmsgs before insert or update on public.group_messages for each row execute function public.coalesce_text();
