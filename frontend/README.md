# SkillBridge Flutter frontend

This directory contains the Flutter application and its Android, iOS, and web
platform projects.

## Run locally

From this directory, run without Supabase for the sample preview:

```powershell
flutter pub get
flutter run -d chrome
```

### Configured Chrome run

The repository-root `env/local.json` contains local Dart defines and is
git-ignored. Copy `env/local.example.json` to `env/local.json`, then fill in
your Supabase project URL, public publishable key, and actual institution
domain as `EDU_EMAIL_DOMAIN` (for example, `eastdelta.edu.bd`, without `@`).
Set the same domain in
`public.platform_settings` as documented in [`../backend/README.md`](../backend/README.md).
When running from this
`frontend` directory, start Chrome at port 7357 with:

```powershell
flutter run -d chrome --web-port=7357 --dart-define-from-file=../env/local.json
```

`flutter run -d chrome` is the plain preview command; `-plain run` is not a
valid Flutter option. The public anon/publishable key is intended for client
apps; never put a `service_role` key in a Flutter app or local config file.

## Backend setup

See [`../backend/README.md`](../backend/README.md). Run the Supabase CLI from
the `backend` directory. Configure email confirmation, email templates, and
redirect/deep-link URLs for your app in Supabase Authentication settings.

## Test and build

```powershell
flutter test
flutter analyze
flutter build appbundle --dart-define-from-file=../env/local.json
```

For web use `flutter build web` with the same `--dart-define` arguments. iOS
builds require macOS and Xcode. Android release builds require the Android SDK
and accepted Android SDK licenses.

## Before production release

Phase 1 now includes role gated dashboards, student and lecturer approval,
course authoring and moderation, private resources, enrollment, course
discovery filters and pagination, learner lesson progress, lecturer course
insights and rosters, review replies, announcements, notifications, support
tickets, and audit views. Flutter analysis reports no issues and the existing
Flutter test suite passes. The latest database migrations have not yet been
applied to the hosted project or verified against live RLS policies; database
security tests still need to be run against a local Supabase stack. Messaging
and peer learning are outside Phase 1. Before launch, apply and test every
migration, configure production auth email/deep links and the institution's
`EDU_EMAIL_DOMAIN`, and complete app signing and identifiers, privacy policy
and terms, monitoring/backups, and release-specific QA. See
[`../backend/docs/security.md`](../backend/docs/security.md) and
[`docs/architecture.md`](docs/architecture.md).
