-- ============================================================================
-- Nexora backend — 008: Supabase Storage buckets + policies
-- NOTE: the Flutter app currently uploads media to Cloudinary (CLOUDINARY_* secrets).
-- These buckets are provided for native Supabase storage / future migration and are safe to leave unused.
-- Path convention (enforced by policies): <owner_uid>/<anything>
-- ============================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('avatars',     'avatars',     true,  5242880,   array['image/jpeg','image/png','image/webp']),
  ('covers',      'covers',      true,  8388608,   array['image/jpeg','image/png','image/webp']),
  ('posts',       'posts',       true,  52428800,  array['image/jpeg','image/png','image/webp','image/gif','video/mp4','video/quicktime','video/webm']),
  ('stories',     'stories',     true,  52428800,  array['image/jpeg','image/png','image/webp','video/mp4','video/quicktime']),
  ('reels',       'reels',       true,  104857600, array['video/mp4','video/quicktime','video/webm']),
  ('chat-files',  'chat-files',  false, 26214400,  array['image/jpeg','image/png','image/webp','image/gif','video/mp4','audio/mpeg','audio/mp4','audio/aac','audio/ogg','audio/webm','application/pdf','application/zip','text/plain']),
  ('group-files', 'group-files', false, 26214400,  array['image/jpeg','image/png','image/webp','image/gif','video/mp4','audio/mpeg','audio/mp4','audio/aac','audio/ogg','audio/webm','application/pdf','application/zip','text/plain'])
on conflict (id) do update set public = excluded.public, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

-- public buckets: anyone can read; only the owner folder can write
do $$
declare b text;
begin
  foreach b in array array['avatars','covers','posts','stories','reels'] loop
    execute format('drop policy if exists "%s_read" on storage.objects', b);
    execute format('create policy "%s_read" on storage.objects for select to anon, authenticated using (bucket_id = %L)', b, b);
    execute format('drop policy if exists "%s_insert" on storage.objects', b);
    execute format('create policy "%s_insert" on storage.objects for insert to authenticated with check (bucket_id = %L and (storage.foldername(name))[1] = auth.uid()::text and not public.is_sanctioned(auth.uid()))', b, b);
    execute format('drop policy if exists "%s_update" on storage.objects', b);
    execute format('create policy "%s_update" on storage.objects for update to authenticated using (bucket_id = %L and (storage.foldername(name))[1] = auth.uid()::text)', b, b);
    execute format('drop policy if exists "%s_delete" on storage.objects', b);
    execute format('create policy "%s_delete" on storage.objects for delete to authenticated using (bucket_id = %L and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin(auth.uid(), ''moderator'')))', b, b);
  end loop;
end $$;

-- chat-files: <uploader_uid>/<peer_uid>/<file>  → readable by uploader and peer only
drop policy if exists chat_files_read on storage.objects;
create policy chat_files_read on storage.objects for select to authenticated using (
  bucket_id = 'chat-files' and (auth.uid()::text = (storage.foldername(name))[1] or auth.uid()::text = (storage.foldername(name))[2]));
drop policy if exists chat_files_insert on storage.objects;
create policy chat_files_insert on storage.objects for insert to authenticated with check (
  bucket_id = 'chat-files' and (storage.foldername(name))[1] = auth.uid()::text and not public.is_sanctioned(auth.uid()));
drop policy if exists chat_files_delete on storage.objects;
create policy chat_files_delete on storage.objects for delete to authenticated using (
  bucket_id = 'chat-files' and (storage.foldername(name))[1] = auth.uid()::text);

-- group-files: <group_uuid>/<uploader_uid>/<file> → members read, member writes into own subfolder
drop policy if exists group_files_read on storage.objects;
create policy group_files_read on storage.objects for select to authenticated using (
  bucket_id = 'group-files' and public.is_group_member(((storage.foldername(name))[1])::uuid, auth.uid()));
drop policy if exists group_files_insert on storage.objects;
create policy group_files_insert on storage.objects for insert to authenticated with check (
  bucket_id = 'group-files' and public.is_group_member(((storage.foldername(name))[1])::uuid, auth.uid())
  and (storage.foldername(name))[2] = auth.uid()::text and not public.is_sanctioned(auth.uid()));
drop policy if exists group_files_delete on storage.objects;
create policy group_files_delete on storage.objects for delete to authenticated using (
  bucket_id = 'group-files' and ((storage.foldername(name))[2] = auth.uid()::text or public.is_group_admin(((storage.foldername(name))[1])::uuid, auth.uid())));
