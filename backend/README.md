# SkillBridge backend

The backend uses Supabase. The CLI project is under `supabase/`:

- `config.toml` — local Supabase project configuration.
- `migrations/` — schema and row-level security policies.
- `seed/` — intentionally empty of unowned demo courses; approved lecturers
  create courses and admins publish them.

## Hosted project

Apply every migration in timestamp order. If `supabase` is not recognized in
PowerShell, install the CLI locally from this `backend` directory with Node.js
20 or newer:

```powershell
npm install --save-dev supabase
npx supabase login
npx supabase link --project-ref YOUR_PROJECT_REF
npx supabase db push
```

Review the pending migration list before confirming `db push`. You can also
apply the SQL files in timestamp order in the Supabase SQL Editor. Phase 1 adds
student verification, lecturer applications, admin-managed roles, course
ownership and review, course content tables, private course resources, learner
progress, lecturer review responses and course insights, rating-aware course
discovery, audit records, and row-level security. Do not run only the latest
migration. See [`docs/auth-and-deployment.md`](docs/auth-and-deployment.md)
for auth redirects, OAuth, email templates, Edge Functions, and required secrets.

## First-run setup

1. Set `EDU_EMAIL_DOMAIN` in the Flutter dart-defines to the institution's
   actual email domain without a leading `@` (for example, `eastdelta.edu.bd`).
   Registration is blocked while the value is empty. The app does not assume
   one.
   Set the matching trusted database value in the Supabase SQL Editor:

   ```sql
   update public.platform_settings
   set edu_email_domain = 'your-real-edu-domain'
   where singleton = true;
   ```

   Keep the value identical in the database and `env/local.json`; the database
   trigger enforces it for public Auth signup requests.
2. Bootstrap the first administrator from the Supabase SQL Editor using the
   verified account's UUID:

   ```sql
   insert into public.user_roles (user_id, role)
   values ('YOUR_VERIFIED_USER_UUID', 'admin')
   on conflict (user_id, role) do nothing;
   ```

   Keep this operation in the trusted dashboard. Client-side administrator
   signup and role escalation are disabled.
3. New accounts receive the student role and a pending verification request.
   Administrators review students and lecturer applications in the Admin
   dashboard. Approved lecturers can create drafts and submit them for review;
   only administrators can publish courses.

## Local project

Install the Supabase CLI and Docker Desktop, then run these commands from this
`backend` directory:

```powershell
supabase start
supabase db reset
supabase test db
```

The Flutter client uses only the Supabase project URL and public anon/publishable
key. Never put a `service_role` key in the client app. See
[`docs/security.md`](docs/security.md) and
[`docs/database-design.md`](docs/database-design.md) before changing policies
or tables.

## Verification status

Flutter static analysis has no Dart issues and the current Flutter test suite
passes. The migrations and RLS policies have not been executed against a local
or hosted PostgreSQL instance in this environment; install the Supabase CLI and
Docker, then run `supabase db reset` and the database security tests before
shipping. Keep any project-specific SQL editor changes, including the EDU email
domain and first-admin bootstrap, in the trusted dashboard only.
The pgTAP suites in `supabase/tests/` check client grants and exercise role,
enrollment, course ownership, roster, and learner-progress boundaries. They are
committed as runnable coverage but still need execution with the local stack;
add scenarios for every role and storage operation before treating the RLS
matrix as fully verified.
