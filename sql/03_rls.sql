-- ============================================================
-- AcademicFlow — 03_rls.sql
-- Enable RLS on every table and define policies.
--
-- Rule of thumb used throughout:
--   SELECT  -> broad-ish (own data, or in-scope, or has a view_* permission)
--   INSERT  -> must be inserting as/for yourself, OR hold the specific
--              create_* permission
--   UPDATE  -> own row + narrow field set (enforced by triggers where
--              SQL alone can't express column-level rules), OR permission
--   DELETE  -> almost never a hard delete for normal users; soft-delete
--              via lifecycle_status/deleted_at columns instead, gated
--              by permission
-- ============================================================

alter table institutions        enable row level security;
alter table departments         enable row level security;
alter table programs            enable row level security;
alter table academic_years      enable row level security;
alter table semesters           enable row level security;
alter table divisions           enable row level security;
alter table profiles            enable row level security;
alter table roles               enable row level security;
alter table permissions         enable row level security;
alter table role_permissions    enable row level security;
alter table user_roles          enable row level security;
alter table admin_invitations   enable row level security;
alter table subjects            enable row level security;
alter table subject_faculty     enable row level security;
alter table activities          enable row level security;
alter table task_types          enable row level security;
alter table statuses            enable row level security;
alter table shared_tasks        enable row level security;
alter table task_scopes         enable row level security;
alter table task_versions       enable row level security;
alter table student_task_states enable row level security;
alter table personal_tasks      enable row level security;
alter table task_submissions    enable row level security;
alter table task_proposals      enable row level security;
alter table task_reports        enable row level security;
alter table change_requests     enable row level security;
alter table announcements       enable row level security;
alter table notifications       enable row level security;
alter table templates           enable row level security;
alter table template_items      enable row level security;
alter table audit_logs          enable row level security;

-- ---------- institutions / departments / programs / academic_years / semesters / divisions ----------
-- Read-only reference data for any authenticated user in that institution;
-- writes gated behind manage_subjects (kept coarse — split further if needed).

create policy institutions_select on institutions
  for select to authenticated
  using (true);  -- institution list itself isn't sensitive (needed at signup)

create policy institutions_write on institutions
  for all to authenticated
  using (has_permission(auth.uid(), 'manage_subjects'))
  with check (has_permission(auth.uid(), 'manage_subjects'));

create policy departments_select on departments
  for select to authenticated using (true);
create policy departments_write on departments
  for all to authenticated
  using (has_permission(auth.uid(), 'manage_subjects'))
  with check (has_permission(auth.uid(), 'manage_subjects'));

create policy programs_select on programs
  for select to authenticated using (true);
create policy programs_write on programs
  for all to authenticated
  using (has_permission(auth.uid(), 'manage_subjects'))
  with check (has_permission(auth.uid(), 'manage_subjects'));

create policy academic_years_select on academic_years
  for select to authenticated using (true);
create policy academic_years_write on academic_years
  for all to authenticated
  using (has_permission(auth.uid(), 'manage_subjects'))
  with check (has_permission(auth.uid(), 'manage_subjects'));

create policy semesters_select on semesters
  for select to authenticated using (true);
create policy semesters_write on semesters
  for all to authenticated
  using (has_permission(auth.uid(), 'manage_subjects'))
  with check (has_permission(auth.uid(), 'manage_subjects'));

create policy divisions_select on divisions
  for select to authenticated using (true);
create policy divisions_write on divisions
  for all to authenticated
  using (has_permission(auth.uid(), 'manage_subjects'))
  with check (has_permission(auth.uid(), 'manage_subjects'));

-- ---------- profiles ----------

create policy profiles_select_own on profiles
  for select to authenticated
  using (id = auth.uid());

create policy profiles_select_admin on profiles
  for select to authenticated
  using (has_permission(auth.uid(), 'manage_users'));

-- Faculty can see students in subjects they teach (needed for analytics/verification).
create policy profiles_select_faculty on profiles
  for select to authenticated
  using (
    has_permission(auth.uid(), 'view_reports')
    and exists (
      select 1 from subject_faculty sf
      join subjects s on s.id = sf.subject_id
      where sf.faculty_id = auth.uid()
        and s.semester_id = profiles.semester_id
    )
  );

-- INSERT happens only via the handle_new_user trigger (SECURITY DEFINER),
-- so no direct insert policy is granted to regular users.
create policy profiles_insert_admin on profiles
  for insert to authenticated
  with check (has_permission(auth.uid(), 'manage_users'));

-- Anyone can update their own row; the protect_academic_fields trigger
-- blocks changes to admin-controlled columns unless they hold manage_users.
create policy profiles_update_own on profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

create policy profiles_update_admin on profiles
  for update to authenticated
  using (has_permission(auth.uid(), 'manage_users'))
  with check (has_permission(auth.uid(), 'manage_users'));

-- ---------- roles / permissions / role_permissions ----------
-- Reference data: readable by anyone authenticated (needed to render
-- permission-gated UI), writable only by SUPER_ADMIN.

create policy roles_select on roles for select to authenticated using (true);
create policy roles_write on roles for all to authenticated
  using (has_role(auth.uid(), 'SUPER_ADMIN'))
  with check (has_role(auth.uid(), 'SUPER_ADMIN'));

create policy permissions_select on permissions for select to authenticated using (true);
create policy permissions_write on permissions for all to authenticated
  using (has_role(auth.uid(), 'SUPER_ADMIN'))
  with check (has_role(auth.uid(), 'SUPER_ADMIN'));

create policy role_permissions_select on role_permissions for select to authenticated using (true);
create policy role_permissions_write on role_permissions for all to authenticated
  using (has_role(auth.uid(), 'SUPER_ADMIN'))
  with check (has_role(auth.uid(), 'SUPER_ADMIN'));

-- ---------- user_roles ----------

create policy user_roles_select_own on user_roles
  for select to authenticated using (user_id = auth.uid());
create policy user_roles_select_admin on user_roles
  for select to authenticated using (has_permission(auth.uid(), 'manage_users'));
create policy user_roles_write_admin on user_roles
  for all to authenticated
  using (has_permission(auth.uid(), 'manage_users'))
  with check (has_permission(auth.uid(), 'manage_users'));

-- ---------- admin_invitations ----------

create policy admin_invitations_manage on admin_invitations
  for all to authenticated
  using (has_permission(auth.uid(), 'manage_admins'))
  with check (has_permission(auth.uid(), 'manage_admins'));

-- ---------- subjects / subject_faculty / activities / task_types / statuses ----------

create policy subjects_select on subjects
  for select to authenticated using (deleted_at is null);
create policy subjects_write on subjects
  for all to authenticated
  using (has_permission(auth.uid(), 'manage_subjects'))
  with check (has_permission(auth.uid(), 'manage_subjects'));

create policy subject_faculty_select on subject_faculty
  for select to authenticated
  using (faculty_id = auth.uid() or has_permission(auth.uid(), 'manage_subjects'));
create policy subject_faculty_write on subject_faculty
  for all to authenticated
  using (has_permission(auth.uid(), 'manage_subjects'))
  with check (has_permission(auth.uid(), 'manage_subjects'));

create policy activities_select on activities
  for select to authenticated using (deleted_at is null);
create policy activities_write on activities
  for all to authenticated
  using (has_permission(auth.uid(), 'manage_subjects'))
  with check (has_permission(auth.uid(), 'manage_subjects'));

create policy task_types_select on task_types for select to authenticated using (true);
create policy task_types_write on task_types
  for all to authenticated
  using (has_permission(auth.uid(), 'manage_subjects'))
  with check (has_permission(auth.uid(), 'manage_subjects'));

create policy statuses_select on statuses for select to authenticated using (true);
create policy statuses_write on statuses
  for all to authenticated
  using (has_permission(auth.uid(), 'manage_subjects'))
  with check (has_permission(auth.uid(), 'manage_subjects'));

-- ---------- shared_tasks ----------

create policy shared_tasks_select on shared_tasks
  for select to authenticated
  using (
    lifecycle_status = 'published' and is_task_in_scope(id, auth.uid())
    or created_by = auth.uid()
    or has_permission(auth.uid(), 'view_reports')
  );

create policy shared_tasks_insert on shared_tasks
  for insert to authenticated
  with check (has_permission(auth.uid(), 'create_tasks') and created_by = auth.uid());

create policy shared_tasks_update on shared_tasks
  for update to authenticated
  using (has_permission(auth.uid(), 'edit_tasks') or has_permission(auth.uid(), 'publish_tasks'))
  with check (has_permission(auth.uid(), 'edit_tasks') or has_permission(auth.uid(), 'publish_tasks'));

-- No hard delete policy: archive via lifecycle_status update instead.

-- ---------- task_scopes ----------

create policy task_scopes_select on task_scopes
  for select to authenticated
  using (
    exists (
      select 1 from shared_tasks st
      where st.id = task_scopes.shared_task_id
        and (is_task_in_scope(st.id, auth.uid()) or st.created_by = auth.uid()
             or has_permission(auth.uid(), 'view_reports'))
    )
  );

create policy task_scopes_write on task_scopes
  for all to authenticated
  using (has_permission(auth.uid(), 'publish_tasks'))
  with check (has_permission(auth.uid(), 'publish_tasks'));

-- ---------- task_versions (read-only to end users; writes are trigger-only) ----------

create policy task_versions_select on task_versions
  for select to authenticated
  using (
    exists (
      select 1 from shared_tasks st
      where st.id = task_versions.shared_task_id
        and (is_task_in_scope(st.id, auth.uid()) or has_permission(auth.uid(), 'view_reports'))
    )
  );
-- Deliberately no insert/update/delete policy: only the SECURITY DEFINER
-- trigger function (record_task_version) writes here.

-- ---------- student_task_states ----------

create policy student_task_states_select_own on student_task_states
  for select to authenticated using (student_id = auth.uid());

create policy student_task_states_select_staff on student_task_states
  for select to authenticated using (has_permission(auth.uid(), 'view_reports'));

create policy student_task_states_insert_own on student_task_states
  for insert to authenticated
  with check (
    student_id = auth.uid()
    and is_task_in_scope(shared_task_id, auth.uid())
  );

create policy student_task_states_update_own on student_task_states
  for update to authenticated
  using (student_id = auth.uid())
  with check (student_id = auth.uid());

create policy student_task_states_verify_staff on student_task_states
  for update to authenticated
  using (has_permission(auth.uid(), 'verify_tasks'))
  with check (has_permission(auth.uid(), 'verify_tasks'));

-- ---------- personal_tasks (fully private) ----------

create policy personal_tasks_all_own on personal_tasks
  for all to authenticated
  using (student_id = auth.uid())
  with check (student_id = auth.uid());

-- ---------- task_submissions ----------

create policy task_submissions_select_own on task_submissions
  for select to authenticated using (student_id = auth.uid());
create policy task_submissions_select_staff on task_submissions
  for select to authenticated using (has_permission(auth.uid(), 'verify_tasks'));

create policy task_submissions_insert_own on task_submissions
  for insert to authenticated
  with check (
    student_id = auth.uid()
    and is_task_in_scope(shared_task_id, auth.uid())
  );

create policy task_submissions_verify_staff on task_submissions
  for update to authenticated
  using (has_permission(auth.uid(), 'verify_tasks'))
  with check (has_permission(auth.uid(), 'verify_tasks'));

-- ---------- task_proposals ----------

create policy task_proposals_select_own on task_proposals
  for select to authenticated using (proposed_by = auth.uid());
create policy task_proposals_select_reviewers on task_proposals
  for select to authenticated using (has_permission(auth.uid(), 'approve_tasks'));

create policy task_proposals_insert_own on task_proposals
  for insert to authenticated
  with check (proposed_by = auth.uid());

create policy task_proposals_review on task_proposals
  for update to authenticated
  using (has_permission(auth.uid(), 'approve_tasks'))
  with check (has_permission(auth.uid(), 'approve_tasks'));

-- ---------- task_reports ----------

create policy task_reports_select_own on task_reports
  for select to authenticated using (reported_by = auth.uid());
create policy task_reports_select_moderators on task_reports
  for select to authenticated using (has_permission(auth.uid(), 'approve_tasks'));

create policy task_reports_insert_own on task_reports
  for insert to authenticated
  with check (reported_by = auth.uid());

create policy task_reports_resolve on task_reports
  for update to authenticated
  using (has_permission(auth.uid(), 'approve_tasks'))
  with check (has_permission(auth.uid(), 'approve_tasks'));

-- ---------- change_requests ----------

create policy change_requests_select_own on change_requests
  for select to authenticated using (student_id = auth.uid());
create policy change_requests_select_admin on change_requests
  for select to authenticated using (has_permission(auth.uid(), 'manage_users'));

create policy change_requests_insert_own on change_requests
  for insert to authenticated
  with check (student_id = auth.uid());

create policy change_requests_review on change_requests
  for update to authenticated
  using (has_permission(auth.uid(), 'manage_users'))
  with check (has_permission(auth.uid(), 'manage_users'));

-- ---------- announcements ----------

create policy announcements_select on announcements
  for select to authenticated
  using (
    scope_type = 'institution'
    or created_by = auth.uid()
    or exists (
      select 1 from profiles pr
      where pr.id = auth.uid()
        and (
          (announcements.scope_type = 'department' and announcements.scope_ref_id = pr.department_id) or
          (announcements.scope_type = 'program'    and announcements.scope_ref_id = pr.program_id) or
          (announcements.scope_type = 'semester'   and announcements.scope_ref_id = pr.semester_id) or
          (announcements.scope_type = 'division'   and announcements.scope_ref_id = pr.division_id) or
          (announcements.scope_type = 'student'    and announcements.scope_ref_id = pr.id)
        )
    )
  );

create policy announcements_write on announcements
  for all to authenticated
  using (has_permission(auth.uid(), 'publish_tasks'))
  with check (has_permission(auth.uid(), 'publish_tasks'));

-- ---------- notifications ----------
-- Users only ever see/mark-read their own; inserts are done by
-- SECURITY DEFINER service functions (see 02_functions.sql pattern),
-- not directly by arbitrary users — so no general insert policy.

create policy notifications_select_own on notifications
  for select to authenticated using (user_id = auth.uid());

create policy notifications_update_own on notifications
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());  -- e.g. marking is_read = true

create policy notifications_insert_staff on notifications
  for insert to authenticated
  with check (has_permission(auth.uid(), 'manage_users'));

-- ---------- templates / template_items ----------

create policy templates_select on templates for select to authenticated using (true);
create policy templates_write on templates
  for all to authenticated
  using (has_permission(auth.uid(), 'manage_subjects'))
  with check (has_permission(auth.uid(), 'manage_subjects'));

create policy template_items_select on template_items for select to authenticated using (true);
create policy template_items_write on template_items
  for all to authenticated
  using (has_permission(auth.uid(), 'manage_subjects'))
  with check (has_permission(auth.uid(), 'manage_subjects'));

-- ---------- audit_logs ----------
-- Write-only via triggers; readable only with view_audit.

create policy audit_logs_select on audit_logs
  for select to authenticated using (has_permission(auth.uid(), 'view_audit'));
-- No insert/update/delete policy granted to any role — only the
-- SECURITY DEFINER write_audit_log() trigger function can write here.
