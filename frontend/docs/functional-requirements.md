# Current functional scope

## Implemented in this starter

- Browse published courses from Supabase; use visibly labeled sample data when
  no backend configuration is supplied.
- Register and sign in with email/password using Supabase Auth.
- Enroll the signed-in user in a published course and list their enrollments.
- Restrict profiles, courses, and enrollment data through database RLS policies.

## Not implemented

- Course lessons, learning progress, assessments, certificates, or payments.
- Profile editing, role-based admin/lecturer dashboards, or course authoring.
- Announcements, messaging, notifications, resources, or peer-learning flows.
- Password recovery, native auth deep links, or push notifications.

These are product features, not missing package imports. They need requirements,
implementation, and end-to-end tests before the application can be considered
production complete.