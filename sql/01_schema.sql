-- ============================================================
-- AcademicFlow — 01_schema.sql
-- Core tables. Run after 00_extensions.sql.
-- Naming: snake_case everywhere, uuid PKs, soft-delete via
-- `deleted_at timestamptz` rather than hard DELETE for anything
-- with academic weight (section 33 of the plan).
-- ============================================================

-- ---------- Academic hierarchy (all optional/nullable on purpose,
--            per "flexible academic hierarchy" — section 4) ----------

create table institutions (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  code          text unique,
  created_at    timestamptz not null default now(),
  deleted_at    timestamptz
);

create table departments (
  id              uuid primary key default gen_random_uuid(),
  institution_id  uuid not null references institutions(id) on delete cascade,
  name            text not null,
  code            text,
  created_at      timestamptz not null default now(),
  deleted_at      timestamptz,
  unique (institution_id, code)
);

create table programs (
  id              uuid primary key default gen_random_uuid(),
  department_id   uuid references departments(id) on delete cascade,
  institution_id  uuid not null references institutions(id) on delete cascade,
  name            text not null,
  code            text,
  created_at      timestamptz not null default now(),
  deleted_at      timestamptz
);

create table academic_years (
  id              uuid primary key default gen_random_uuid(),
  institution_id  uuid not null references institutions(id) on delete cascade,
  label           text not null,          -- e.g. '2026-2027'
  start_date      date,
  end_date        date,
  is_current      boolean not null default false,
  created_at      timestamptz not null default now()
);

create table semesters (
  id              uuid primary key default gen_random_uuid(),
  program_id      uuid references programs(id) on delete cascade,
  academic_year_id uuid references academic_years(id) on delete set null,
  number          int not null,
  label           text,                    -- e.g. 'Semester 3'
  created_at      timestamptz not null default now()
);

create table divisions (
  id              uuid primary key default gen_random_uuid(),
  semester_id     uuid references semesters(id) on delete cascade,
  name            text not null,           -- e.g. 'Division A'
  created_at      timestamptz not null default now()
);

-- ---------- Identity, roles, permissions ----------

