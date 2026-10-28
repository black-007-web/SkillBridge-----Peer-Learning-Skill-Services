# SkillBridge authentication and deployment

## What the app provides

- Supabase email/password registration and login, Google OAuth entry, email OTP
  verification with a resend cooldown, password reset and password change.
- GoRouter auth redirects and protected profile, settings, notifications, and
  recovery routes. Supabase's auth stream restores and refreshes sessions.
- Profile editing and private avatars. Avatar images are checked for JPEG, PNG,
  or WebP signatures and limited to 2 MiB before upload.
- Registration collects a phone number as profile contact information. Account
  verification codes are sent to email; SMS verification is not required.
- Per-user notification preferences and a database-backed notification inbox.
- Account deletion through an authenticated Edge Function, including avatar
  cleanup. User-owned rows cascade from `auth.users`.
- A transactional email outbox, branded confirmation/recovery templates, and
  an idempotent Resend welcome-email function.

## Configure the Flutter app

The app uses only the public Supabase URL and publishable key. Never pass the
service-role key to Flutter. Set the public legal document URLs before building;
the project does not invent Terms or Privacy content for you.

```powershell
cd frontend
flutter pub get
flutter run `
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLIC_PUBLISHABLE_KEY `
  --dart-define=TERMS_URL=https://YOUR_SITE/terms `
  --dart-define=PRIVACY_URL=https://YOUR_SITE/privacy
```

Web deployments must use HTTPS for secure browser storage. Native callback
schemes are already declared in `android/app/src/main/AndroidManifest.xml` and
`ios/Runner/Info.plist`:

- `skillbridge://auth-callback`
- `skillbridge://reset-password`

Add both exact URLs, plus your production website URLs and local development
origins, to Supabase **Authentication → URL Configuration → Redirect URLs**.
Set the production website as the Site URL. The local `config.toml` includes
the native URLs and the local web redirect.

## Apply the database changes

From `backend/`, link the Supabase CLI to the intended project and apply all
migrations in timestamp order:

```powershell
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase db push
```

The migrations create profile columns, safe student-role provisioning,
notification preferences and records, an email outbox, verified-user RLS
policies, and a private avatar bucket. Do not expose the outbox or role writes
to client roles. The `is_verified_user()` function is used by policies so an
unverified email account cannot access protected user data even if it bypasses
the Flutter router.

## Email verification and recovery

In **Authentication → Providers → Email**, enable email confirmations and set
the password policy and rate limits appropriate for the deployment. Configure
a trusted SMTP provider in **Authentication → SMTP Settings** before production;
the default service is restricted to project team addresses and heavily
rate-limited, so it is only suitable for evaluation.

### SMTP without buying a domain

You can test with a provider that supports **single-sender verification**. For
example, SendGrid lets you verify an existing email address without changing
domain DNS. This is intended for testing and may have weaker inbox delivery than
an authenticated domain. You must be able to receive and approve the provider's
sender-verification message.

1. Create a SendGrid account and verify one sender address you control.
2. Create an API key with Mail Send permission. Keep it private.
3. In Supabase **Authentication → SMTP Settings**, enable custom SMTP and enter:

   - Sender email: the exact address verified in SendGrid
   - Sender name: `SkillBridge`
   - Host: `smtp.sendgrid.net`
   - Port: `587`
   - Username: `apikey`
   - Password: the SendGrid API key

4. Save settings and test registration with an email address you can access.
   Supabase's confirmation template controls whether the message contains the
   numeric code; SMTP controls sending and delivery.

Do not use this single-sender setup as a deliverability guarantee for a public
launch. SendGrid recommends domain authentication for production mail. If you
later decide to use a domain, you can authenticate one you already own; you do
not have to purchase a new domain specifically for Supabase.

The local `supabase/config.toml` enables email confirmation and configures the
confirmation template with an 8-digit OTP. For a hosted Supabase project, open
**Authentication → Email Templates → Confirm signup**, set the subject to
`Your SkillBridge registration code`, and replace the template body with
`supabase/templates/auth_confirmation.html`. The body must contain
`{{ .Token }}`; a template that still uses `{{ .ConfirmationURL }}` sends a link
instead of a code. Save the template and enable email confirmations. Copy
`supabase/templates/password_recovery.html` into the recovery template and keep
its `{{ .ConfirmationURL }}` link. Then use **Resend code** for an unverified
test registration and verify that a numeric code arrives. Test invalid/expired
codes, resend cooldown, password reset links, and reset on each platform.

The welcome email is intentionally separate from Supabase's verification
email. It tells the recipient to use the Auth verification message rather than
creating a second or fabricated verification link.

## Phone number and email OTP

