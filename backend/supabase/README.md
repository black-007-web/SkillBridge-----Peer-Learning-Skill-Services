# Supabase setup

The schema and later role, course, notification, and authorization updates are
in timestamped `migrations/`. `seed/seed.sql` intentionally adds no unowned demo
courses; create real courses through an approved lecturer account.

For local development, install the Supabase CLI and Docker, then run
`supabase start` and `supabase db reset` from the `backend` directory. To set
up a hosted project, apply the migration and run the seed SQL through the
Supabase SQL editor.

The Flutter app connects with `SUPABASE_URL` and the public anon/publishable key
provided via Dart `--dart-define` values. Do not use a service-role key in the
mobile/web client.
