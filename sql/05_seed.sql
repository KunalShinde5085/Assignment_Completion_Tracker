-- ============================================================
-- AcademicFlow — 05_seed.sql
-- Default roles, permissions, role→permission mapping, and
-- system task types. Safe to re-run (idempotent upserts).
-- ============================================================

insert into roles (name, description) values
  ('SUPER_ADMIN',      'Full control of the institution, roles, and security settings'),
  ('ADMIN',            'Manages users, academic structure, subjects, tasks, approvals'),
  ('FACULTY',          'Manages assigned subjects, verifies student work'),
  ('DIVISION_MANAGER', 'Manages a single division''s tasks and announcements'),
  ('STUDENT',          'Default role for every student'),
  ('CLASS_REP',        'Student with limited proposal/announcement privileges'),
  ('MODERATOR',        'Reviews proposals and reports'),
  ('AUDITOR',          'Read-only access to audit logs and reports')
on conflict (name) do nothing;

insert into permissions (code, description) values
  ('manage_users',        'Create/edit/suspend users, resolve change requests'),
  ('manage_subjects',     'Manage academic structure, subjects, activities, task types, templates'),
  ('manage_admins',       'Invite/manage other admin accounts'),
  ('create_tasks',        'Create new shared tasks'),
  ('edit_tasks',          'Edit existing shared tasks'),
  ('publish_tasks',       'Publish tasks/announcements to a scope'),
  ('approve_tasks',       'Approve/reject proposals and reports'),
  ('verify_tasks',        'Verify student submissions/evidence'),
  ('view_reports',        'View analytics and student progress'),
  ('manage_files',        'Manage storage/evidence beyond own uploads'),
  ('view_audit',          'View the audit log')
on conflict (code) do nothing;

-- Role -> permission mapping
with rp as (
  select r.id as role_id, p.id as permission_id, r.name as rname, p.code as pcode
  from roles r cross join permissions p
)
insert into role_permissions (role_id, permission_id)
select role_id, permission_id from rp where
  (rname = 'SUPER_ADMIN') -- gets everything
  or (rname = 'ADMIN' and pcode in
      ('manage_users','manage_subjects','create_tasks','edit_tasks','publish_tasks',
       'approve_tasks','verify_tasks','view_reports','manage_files','view_audit'))
  or (rname = 'FACULTY' and pcode in
      ('create_tasks','edit_tasks','verify_tasks','view_reports'))
  or (rname = 'DIVISION_MANAGER' and pcode in
      ('create_tasks','edit_tasks','publish_tasks','view_reports'))
  or (rname = 'MODERATOR' and pcode in ('approve_tasks','view_reports'))
  or (rname = 'AUDITOR' and pcode in ('view_audit','view_reports'))
on conflict do nothing;

-- SUPER_ADMIN gets every permission explicitly (avoids relying on a
-- wildcard check anywhere in application code).
insert into role_permissions (role_id, permission_id)
select r.id, p.id from roles r cross join permissions p
where r.name = 'SUPER_ADMIN'
on conflict do nothing;

-- Global system task types (institution_id null = available everywhere)
insert into task_types (institution_id, name, code, is_system) values
  (null, 'Assignment',    'assignment',    true),
  (null, 'Write-up',      'writeup',       true),
  (null, 'Printout',      'printout',      true),
  (null, 'Output',        'output',        true),
  (null, 'Journal',       'journal',       true),
  (null, 'Practical',     'practical',     true),
  (null, 'Viva',          'viva',          true),
  (null, 'Presentation',  'presentation',  true),
  (null, 'Project',       'project',       true),
  (null, 'Documentation', 'documentation', true),
  (null, 'Submission',    'submission',    true),
  (null, 'Signature',     'signature',     true)
on conflict (institution_id, code) do nothing;

-- ------------------------------------------------------------
-- OPTIONAL: demo institution so you have something to click
-- around immediately after connecting the frontend. Delete this
-- block for a production deployment.
-- ------------------------------------------------------------
do $$
declare
  v_inst uuid;
  v_dept uuid;
  v_prog uuid;
  v_year uuid;
  v_sem  uuid;
  v_div  uuid;
begin
  insert into institutions (name, code) values ('Demo College of Engineering', 'DEMO')
    returning id into v_inst;
  insert into departments (institution_id, name, code) values (v_inst, 'Computer Engineering', 'CE')
    returning id into v_dept;
  insert into programs (department_id, institution_id, name, code) values (v_dept, v_inst, 'B.Tech Computer Engineering', 'BTCE')
    returning id into v_prog;
  insert into academic_years (institution_id, label, is_current) values (v_inst, '2026-2027', true)
    returning id into v_year;
  insert into semesters (program_id, academic_year_id, number, label) values (v_prog, v_year, 3, 'Semester 3')
    returning id into v_sem;
  insert into divisions (semester_id, name) values (v_sem, 'Division A')
    returning id into v_div;
end $$;
