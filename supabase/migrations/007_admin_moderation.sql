-- ============================================================================
-- Nexora backend — 007: admin roles, sanctions (warn / suspend / ban), audit log,
-- report review, AI usage log, write-blocking for sanctioned accounts,
-- real suspension state in get_app_system_status.
-- ============================================================================

create table if not exists public.app_admins (
  user_id uuid primary key references public.users(id) on delete cascade,
  role text not null default 'moderator' check (role in ('moderator','admin','owner')),
  created_at timestamptz not null default now()
);

create table if not exists public.user_sanctions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  kind text not null check (kind in ('warning','suspension','ban')),
  reason text not null,
  starts_at timestamptz not null default now(),
  expires_at timestamptz,                       -- null = permanent
  created_by uuid references public.users(id) on delete set null,
  revoked_at timestamptz,
  revoked_by uuid references public.users(id) on delete set null,
  revoke_reason text,
  created_at timestamptz not null default now()
);
create index if not exists user_sanctions_active_idx on public.user_sanctions (user_id) where revoked_at is null;

create table if not exists public.admin_audit_log (
  id bigint generated always as identity primary key,
  admin_id uuid references public.users(id) on delete set null,
  action text not null,
  target_user_id uuid,
  target_type text, target_id text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists audit_created_idx on public.admin_audit_log (created_at desc);

create table if not exists public.ai_usage (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.users(id) on delete cascade,
  action text not null, provider text, model text,
  tokens_in int not null default 0, tokens_out int not null default 0,
  success boolean not null default true, request_id text,
  created_at timestamptz not null default now()
);
create index if not exists ai_usage_user_idx on public.ai_usage (user_id, created_at desc);

create table if not exists public.media_cleanup_queue (
  id bigint generated always as identity primary key,
  public_id text not null, resource_type text not null default 'image',
  created_at timestamptz not null default now()
);

alter table public.reports
  add column if not exists reviewed_by uuid references public.users(id) on delete set null,
  add column if not exists reviewed_at timestamptz,
  add column if not exists resolution text,
  add column if not exists action_taken text;
create index if not exists reports_status_idx on public.reports (status, created_at desc);

-- ---------- role helpers ----------
create or replace function public.role_rank(r text) returns int language sql immutable as $$
  select case r when 'owner' then 3 when 'admin' then 2 when 'moderator' then 1 else 0 end;
$$;

create or replace function public.is_admin(p_user_id uuid default auth.uid(), p_min_role text default 'moderator')
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.app_admins a
                  where a.user_id = p_user_id and public.role_rank(a.role) >= public.role_rank(p_min_role));
$$;

-- ---------- sanction state ----------
create or replace function public.active_sanction(p_user_id uuid)
returns public.user_sanctions language sql stable security definer set search_path = public as $$
  select s.* from public.user_sanctions s
   where s.user_id = p_user_id and s.kind in ('suspension','ban') and s.revoked_at is null
     and s.starts_at <= now() and (s.expires_at is null or s.expires_at > now())
   order by (s.expires_at is null) desc, s.expires_at desc nulls first, s.created_at desc limit 1;
$$;

create or replace function public.is_sanctioned(p_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.user_sanctions s
   where s.user_id = p_user_id and s.kind in ('suspension','ban') and s.revoked_at is null
     and s.starts_at <= now() and (s.expires_at is null or s.expires_at > now()));
$$;

create or replace function public.get_my_active_sanction()
returns table (id uuid, kind text, reason text, expires_at timestamptz)
language sql stable security definer set search_path = public as $$
  select s.id, s.kind, s.reason, s.expires_at from public.active_sanction(auth.uid()) s where s.id is not null;
$$;

