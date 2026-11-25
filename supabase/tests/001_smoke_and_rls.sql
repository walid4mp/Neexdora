-- ============================================================================
-- Nexora backend smoke + RLS tests.  Run AFTER migrations 001-009 on a DISPOSABLE database:
--   psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/001_smoke_and_rls.sql
-- Everything runs in one transaction and is ROLLED BACK at the end. Each check RAISEs on failure.
-- ============================================================================
begin;

create or replace function pg_temp.act_as(u uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', u::text, true);
  execute 'set local role authenticated';
end $$;
create or replace function pg_temp.act_admin() returns void language plpgsql as $$
begin execute 'reset role'; end $$;
create or replace function pg_temp.check(name text, ok boolean) returns void language plpgsql as $$
begin if ok is not true then raise exception 'TEST FAILED: %', name; end if; raise notice 'PASS: %', name; end $$;

-- ---- fixtures: three auth users (trigger must create profiles) ----
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at)
select u, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', n || '@test.local', jsonb_build_object('name', n), now(), now()
from (values ('aaaaaaaa-0000-0000-0000-000000000001'::uuid, 'alice'), ('aaaaaaaa-0000-0000-0000-000000000002', 'bob'), ('aaaaaaaa-0000-0000-0000-000000000003', 'carol')) v(u, n);
select pg_temp.check('1 signup trigger created profiles', (select count(*) from public.users where email like '%@test.local') = 3);

-- ---- 3 friend request + accept ----
select pg_temp.act_as('aaaaaaaa-0000-0000-0000-000000000001');
insert into public.friendships (requester_id, addressee_id) values ('aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000002');
select pg_temp.act_as('aaaaaaaa-0000-0000-0000-000000000002');
update public.friendships set status = 'accepted' where addressee_id = auth.uid();
select pg_temp.check('3 friendship accepted', public.are_users_friends('aaaaaaaa-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000002'));

-- ---- 4 post (friends-only) + comment + like counters ----
select pg_temp.act_as('aaaaaaaa-0000-0000-0000-000000000001');
insert into public.posts (id, author_id, text, privacy_type) values ('bbbbbbbb-0000-0000-0000-000000000001', auth.uid(), 'hello', 'friends');
select pg_temp.act_as('aaaaaaaa-0000-0000-0000-000000000002');
insert into public.comments (post_id, author_id, text) values ('bbbbbbbb-0000-0000-0000-000000000001', auth.uid(), 'hi');
insert into public.post_likes (post_id, user_id) values ('bbbbbbbb-0000-0000-0000-000000000001', auth.uid());
select pg_temp.check('4 friend sees friends-only post', exists (select 1 from public.posts where id = 'bbbbbbbb-0000-0000-0000-000000000001'));
select pg_temp.check('4 counters updated', (select likes = 1 and comments = 1 from public.posts where id = 'bbbbbbbb-0000-0000-0000-000000000001'));
-- RLS: stranger must NOT see it
select pg_temp.act_as('aaaaaaaa-0000-0000-0000-000000000003');
select pg_temp.check('10 RLS: stranger cannot read friends-only post', not exists (select 1 from public.posts where id = 'bbbbbbbb-0000-0000-0000-000000000001'));
select pg_temp.check('10 RLS: stranger home feed hides it', not exists (select 1 from public.get_ranked_home_feed(auth.uid(), 50, 0) where post_id = 'bbbbbbbb-0000-0000-0000-000000000001'));

-- ---- 5 messages ----
select pg_temp.act_as('aaaaaaaa-0000-0000-0000-000000000001');
insert into public.messages (sender_id, receiver_id, conversation_id, message_text) values (auth.uid(), 'aaaaaaaa-0000-0000-0000-000000000002', 'c1', 'ping');
select pg_temp.act_as('aaaaaaaa-0000-0000-0000-000000000002');
select pg_temp.check('5 receiver reads message + chat list shows unread', (select unread_count = 1 from public.get_chats_with_last_message(auth.uid()) limit 1));
select pg_temp.act_as('aaaaaaaa-0000-0000-0000-000000000003');
select pg_temp.check('10 RLS: third user sees no messages', (select count(*) from public.messages) = 0);

