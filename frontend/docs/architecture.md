# Architecture

- `../lib/main.dart` validates compile-time Supabase settings and initializes the
  client only when a valid URL and public key are provided.
- `../lib/app.dart` configures the Material app and shared theme.
- `../lib/features/home/home_screen.dart` contains the four-tab app shell, course
  catalog, and initial profile/learning views.
- `../lib/features/auth/login_screen.dart` provides email sign-in and registration.
- `../lib/services/course_service.dart` reads published courses from Supabase or
  supplies clearly identified preview data when the backend is not configured.
- `../../backend/supabase/migrations/` is the source of truth for the initial
  database schema and row-level security policies.

The learning, profile, messaging, admin, lecturer, and social feature folders
from the original scaffold were empty placeholders. They should be implemented
as separate feature modules as product requirements are finalized; they are
not currently production workflows.