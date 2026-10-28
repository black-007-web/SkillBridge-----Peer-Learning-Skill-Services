# Testing

Run `flutter test` for the widget and unit tests, then `flutter analyze` for
static checks.

Before release, add integration coverage for Supabase registration, email
verification/deep links, sign-in/sign-out, published course visibility, and
row-level-security behavior for cross-user data access. Test release builds on
the supported Android/iOS devices and browsers, including offline and
intermittent-network behavior.