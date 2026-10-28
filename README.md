# SkillBridge

The project is organized into two application areas:

- [`frontend/`](frontend/): Flutter app, Android/iOS/web runners, assets, and
  client tests.
- [`backend/`](backend/): Supabase configuration, database migrations, seed
  data, and backend documentation.

## Start the app

Open PowerShell in `frontend` and run:

```powershell
flutter pub get
flutter run
```

Without Supabase settings the app runs in preview mode. For backend setup,
production limitations, and release instructions, see
[`frontend/README.md`](frontend/README.md). Backend setup is documented in
[`backend/README.md`](backend/README.md).
