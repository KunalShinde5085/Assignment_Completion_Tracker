-- ============================================================
-- AcademicFlow — 02_functions.sql
-- Helper functions used by RLS policies + business-logic triggers.
--
-- IMPORTANT PATTERN: every function a policy calls to check "am I
-- allowed" is SECURITY DEFINER with `set search_path = public, pg_temp`.
-- This is what avoids the classic Supabase RLS recursion trap where
-- a policy on `user_roles` queries `user_roles`, or a hijacked
-- search_path lets a caller shadow a system table.
-- ============================================================

-- ---------- Permission / role checks ----------

create or replace function public.has_permission(p_user uuid, p_code text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from user_roles ur
    join role_permissions rp on rp.role_id = ur.role_id
    join permissions p on p.id = rp.permission_id
    where ur.user_id = p_user and p.code = p_code
  );
$$;

create or replace function public.has_role(p_user uuid, p_role text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from user_roles ur
    join roles r on r.id = ur.role_id
    where ur.user_id = p_user and r.name = p_role
  );
$$;

create or replace function public.current_user_permissions()
returns setof text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select distinct p.code
  from user_roles ur
  join role_permissions rp on rp.role_id = ur.role_id
  join permissions p on p.id = rp.permission_id
  where ur.user_id = auth.uid();
$$;