-- ---------- admin actions (authorisation enforced here, not in the client) ----------
create or replace function public.admin_apply_sanction(p_user_id uuid, p_kind text, p_reason text, p_duration_hours int default null)
returns uuid language plpgsql security definer set search_path = public, auth as $$
declare me uuid := auth.uid(); sid uuid; exp timestamptz;
begin
  if not public.is_admin(me, case when p_kind = 'ban' then 'admin' else 'moderator' end) then raise exception 'forbidden'; end if;
  if p_kind not in ('warning','suspension','ban') then raise exception 'invalid_kind'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'reason_required'; end if;
  if p_user_id = me then raise exception 'cannot_sanction_self'; end if;
  -- cannot act on someone with an equal or higher admin role
  if (select public.role_rank(role) from public.app_admins where user_id = p_user_id) >= (select public.role_rank(role) from public.app_admins where user_id = me) then
    raise exception 'insufficient_role'; end if;
  exp := case when p_duration_hours is null or p_kind = 'warning' then null else now() + make_interval(hours => p_duration_hours) end;
  insert into public.user_sanctions (user_id, kind, reason, expires_at, created_by)
  values (p_user_id, p_kind, trim(p_reason), exp, me) returning id into sid;
  if p_kind = 'ban' then
    update auth.users set banned_until = coalesce(exp, 'infinity'::timestamptz) where id = p_user_id;
    delete from auth.sessions where user_id = p_user_id;
  end if;
  insert into public.admin_audit_log (admin_id, action, target_user_id, target_type, target_id, details)
  values (me, 'sanction_' || p_kind, p_user_id, 'user', p_user_id::text, jsonb_build_object('sanction_id', sid, 'reason', p_reason, 'expires_at', exp));
  return sid;
end $$;

create or replace function public.admin_revoke_sanction(p_sanction_id uuid, p_reason text default null)
returns void language plpgsql security definer set search_path = public, auth as $$
declare me uuid := auth.uid(); s public.user_sanctions;
begin
  if not public.is_admin(me, 'moderator') then raise exception 'forbidden'; end if;
  select * into s from public.user_sanctions where id = p_sanction_id and revoked_at is null;
  if s.id is null then raise exception 'not_found'; end if;
  if s.kind = 'ban' and not public.is_admin(me, 'admin') then raise exception 'forbidden'; end if;
  update public.user_sanctions set revoked_at = now(), revoked_by = me, revoke_reason = p_reason where id = s.id;
  if s.kind = 'ban' and not exists (select 1 from public.user_sanctions x where x.user_id = s.user_id and x.kind = 'ban' and x.revoked_at is null and (x.expires_at is null or x.expires_at > now())) then
    update auth.users set banned_until = null where id = s.user_id;
  end if;
  insert into public.admin_audit_log (admin_id, action, target_user_id, target_type, target_id, details)
  values (me, 'sanction_revoked', s.user_id, 'user', s.user_id::text, jsonb_build_object('sanction_id', s.id, 'reason', p_reason));
end $$;

