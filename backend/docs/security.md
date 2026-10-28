# Security and deployment notes

- The client receives only the Supabase URL and public anon/publishable key.
  Never ship a Supabase service-role key or another server secret in a Flutter
  build; values compiled into a client can be extracted.
- The migrations enable row-level security on all application tables.
  Anonymous and signed-in clients can read only published courses. Verified
  users can read and update only permitted fields in their own profile,
  preferences, notifications, and enrollments. Role assignment and transactional
  email queue records are server-side only.
- `is_verified_user()` checks `auth.users.email_confirmed_at` in a
  security-definer function. Policies also require the caller's own `auth.uid()`.
  The client cannot write roles or verification status.
- The private `avatars` bucket limits files to 2 MiB and JPEG, PNG, and WebP.
  Storage policies scope every object path to the authenticated user's UUID.
  The app checks image signatures and uses signed URLs for display.
- Configure Supabase email confirmation, password reset, Google OAuth, SMTP,
  and redirect/deep link URLs for each environment using
  [`auth-and-deployment.md`](auth-and-deployment.md). The Flutter app uses
  Supabase Auth's SDK-managed refresh and stores sessions and PKCE verifiers
  through `flutter_secure_storage`. Browser storage still depends on HTTPS and
  the browser's security boundary.
- Account deletion uses an authenticated Edge Function with the service-role
  key held only in Edge Function secrets. It requires a current password or a
  recent sign-in, removes avatar objects, then deletes the Auth user so dependent
  rows cascade.
- Review every SQL function and policy with both anon and authenticated clients
  before deployment. The generated platform projects still need production
  application IDs, signing credentials, privacy disclosure, and release review.
- The generated platform projects still need production application IDs,
  signing credentials, privacy disclosures, and release review. Do not treat
  the starter as security-certified or launch-ready without those checks.
