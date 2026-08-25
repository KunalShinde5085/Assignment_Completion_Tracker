-- ============================================================
-- AcademicFlow — 04_storage.sql
-- Buckets: avatars (public read), task-evidence (private),
-- institution-assets (private, admin-managed).
--
-- Convention used for paths so storage policies can be expressed
-- purely from the path string (fast, no extra join needed):
--   avatars/{user_id}/...
--   task-evidence/{student_id}/{shared_task_id}/...
--   institution-assets/{institution_id}/...
-- ============================================================

insert into storage.buckets (id, name, public, file_size_limit)
values
  ('avatars', 'avatars', true, 5242880),               -- 5MB
  ('task-evidence', 'task-evidence', false, 20971520),  -- 20MB
  ('institution-assets', 'institution-assets', false, 20971520)
on conflict (id) do nothing;

-- ---------- avatars ----------

create policy avatars_public_read on storage.objects
  for select
  using (bucket_id = 'avatars');

create policy avatars_owner_write on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy avatars_owner_update on storage.objects
  for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

create policy avatars_owner_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------- task-evidence ----------
-- Path: task-evidence/{student_id}/{shared_task_id}/{filename}

create policy evidence_owner_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'task-evidence'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy evidence_staff_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'task-evidence'
    and has_permission(auth.uid(), 'verify_tasks')
  );

create policy evidence_owner_write on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'task-evidence'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy evidence_owner_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'task-evidence'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ---------- institution-assets ----------

create policy institution_assets_read on storage.objects
  for select to authenticated
  using (bucket_id = 'institution-assets');

create policy institution_assets_write on storage.objects
  for all to authenticated
  using (bucket_id = 'institution-assets' and has_permission(auth.uid(), 'manage_subjects'))
  with check (bucket_id = 'institution-assets' and has_permission(auth.uid(), 'manage_subjects'));
