# AcademicFlow

A student task-tracking platform built on **HTML + CSS + vanilla JavaScript + Supabase**
(Postgres, Auth, Storage). Answers one question for a student: *what do I still have to do?*

This is the MVP slice of the larger plan (roles/permissions, shared tasks with
per-student completion state, personal tasks, subject progress, admin task
publishing, proposals/reports/change-request moderation, basic analytics).
Sections marked V2/V3 in the original spec (notifications, calendar,
announcements UI, templates UI, CSV import, realtime, AI layer) have
database tables ready for them but no frontend yet — see "What's scaffolded
vs. built" below.

## 1. Set up Supabase

1. Create a project at https://supabase.com.
2. Open the SQL editor and run the files in `sql/` **in order**:
   1. `00_extensions.sql`
   2. `01_schema.sql`
   3. `02_functions.sql`
   4. `03_rls.sql`
   5. `04_storage.sql`
   6. `05_seed.sql` (creates default roles/permissions/task types + one
      demo institution — delete the `do $$ ... $$` block at the bottom
      if you don't want the demo data)
3. In **Authentication → URL Configuration**, add
   `http://localhost:PORT/reset-password.html` (and your production URL)
   to the redirect allow-list, or the "forgot password" email link won't work.
4. In **Authentication → Providers**, email/password is on by default —
   that's all this build uses.

### Making your first user an admin

New signups get the `STUDENT` role automatically (via the
`handle_new_user` trigger). To promote your own account after signing up
once through the app:

```sql
insert into user_roles (user_id, role_id)
select p.id, r.id
from profiles p, roles r
where p.id = 'YOUR-AUTH-USER-UUID'   -- from auth.users
  and r.name = 'ADMIN';

update profiles set institution_id = (select id from institutions limit 1),
  account_status = 'active'
where id = 'YOUR-AUTH-USER-UUID';
```

## 2. Configure the frontend

Edit `frontend/js/config.js`:

```js
export const SUPABASE_URL = 'https://YOUR-PROJECT-REF.supabase.co';
export const SUPABASE_ANON_KEY = 'YOUR-ANON-PUBLIC-KEY';
```

Both values are in **Project Settings → API**. The anon key is safe to
ship in client code — Row Level Security is the actual gate.

## 3. Run it

No build step. Any static file server works, e.g. from `frontend/`:

```bash
npx serve .
# or: python3 -m http.server 8080
```

Then open `http://localhost:PORT/` — it redirects to `login.html` or
`dashboard.html` depending on session state.

## Why the RLS is structured this way

Two mistakes sink most hand-rolled Supabase RLS setups, so both are
designed out from the start:

- **Recursive policies.** A naive policy like "admins can see all
  profiles" that queries `user_roles` from *inside* a policy on
  `profiles`/`user_roles` can recurse or get silently blocked. Every
  permission check here goes through `has_permission()` / `has_role()`,
  which are `SECURITY DEFINER` functions with a locked `search_path` —
  they run outside RLS, so no recursion, and no ambiguity about which
  `user_roles` table they're reading.
- **Column-level "protection" that RLS can't express.** RLS is row-level
  only. "Students can edit their name but not their division" is
  enforced by a trigger (`protect_academic_fields`) that raises an
  exception on any protected-column diff from a non-admin — combined
  with the `change_requests` table as the sanctioned path for those
  edits.

Everything that writes an audit trail (`task_versions`, `audit_logs`) has
**no INSERT policy for any role** — those rows only come from
`SECURITY DEFINER` trigger functions, so a student (or a compromised
frontend) cannot fabricate history.

## What's scaffolded vs. built

**Built (working end-to-end):**
Signup / login / forgot-password / reset-password, profile view + edit,
academic-field change requests, dashboard with live stats, "My Work"
(shared tasks + personal tasks, filters, status updates), subject
progress view, and an admin panel for publishing shared tasks
(with a duplicate-check call), reviewing proposals/reports/change
requests, suspending/activating users, and a bare-bones completion
analytics tally.

**Scaffolded in SQL, no frontend yet (V2/V3 in the original plan):**
`announcements`, `notifications`, `templates`/`template_items`,
`task_versions` (viewable via SQL/API, no UI timeline yet), CSV bulk
import, Supabase Realtime subscriptions, calendar view, and the future
AI/document-intelligence layer. Wiring these up is mostly writing a new
page + service file against tables and RLS policies that already exist.

## Project layout

```
sql/
  00_extensions.sql
  01_schema.sql        all tables
  02_functions.sql      SECURITY DEFINER helpers + triggers (versioning, audit, profile protection)
  03_rls.sql            RLS enable + policies for every table
  04_storage.sql        storage buckets + storage RLS
  05_seed.sql            default roles/permissions/task types + demo data
frontend/
  *.html                 one page per route, no build step
  css/styles.css
  js/
    config.js            <- put your Supabase URL/key here
    supabaseClient.js
    state/appState.js     tiny in-memory state, no localStorage of sensitive data
    services/             one file per domain (auth, tasks, profile, admin)
    pages/                one controller script per HTML page
    components/sidebar.js
    utils/                dom helpers, date/urgency formatting, auth guard
```