-- Same-institution helper (most permission checks should also be
-- scoped to the actor's own institution, not global).
create or replace function public.same_institution(p_user uuid, p_institution uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from profiles
    where id = p_user and institution_id = p_institution
  );
$$;

-- ---------- Scope engine ----------
-- Is `p_task` visible to `p_user` given its task_scopes rows?
create or replace function public.is_task_in_scope(p_task uuid, p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from task_scopes ts
    join profiles pr on pr.id = p_user
    where ts.shared_task_id = p_task
      and (
        ts.scope_type = 'institution'
        or (ts.scope_type = 'department'    and ts.scope_ref_id = pr.department_id)
        or (ts.scope_type = 'program'       and ts.scope_ref_id = pr.program_id)
        or (ts.scope_type = 'semester'      and ts.scope_ref_id = pr.semester_id)
        or (ts.scope_type = 'division'      and ts.scope_ref_id = pr.division_id)
        or (ts.scope_type = 'student'       and ts.scope_ref_id = pr.id)
      )
  );
$$;

-- ---------- Effective task list for the logged-in student ----------
-- Combines shared_tasks (in scope) with the student's own state row
-- when it exists, defaulting to 'not_started' when it doesn't
-- (the "lazy state creation" optimization from the plan).
create or replace function public.my_tasks()
returns table (
  task_id uuid,
  title text,
  subject_id uuid,
  activity_id uuid,
  task_type_id uuid,
  deadline timestamptz,
  priority text,
  requires_evidence boolean,
  effective_status text,
  effective_priority text,
  note text,
  completed_at timestamptz
)
language sql
stable
security invoker   -- runs as the caller; relies on RLS on the underlying tables
as $$
  select
    st.id,
    st.title,
    st.subject_id,
    st.activity_id,
    st.task_type_id,
    st.deadline,
    st.priority,
    st.requires_evidence,
    coalesce(sts.status, 'not_started')          as effective_status,
    coalesce(sts.priority_override, st.priority) as effective_priority,
    sts.note,
    sts.completed_at
  from shared_tasks st
  left join student_task_states sts
    on sts.shared_task_id = st.id and sts.student_id = auth.uid()
  where st.lifecycle_status = 'published'
    and is_task_in_scope(st.id, auth.uid());
$$;

-- ---------- Triggers: profile creation on signup ----------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_student_role_id uuid;
begin
  insert into public.profiles (id, full_name, account_status)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', ''), 'pending')
  on conflict (id) do nothing;

  select id into v_student_role_id from public.roles where name = 'STUDENT';
  if v_student_role_id is not null then
    insert into public.user_roles (user_id, role_id)
    values (new.id, v_student_role_id)
    on conflict do nothing;
  end if;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- Trigger: protect admin-controlled profile fields ----------
-- Students may edit name/phone/avatar/bio freely. Academic identity
-- fields (student_id, roll_number, department/program/semester/division)
-- can only change via someone holding `manage_users` — everyone else
-- must go through change_requests (section 16).

create or replace function public.protect_academic_fields()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if has_permission(auth.uid(), 'manage_users') then
    return new;
  end if;

  if new.student_id      is distinct from old.student_id
     or new.roll_number    is distinct from old.roll_number
     or new.department_id  is distinct from old.department_id
     or new.program_id     is distinct from old.program_id
     or new.semester_id    is distinct from old.semester_id
     or new.division_id    is distinct from old.division_id
     or new.institution_id is distinct from old.institution_id
     or new.account_status is distinct from old.account_status
  then
    raise exception 'Academic identity fields are protected. Submit a change_request instead.';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_protect_academic_fields on profiles;
create trigger trg_protect_academic_fields
  before update on profiles
  for each row execute function public.protect_academic_fields();

-- ---------- Trigger: shared_tasks versioning (section 31) ----------
-- Runs as the trigger owner so students/faculty never insert
-- task_versions rows themselves — they're a system-generated audit trail.

create or replace function public.record_task_version()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_diff jsonb := '{}'::jsonb;
begin
  if new.title       is distinct from old.title then
    v_diff := v_diff || jsonb_build_object('title', jsonb_build_object('old', old.title, 'new', new.title));
  end if;
  if new.deadline     is distinct from old.deadline then
    v_diff := v_diff || jsonb_build_object('deadline', jsonb_build_object('old', old.deadline, 'new', new.deadline));
  end if;
  if new.description  is distinct from old.description then
    v_diff := v_diff || jsonb_build_object('description', jsonb_build_object('old', old.description, 'new', new.description));
  end if;
  if new.priority     is distinct from old.priority then
    v_diff := v_diff || jsonb_build_object('priority', jsonb_build_object('old', old.priority, 'new', new.priority));
  end if;
  if new.lifecycle_status is distinct from old.lifecycle_status then
    v_diff := v_diff || jsonb_build_object('lifecycle_status', jsonb_build_object('old', old.lifecycle_status, 'new', new.lifecycle_status));
  end if;

  if v_diff <> '{}'::jsonb then
    new.current_version := old.current_version + 1;
    new.updated_at := now();
    insert into task_versions (shared_task_id, version_number, changed_by, diff)
    values (new.id, new.current_version, auth.uid(), v_diff);
  end if;

  return new;
end;
$$;

drop trigger if exists trg_record_task_version on shared_tasks;
create trigger trg_record_task_version
  before update on shared_tasks
  for each row execute function public.record_task_version();

-- ---------- Trigger: generic audit log for sensitive tables ----------

create or replace function public.write_audit_log()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into audit_logs (actor_id, action, entity_type, entity_id, old_value, new_value)
  values (
    auth.uid(),
    tg_op,
    tg_table_name,
    coalesce(new.id, old.id),
    case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else null end,
    case when tg_op in ('UPDATE','INSERT') then to_jsonb(new) else null end
  );
  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_audit_shared_tasks on shared_tasks;
create trigger trg_audit_shared_tasks
  after insert or update or delete on shared_tasks
  for each row execute function public.write_audit_log();

drop trigger if exists trg_audit_user_roles on user_roles;
create trigger trg_audit_user_roles
  after insert or update or delete on user_roles
  for each row execute function public.write_audit_log();

drop trigger if exists trg_audit_role_permissions on role_permissions;
create trigger trg_audit_role_permissions
  after insert or update or delete on role_permissions
  for each row execute function public.write_audit_log();

-- ---------- Trigger: change_request approval applies the change ----------

create or replace function public.apply_change_request()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.status = 'approved' and old.status is distinct from 'approved' then
    if new.field_name = 'division_id' then
      update profiles set division_id = new.requested_value::uuid where id = new.student_id;
    elsif new.field_name = 'program_id' then
      update profiles set program_id = new.requested_value::uuid where id = new.student_id;
    elsif new.field_name = 'semester_id' then
      update profiles set semester_id = new.requested_value::uuid where id = new.student_id;
    elsif new.field_name = 'department_id' then
      update profiles set department_id = new.requested_value::uuid where id = new.student_id;
    elsif new.field_name = 'roll_number' then
      update profiles set roll_number = new.requested_value where id = new.student_id;
    elsif new.field_name = 'student_id' then
      update profiles set student_id = new.requested_value where id = new.student_id;
    end if;
    new.reviewed_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists trg_apply_change_request on change_requests;
create trigger trg_apply_change_request
  before update on change_requests
  for each row execute function public.apply_change_request();

-- ---------- updated_at maintenance ----------

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger trg_touch_profiles        before update on profiles              for each row execute function touch_updated_at();
create trigger trg_touch_student_states  before update on student_task_states   for each row execute function touch_updated_at();
create trigger trg_touch_personal_tasks  before update on personal_tasks        for each row execute function touch_updated_at();

-- ---------- Duplicate-detection helper (section 29) ----------
-- Simple trigram-free heuristic: same subject + activity + task_type
-- + similar title (case-insensitive substring) within 14 days of
-- each other's deadline. Good enough for MVP; swap in pg_trgm
-- similarity() later if you enable the extension.

create or replace function public.find_possible_duplicates(
  p_subject uuid, p_activity uuid, p_task_type uuid, p_title text, p_deadline timestamptz
)
returns table (id uuid, title text, deadline timestamptz)
language sql
stable
security invoker
as $$
  select st.id, st.title, st.deadline
  from shared_tasks st
  where st.lifecycle_status = 'published'
    and st.subject_id is not distinct from p_subject
    and st.activity_id is not distinct from p_activity
    and st.task_type_id is not distinct from p_task_type
    and (
      lower(st.title) = lower(p_title)
      or lower(st.title) like '%' || lower(p_title) || '%'
      or lower(p_title) like '%' || lower(st.title) || '%'
    )
    and (p_deadline is null or st.deadline is null
         or abs(extract(epoch from (st.deadline - p_deadline))) < 14 * 86400);
$$;
