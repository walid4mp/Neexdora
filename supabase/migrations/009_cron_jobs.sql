-- ============================================================================
-- Nexora backend — 009: scheduled jobs (pg_cron) + DB→Edge notification triggers (pg_net)
-- Everything here degrades gracefully: missing extensions only raise NOTICEs.
-- ============================================================================
do $$ begin create extension if not exists pg_cron; exception when others then raise notice 'pg_cron not available: %', sqlerrm; end $$;
do $$ begin create extension if not exists pg_net;  exception when others then raise notice 'pg_net not available: %', sqlerrm;  end $$;

-- ---------- maintenance functions ----------
create or replace function public.purge_expired_stories(p_older_than interval default interval '24 hours')
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  -- queue Cloudinary assets for deletion first
  insert into public.media_cleanup_queue (public_id, resource_type)
  select x.pid, x.rtype from public.stories s
    cross join lateral (values (s.image_public_id, 'image'), (s.video_public_id, 'video')) as x(pid, rtype)
   where s.created_at < now() - p_older_than and x.pid is not null;
  delete from public.stories where created_at < now() - p_older_than;
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function public.close_stale_group_calls() returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update public.group_calls set ended = true, ringing = false, status = 'ended', ended_at = now()
   where ended = false and coalesce(last_heartbeat_at, started_at) < now() - interval '3 minutes';
  get diagnostics n = row_count;
  update public.calls set status = 'ended' where status in ('dialing','ringing') and created_at < now() - interval '2 minutes';
  return n;
end $$;

create or replace function public.purge_ephemeral_rows() returns void
language sql security definer set search_path = public as $$
  delete from public.typing_status where updated_at < now() - interval '1 minute';
  delete from public.group_typing_status where updated_at < now() - interval '1 minute';
  delete from public.ai_usage where created_at < now() - interval '90 days';
  delete from public.incident_reports where created_at < now() - interval '30 days';
$$;

-- ---------- helper: call an Edge Function from Postgres (needs vault secrets project_url + cron_secret) ----------
create or replace function public.call_edge(p_function text, p_body jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare url text; sec text;
begin
  begin
    select decrypted_secret into url from vault.decrypted_secrets where name = 'project_url' limit 1;
    select decrypted_secret into sec from vault.decrypted_secrets where name = 'cron_secret' limit 1;
  exception when others then return;
  end;
  if url is null or sec is null then return; end if;
  perform net.http_post(url := url || '/functions/v1/' || p_function,
                        headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', sec),
                        body := p_body);
exception when others then
  raise notice 'call_edge(%) skipped: %', p_function, sqlerrm;
end $$;

-- ---------- DB-driven notifications (group join request / accept) ----------
create or replace function public.trg_notify_join_request() returns trigger
language plpgsql security definer set search_path = public as $$
declare g public.groups; a record; u public.users;
begin
  select * into g from public.groups where id = new.group_id;
  if tg_op = 'INSERT' and new.status = 'pending' then
    select * into u from public.users where id = new.user_id;
    for a in select user_id from public.group_members where group_id = new.group_id and role in ('owner','admin') and membership_status = 'active' loop
      perform public.call_edge('send-notification', jsonb_build_object('type','group_join_request','receiverId',a.user_id,
        'groupId',new.group_id,'groupName',g.name,'actorId',new.user_id,'actorName',u.name,'actorImageUrl',coalesce(u.image_url,'')));
    end loop;
  elsif tg_op = 'UPDATE' and old.status <> 'accepted' and new.status = 'accepted' then
    perform public.call_edge('send-notification', jsonb_build_object('type','group_join_accept','receiverId',new.user_id,
      'groupId',new.group_id,'groupName',g.name,'actorImageUrl',coalesce(g.avatar_url,'')));
  end if;
  return null;
end $$;
drop trigger if exists trg_join_request_notify on public.group_join_requests;
create trigger trg_join_request_notify after insert or update on public.group_join_requests
  for each row execute function public.trg_notify_join_request();

-- ---------- schedules (idempotent) ----------
do $$
declare ok boolean := exists (select 1 from pg_extension where extname = 'pg_cron');
begin
  if not ok then raise notice 'pg_cron missing → schedules NOT created. Enable it in Dashboard → Database → Extensions, then re-run this file.'; return; end if;
  perform cron.unschedule(jobname) from cron.job where jobname in ('nexora-purge-stories','nexora-close-stale-calls','nexora-purge-ephemeral','nexora-flush-media-queue','nexora-sync-reels');
  perform cron.schedule('nexora-purge-stories',     '7 * * * *',    $c$select public.purge_expired_stories()$c$);
  perform cron.schedule('nexora-close-stale-calls', '*/5 * * * *',  $c$select public.close_stale_group_calls()$c$);
  perform cron.schedule('nexora-purge-ephemeral',   '30 3 * * *',   $c$select public.purge_ephemeral_rows()$c$);
  perform cron.schedule('nexora-flush-media-queue', '17 * * * *',   $c$select public.call_edge('delete-media-asset', '{"mode":"queue"}'::jsonb)$c$);
  perform cron.schedule('nexora-sync-reels',        '0 */6 * * *',  $c$select public.call_edge('sync-reels')$c$);
  raise notice 'Nexora cron jobs scheduled: %', (select count(*) from cron.job where jobname like 'nexora-%');
end $$;
