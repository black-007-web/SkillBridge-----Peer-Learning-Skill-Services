# Supabase setup

The schema and later role, course, notification, and authorization updates are
in timestamped `migrations/`. `seed/seed.sql` intentionally adds no unowned demo
courses; create real courses through an approved lecturer account.
Apply `20261101000000_course_resource_any_file_type.sql` to hosted projects to
allow course-resource uploads of any MIME type. The private bucket's 50 MiB
per-file limit and lecturer authorization policies remain in force; zero-byte
files are supported. Apply `20261101000001_user_and_course_image_limits.sql`
to raise the private `avatars` bucket limit to 5 MiB and allow JPEG, PNG, WebP,
GIF, and BMP images for profile and course-cover uploads.

For local development, install the Supabase CLI and Docker, then run
`supabase start` and `supabase db reset` from the `backend` directory. To set
up a hosted project, apply the migration and run the seed SQL through the
Supabase SQL editor.

The Flutter app connects with `SUPABASE_URL` and the public anon/publishable key
provided via Dart `--dart-define` values. Do not use a service-role key in the
mobile/web client.