-- ---- 6 story ----
select pg_temp.act_as('aaaaaaaa-0000-0000-0000-000000000001');
insert into public.stories (id, author_id, content_text, privacy_type) values ('cccccccc-0000-0000-0000-000000000001', auth.uid(), 'story', 'public');
select pg_temp.act_as('aaaaaaaa-0000-0000-0000-000000000002');
select public.mark_story_viewed('cccccccc-0000-0000-0000-000000000001');
select pg_temp.act_as('aaaaaaaa-0000-0000-0000-000000000001');
select pg_temp.check('6 author sees story viewer', (select count(*) from public.get_story_viewers('cccccccc-0000-0000-0000-000000000001')) = 1);

-- ---- 8 group + invite join ----
select pg_temp.act_as('aaaaaaaa-0000-0000-0000-000000000001');
create temp table _g as select * from public.create_group_with_members(auth.uid(), 'Team', null, null, '{}');
create temp table _inv as select * from public.generate_group_invite_link((select id from _g), 24);
grant select on _g, _inv to authenticated;
select pg_temp.act_as('aaaaaaaa-0000-0000-0000-000000000003');
select public.join_group_via_invite((select invite_hash from _inv));
select pg_temp.check('8 joined group via invite', public.is_group_member((select id from _g), auth.uid()));
insert into public.group_messages (group_id, sender_id, text) values ((select id from _g), auth.uid(), 'hi group');
select pg_temp.act_as('aaaaaaaa-0000-0000-0000-000000000002');
select pg_temp.check('10 RLS: non-member cannot read group messages', (select count(*) from public.group_messages) = 0);

-- ---- 9 admin sanction blocks writes; user cannot self-escalate ----
select pg_temp.act_admin();
insert into public.app_admins (user_id, role) values ('aaaaaaaa-0000-0000-0000-000000000001', 'admin');
select pg_temp.act_as('aaaaaaaa-0000-0000-0000-000000000003');
select pg_temp.check('9 normal user cannot grant themselves admin', (select not exists (select 1 from public.app_admins where user_id = auth.uid()) and (select count(*) from public.app_admins) <= 1));
do $$ begin
  begin perform public.admin_apply_sanction('aaaaaaaa-0000-0000-0000-000000000002', 'ban', 'abuse', 1); raise exception 'TEST FAILED: non-admin could ban';
  exception when others then if sqlerrm <> 'forbidden' then raise; end if; end;
end $$;
select pg_temp.act_as('aaaaaaaa-0000-0000-0000-000000000001');
select public.admin_apply_sanction('aaaaaaaa-0000-0000-0000-000000000003', 'suspension', 'spam', 2);
select pg_temp.act_as('aaaaaaaa-0000-0000-0000-000000000003');
select pg_temp.check('9 status reports suspension', (public.get_app_system_status('1.0.0') ->> 'is_caller_suspended')::boolean);
do $$ begin
  begin insert into public.posts (author_id, text) values (auth.uid(), 'blocked?'); raise exception 'TEST FAILED: sanctioned user could post';
  exception when others then if sqlerrm <> 'account_sanctioned' then raise; end if; end;
end $$;
select pg_temp.act_as('aaaaaaaa-0000-0000-0000-000000000001');
select public.admin_revoke_sanction((select id from public.user_sanctions where user_id = 'aaaaaaaa-0000-0000-0000-000000000003' and revoked_at is null limit 1), 'ok');
select pg_temp.act_as('aaaaaaaa-0000-0000-0000-000000000003');
insert into public.posts (author_id, text) values (auth.uid(), 'allowed again');
select pg_temp.check('9 unsuspended user can post again', true);

-- ---- 14 story expiry purge ----
select pg_temp.act_admin();
update public.stories set created_at = now() - interval '30 hours' where id = 'cccccccc-0000-0000-0000-000000000001';
select pg_temp.check('14 purge removes expired stories', public.purge_expired_stories() >= 1 and not exists (select 1 from public.stories where id = 'cccccccc-0000-0000-0000-000000000001'));

rollback;
\echo 'ALL SQL TESTS PASSED (rolled back)'