create or replace function public.admin_resolve_report(p_report_id uuid, p_status text, p_resolution text default null, p_action text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin(auth.uid(), 'moderator') then raise exception 'forbidden'; end if;
  if p_status not in ('open','reviewing','resolved','dismissed') then raise exception 'invalid_status'; end if;
  update public.reports set status = p_status, resolution = p_resolution, action_taken = p_action, reviewed_by = auth.uid(), reviewed_at = now() where id = p_report_id;
  insert into public.admin_audit_log (admin_id, action, target_type, target_id, details)
  values (auth.uid(), 'report_' || p_status, 'report', p_report_id::text, jsonb_build_object('resolution', p_resolution, 'action', p_action));
end $$;

create or replace function public.admin_set_role(p_user_id uuid, p_role text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin(auth.uid(), 'owner') then raise exception 'forbidden'; end if;
  if p_role = 'none' then delete from public.app_admins where user_id = p_user_id;
  elsif p_role in ('moderator','admin','owner') then
    insert into public.app_admins (user_id, role) values (p_user_id, p_role) on conflict (user_id) do update set role = excluded.role;
  else raise exception 'invalid_role'; end if;
  insert into public.admin_audit_log (admin_id, action, target_user_id, details) values (auth.uid(), 'set_role', p_user_id, jsonb_build_object('role', p_role));
end $$;

create or replace function public.admin_list_reports(p_status text default 'open', p_limit int default 50, p_offset int default 0)
returns setof public.reports language sql stable security definer set search_path = public as $$
  select r.* from public.reports r where public.is_admin(auth.uid(), 'moderator') and (p_status is null or r.status = p_status)
   order by r.created_at desc limit greatest(p_limit,1) offset greatest(p_offset,0);
$$;

-- ---------- block write operations of sanctioned accounts ----------
create or replace function public.enforce_not_sanctioned() returns trigger
language plpgsql security definer set search_path = public as $$
declare col text := tg_argv[0]; uid uuid; s public.user_sanctions;
begin
  uid := nullif(to_jsonb(new) ->> col, '')::uuid;
  if uid is null then return new; end if;
  s := public.active_sanction(uid);
  if s.id is not null then
    raise exception 'account_sanctioned' using errcode = 'P0001', detail = coalesce(s.reason, ''), hint = coalesce(s.expires_at::text, 'permanent');
  end if;
  return new;
end $$;

do $$
declare r record;
begin
  for r in select * from (values
    ('messages','sender_id'), ('group_messages','sender_id'), ('posts','author_id'), ('comments','author_id'),
    ('stories','author_id'), ('calls','caller_id'), ('friendships','requester_id'), ('follows','follower_id'),
    ('group_join_requests','user_id'), ('message_requests','sender_id'), ('post_likes','user_id'), ('comment_reactions','user_id'),
    ('message_reactions','user_id'), ('story_reactions','user_id'), ('post_shares','user_id'), ('ai_chat_messages','user_id')
  ) as t(tbl, col) loop
    execute format('drop trigger if exists trg_not_sanctioned on public.%I', r.tbl);
    execute format('create trigger trg_not_sanctioned before insert on public.%I for each row execute function public.enforce_not_sanctioned(%L)', r.tbl, r.col);
  end loop;
end $$;

-- ---------- real suspension state for the app's system gate ----------
create or replace function public.get_app_system_status(p_app_version text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare s public.app_system_control; active boolean; sanc public.user_sanctions;
begin
  select * into s from public.app_system_control where id = 1;
  active := s.maintenance_enabled
            and (s.maintenance_starts_at is null or s.maintenance_starts_at <= now())
            and (s.maintenance_ends_at   is null or s.maintenance_ends_at   >  now());
  if auth.uid() is not null then sanc := public.active_sanction(auth.uid()); end if;
  return jsonb_build_object(
    'ok', true,
    'maintenance_enabled', s.maintenance_enabled,
    'maintenance_active', active,
    'maintenance_bypassed', auth.uid() is not null and public.is_admin(auth.uid(), 'moderator'),
    'maintenance_message', s.maintenance_message,
    'maintenance_starts_at', s.maintenance_starts_at,
    'maintenance_ends_at', s.maintenance_ends_at,
    'min_supported_version', s.min_supported_version,
    'recommended_version', s.recommended_version,
    'update_required', p_app_version is not null and s.min_supported_version is not null and public.compare_versions(p_app_version, s.min_supported_version) < 0,
    'update_recommended', p_app_version is not null and s.recommended_version is not null and public.compare_versions(p_app_version, s.recommended_version) < 0,
    'banner_message', s.banner_message,
    'banner_severity', s.banner_severity,
    'is_caller_suspended', sanc.id is not null,
    'suspension_reason', sanc.reason,
    'suspension_expires_at', sanc.expires_at,
    'server_time', now());
end $$;
grant execute on function public.get_app_system_status(text) to anon, authenticated;

-- ---------- RLS ----------
alter table public.app_admins enable row level security;
alter table public.user_sanctions enable row level security;
alter table public.admin_audit_log enable row level security;
alter table public.ai_usage enable row level security;
alter table public.media_cleanup_queue enable row level security;

drop policy if exists admins_sel on public.app_admins;
create policy admins_sel on public.app_admins for select to authenticated using (user_id = auth.uid() or public.is_admin(auth.uid(), 'moderator'));
drop policy if exists sanctions_sel on public.user_sanctions;
create policy sanctions_sel on public.user_sanctions for select to authenticated using (user_id = auth.uid() or public.is_admin(auth.uid(), 'moderator'));
drop policy if exists audit_sel on public.admin_audit_log;
create policy audit_sel on public.admin_audit_log for select to authenticated using (public.is_admin(auth.uid(), 'admin'));
drop policy if exists aiu_sel on public.ai_usage;
create policy aiu_sel on public.ai_usage for select to authenticated using (user_id = auth.uid());
drop policy if exists rep_sel on public.reports;
create policy rep_sel on public.reports for select to authenticated using (reporter_id = auth.uid() or public.is_admin(auth.uid(), 'moderator'));
-- no insert/update/delete policies on the tables above: all writes go through SECURITY DEFINER functions / service role

-- users can never edit their own privileged data: block updates of sensitive columns on public.users
create or replace function public.protect_user_columns() returns trigger language plpgsql as $$
begin
  if auth.uid() is not null and auth.uid() = old.id and coalesce(auth.role(), '') <> 'service_role' then
    new.id := old.id; new.is_deleted := old.is_deleted; new.deleted_at := old.deleted_at; new.created_at := old.created_at;
  end if;
  return new;
end $$;
drop trigger if exists trg_protect_user_columns on public.users;
create trigger trg_protect_user_columns before update on public.users for each row execute function public.protect_user_columns();

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