create table profiles (
  id                uuid primary key references auth.users(id) on delete cascade,
  institution_id    uuid references institutions(id) on delete set null,
  full_name         text,
  avatar_url        text,
  phone             text,
  bio               text,
  -- protected / admin-controlled academic identity fields (section 15)
  student_id        text,
  roll_number       text,
  department_id     uuid references departments(id) on delete set null,
  program_id        uuid references programs(id) on delete set null,
  semester_id       uuid references semesters(id) on delete set null,
  division_id       uuid references divisions(id) on delete set null,
  account_status    text not null default 'pending'
                      check (account_status in ('pending','active','suspended','deactivated','archived')),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create unique index profiles_student_id_per_institution
  on profiles (institution_id, student_id) where student_id is not null;

create table roles (
  id            uuid primary key default gen_random_uuid(),
  name          text unique not null,   -- SUPER_ADMIN, ADMIN, FACULTY, DIVISION_MANAGER, STUDENT, CLASS_REP, MODERATOR, AUDITOR
  description   text
);

create table permissions (
  id            uuid primary key default gen_random_uuid(),
  code          text unique not null,   -- manage_users, manage_subjects, create_tasks, ...
  description   text
);

create table role_permissions (
  role_id       uuid not null references roles(id) on delete cascade,
  permission_id uuid not null references permissions(id) on delete cascade,
  primary key (role_id, permission_id)
);

create table user_roles (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references profiles(id) on delete cascade,
  role_id       uuid not null references roles(id) on delete cascade,
  assigned_by   uuid references profiles(id),
  assigned_at   timestamptz not null default now(),
  unique (user_id, role_id)
);

create table admin_invitations (
  id            uuid primary key default gen_random_uuid(),
  email         citext not null,
  institution_id uuid references institutions(id) on delete cascade,
  role_id       uuid not null references roles(id),
  invited_by    uuid references profiles(id),
  token         uuid not null default gen_random_uuid(),
  status        text not null default 'pending' check (status in ('pending','accepted','revoked','expired')),
  expires_at    timestamptz not null default (now() + interval '7 days'),
  created_at    timestamptz not null default now()
);

-- ---------- Subjects / activities / task types ----------

create table subjects (
  id            uuid primary key default gen_random_uuid(),
  institution_id uuid not null references institutions(id) on delete cascade,
  program_id    uuid references programs(id) on delete set null,
  semester_id   uuid references semesters(id) on delete set null,
  name          text not null,
  code          text,
  is_active     boolean not null default true,
  created_by    uuid references profiles(id),
  created_at    timestamptz not null default now(),
  deleted_at    timestamptz
);

create table subject_faculty (
  id            uuid primary key default gen_random_uuid(),
  subject_id    uuid not null references subjects(id) on delete cascade,
  faculty_id    uuid not null references profiles(id) on delete cascade,
  assigned_at   timestamptz not null default now(),
  unique (subject_id, faculty_id)
);

create table activities (
  id            uuid primary key default gen_random_uuid(),
  subject_id    uuid not null references subjects(id) on delete cascade,
  name          text not null,          -- 'Experiment 1', 'Unit Test', ...
  order_index   int not null default 0,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  deleted_at    timestamptz
);

create table task_types (
  id            uuid primary key default gen_random_uuid(),
  institution_id uuid references institutions(id) on delete cascade,  -- null = global system default
  name          text not null,
  code          text not null,
  is_system     boolean not null default false,
  created_at    timestamptz not null default now(),
  unique (institution_id, code)
);

-- Reference table for future custom workflows (section 7 — V2 feature).
-- MVP uses the fixed status set on student_task_states directly;
-- this table exists so a workflow can be swapped in later without a
-- schema migration.
create table statuses (
  id            uuid primary key default gen_random_uuid(),
  task_type_id  uuid references task_types(id) on delete cascade,
  name          text not null,
  order_index   int not null default 0,
  is_terminal   boolean not null default false
);

-- ---------- Shared task engine ----------

create table shared_tasks (
  id                uuid primary key default gen_random_uuid(),
  institution_id    uuid not null references institutions(id) on delete cascade,
  subject_id        uuid references subjects(id) on delete set null,
  activity_id       uuid references activities(id) on delete set null,
  task_type_id      uuid references task_types(id) on delete set null,
  title             text not null,
  description       text,
  deadline          timestamptz,
  priority          text not null default 'medium' check (priority in ('low','medium','high')),
  requires_evidence boolean not null default false,
  lifecycle_status  text not null default 'published'
                       check (lifecycle_status in ('draft','published','archived','deleted')),
  current_version   int not null default 1,
  created_by        uuid references profiles(id),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create table task_scopes (
  id              uuid primary key default gen_random_uuid(),
  shared_task_id  uuid not null references shared_tasks(id) on delete cascade,
  scope_type      text not null check (scope_type in
                     ('institution','department','program','academic_year','semester','division','student')),
  scope_ref_id    uuid,   -- null only valid when scope_type = 'institution'
  created_at      timestamptz not null default now()
);
create index task_scopes_lookup on task_scopes (scope_type, scope_ref_id);
create index task_scopes_task on task_scopes (shared_task_id);

create table task_versions (
  id              uuid primary key default gen_random_uuid(),
  shared_task_id  uuid not null references shared_tasks(id) on delete cascade,
  version_number  int not null,
  changed_by      uuid references profiles(id),
  change_reason   text,
  diff            jsonb not null,     -- {"deadline": {"old": "...", "new": "..."}}
  created_at      timestamptz not null default now(),
  unique (shared_task_id, version_number)
);

-- Per-student completion state. NOT created eagerly for every student
-- (section 10 lazy-creation optimization) — absence of a row means
-- "not_started". See sql/02_functions.sql: my_tasks_view().
create table student_task_states (
  id              uuid primary key default gen_random_uuid(),
  shared_task_id  uuid not null references shared_tasks(id) on delete cascade,
  student_id      uuid not null references profiles(id) on delete cascade,
  status          text not null default 'not_started'
                    check (status in ('not_started','in_progress','ready_for_submission','submitted','verified')),
  priority_override text check (priority_override in ('low','medium','high')),
  reminder_at     timestamptz,
  note            text,
  completed_at    timestamptz,
  updated_at      timestamptz not null default now(),
  unique (shared_task_id, student_id)
);
create index student_task_states_student on student_task_states (student_id);

create table personal_tasks (
  id            uuid primary key default gen_random_uuid(),
  student_id    uuid not null references profiles(id) on delete cascade,
  title         text not null,
  description   text,
  task_type_id  uuid references task_types(id) on delete set null,
  deadline      timestamptz,
  priority      text not null default 'medium' check (priority in ('low','medium','high')),
  status        text not null default 'not_started'
                  check (status in ('not_started','in_progress','completed')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- ---------- Evidence / submissions (section 43-44) ----------

create table task_submissions (
  id              uuid primary key default gen_random_uuid(),
  shared_task_id  uuid not null references shared_tasks(id) on delete cascade,
  student_id      uuid not null references profiles(id) on delete cascade,
  storage_path    text not null,     -- path inside the 'task-evidence' bucket
  file_name       text not null,
  mime_type       text,
  size_bytes      bigint,
  verification_status text not null default 'pending'
                       check (verification_status in ('pending','verified','rejected')),
  verified_by     uuid references profiles(id),
  verified_at     timestamptz,
  uploaded_at     timestamptz not null default now()
);

-- ---------- Governance: proposals, reports, change requests ----------

create table task_proposals (
  id            uuid primary key default gen_random_uuid(),
  proposed_by   uuid not null references profiles(id) on delete cascade,
  title         text not null,
  description   text,
  subject_id    uuid references subjects(id) on delete set null,
  activity_id   uuid references activities(id) on delete set null,
  task_type_id  uuid references task_types(id) on delete set null,
  deadline      timestamptz,
  target_scope  jsonb,               -- {"scope_type":"division","scope_ref_id":"..."}
  status        text not null default 'pending'
                  check (status in ('pending','approved','rejected','merged')),
  duplicate_of  uuid references shared_tasks(id),
  reviewed_by   uuid references profiles(id),
  reviewed_at   timestamptz,
  review_notes  text,
  created_at    timestamptz not null default now()
);

create table task_reports (
  id              uuid primary key default gen_random_uuid(),
  shared_task_id  uuid not null references shared_tasks(id) on delete cascade,
  reported_by     uuid not null references profiles(id) on delete cascade,
  reason          text not null,   -- wrong_subject, wrong_division, wrong_deadline, duplicate, ...
  description     text,
  status          text not null default 'open' check (status in ('open','resolved','dismissed')),
  resolved_by     uuid references profiles(id),
  resolved_at     timestamptz,
  created_at      timestamptz not null default now()
);

create table change_requests (
  id                uuid primary key default gen_random_uuid(),
  student_id        uuid not null references profiles(id) on delete cascade,
  field_name        text not null,     -- 'division_id', 'program_id', etc.
  current_value     text,
  requested_value   text not null,
  reason            text,
  status            text not null default 'pending' check (status in ('pending','approved','rejected')),
  reviewed_by       uuid references profiles(id),
  reviewed_at       timestamptz,
  created_at        timestamptz not null default now()
);

-- ---------- Announcements & notifications ----------

create table announcements (
  id              uuid primary key default gen_random_uuid(),
  institution_id  uuid not null references institutions(id) on delete cascade,
  title           text not null,
  body            text,
  scope_type      text not null check (scope_type in
                     ('institution','department','program','academic_year','semester','division','student')),
  scope_ref_id    uuid,
  linked_task_id  uuid references shared_tasks(id) on delete set null,
  created_by      uuid references profiles(id),
  created_at      timestamptz not null default now()
);

create table notifications (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references profiles(id) on delete cascade,
  type          text not null,   -- new_task, deadline_changed, proposal_approved, ...
  title         text not null,
  body          text,
  related_id    uuid,
  is_read       boolean not null default false,
  created_at    timestamptz not null default now()
);
create index notifications_user_unread on notifications (user_id, is_read);

-- ---------- Templates (section 53-54) ----------

create table templates (
  id            uuid primary key default gen_random_uuid(),
  institution_id uuid not null references institutions(id) on delete cascade,
  name          text not null,
  description   text,
  version       int not null default 1,
  created_by    uuid references profiles(id),
  created_at    timestamptz not null default now()
);

create table template_items (
  id            uuid primary key default gen_random_uuid(),
  template_id   uuid not null references templates(id) on delete cascade,
  task_type_id  uuid references task_types(id) on delete set null,
  title         text not null,
  order_index   int not null default 0
);

-- ---------- Audit log (write-only for normal users) ----------

create table audit_logs (
  id            uuid primary key default gen_random_uuid(),
  actor_id      uuid references profiles(id),
  action        text not null,
  entity_type   text not null,
  entity_id     uuid,
  old_value     jsonb,
  new_value     jsonb,
  reason        text,
  created_at    timestamptz not null default now()
);
create index audit_logs_entity on audit_logs (entity_type, entity_id);