Registration collects a phone number in E.164 format, such as `+8801...` or
`+14155552671`, for the user's profile. Email/password remains the sign-in
method, and the confirmation code is sent to the registered email address.
Supabase's hosted **Confirm signup** template must include `{{ .Token }}`. The
app verifies the code with the email OTP endpoint; an SMS provider is not needed
for this flow. Local config sets code length to 8 digits; the hosted project
uses its own OTP length setting.

Set OTP expiry and email rate limits in Supabase Auth. Test signup, valid,
incorrect and expired codes, resend cooldown, and protected page access.

## Google OAuth

1. Create a Google Cloud OAuth **Web application** client and configure the
   consent screen/audience for the intended users.
2. In Supabase **Authentication → Providers → Google**, enable Google and add
   the client ID and client secret. The Google authorized redirect URI must be
   the Supabase project's `/auth/v1/callback` URL shown on that provider page.
3. Add the web origin and the two `skillbridge://` callbacks to Supabase's
   redirect allowlist. Keep the Google client secret in Supabase dashboard
   configuration or Edge Function/server secrets, never in Flutter.
4. Configure the intended test users/publishing audience in Google Cloud.
   Android signing IDs, production package IDs, and web origins still need to
   be supplied for release builds.

OAuth is coded but cannot succeed until the Google provider credentials and
redirect allowlist are configured in the project dashboard.

## Welcome email function

The Auth user trigger inserts one `welcome` row per account into
`transactional_email_outbox`. Deploy both functions:

```powershell
cd backend
supabase functions deploy welcome-email --no-verify-jwt
supabase functions deploy delete-account
```

Set Edge Function secrets in the Supabase project (never in Flutter or source
control):

```powershell
supabase secrets set `
  RESEND_API_KEY=YOUR_RESEND_API_KEY `
  WELCOME_FROM="SkillBridge <welcome@YOUR_VERIFIED_DOMAIN>" `
  WELCOME_SUPPORT_EMAIL=support@YOUR_DOMAIN `
  APP_URL=https://YOUR_APP_DOMAIN `
  WELCOME_WEBHOOK_SECRET=GENERATE_A_LONG_RANDOM_SECRET
```

Supabase supplies `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and
`SUPABASE_SERVICE_ROLE_KEY` to Edge Functions. The service-role secret stays
server-side.

In **Database → Webhooks**, create an INSERT webhook on
`public.transactional_email_outbox` targeting
`https://YOUR_PROJECT_REF.supabase.co/functions/v1/welcome-email`. Send JSON
with `Authorization: Bearer <WELCOME_WEBHOOK_SECRET>` and
`Content-Type: application/json`. Keep the webhook secret in the dashboard's
server-side webhook configuration. The handler uses the outbox row ID as the
Resend idempotency key, records attempts, and applies exponential retry delay.

For recovery if a webhook delivery fails, enable `pg_cron`, `pg_net`, and Vault
for the project, put the project URL and webhook secret in Vault, then schedule
a five-minute POST to the same function with body `{"batch":true}`. The batch
handler processes at most 25 due outbox records each run. Never paste a live
secret into a checked-in SQL file or client build. After creating Vault secrets
named `skillbridge_project_url` and `skillbridge_welcome_secret`, the schedule
can use:

```sql
select cron.schedule(
  'skillbridge-welcome-email-retry',
  '*/5 * * * *',
  $$
    select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets
              where name = 'skillbridge_project_url') || '/functions/v1/welcome-email',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (select decrypted_secret
          from vault.decrypted_secrets where name = 'skillbridge_welcome_secret')
      ),
      body := '{"batch":true}'::jsonb
    );
  $$
);
```

## Account deletion and session behavior

`delete-account` validates the caller's Supabase session. Email/password users
must supply the current password; OAuth users must have signed in recently.
The function removes the caller's avatar objects before deleting the Auth user.
If storage cleanup fails, it leaves the account in place so deletion can be
retried. Profile, role, notification, enrollment, and outbox rows cascade on
Auth-user deletion. Supabase/provider backups may retain data according to
their documented retention period.

The profile Log out action signs out only the current device. Account Settings
offers a separate all-sessions sign-out using Supabase's global sign-out scope.
Access tokens already issued can remain valid until expiry; refresh tokens are
revoked by Supabase.

## Dashboard values still required

- A Supabase project URL and publishable key for each build environment.
- Supabase Auth email confirmation, SMTP, confirmation/recovery templates,
  allowed redirects, and suitable rate limits.
- Google OAuth client credentials and provider enablement.
- Public Terms and Privacy URLs supplied as `TERMS_URL` and `PRIVACY_URL`.
- A verified Resend sender domain, API key, outbox webhook, and retry schedule
  if you want the separate welcome-email function.
- Android/iOS production identifiers, signing configuration, and real-device
  verification of OAuth and image-picker callbacks.

The repository includes the integration code and local project configuration;
it cannot apply hosted migrations, enable dashboard providers, verify a sender
domain, or provision credentials without access to those accounts.
