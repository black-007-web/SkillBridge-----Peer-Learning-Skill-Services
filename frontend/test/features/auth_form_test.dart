import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skillbridge_mobile/features/auth/screens/email_verification_screen.dart';
import 'package:skillbridge_mobile/features/auth/screens/login_screen.dart';
import 'package:skillbridge_mobile/features/auth/screens/register_screen.dart';

void main() {
  Widget app(Widget child) => ProviderScope(
    child: MaterialApp(theme: ThemeData.dark(useMaterial3: true), home: child),
  );

  testWidgets('registration validates required identity and password fields', (
    tester,
  ) async {
    await tester.pumpWidget(app(const RegisterScreen()));
    await tester.ensureVisible(find.text('Create account').last);
    await tester.tap(find.text('Create account').last);
    await tester.pumpAndSettle();

    expect(find.text('Enter your full name'), findsOneWidget);
    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.text('Enter a valid number with country code'), findsOneWidget);
    expect(
      find.text('Choose your date of birth (13 or older)'),
      findsOneWidget,
    );
    expect(find.text('Use at least 8 characters'), findsOneWidget);
  });

  testWidgets('registration rejects a mismatched password confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(app(const RegisterScreen()));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Full name'),
      'Amina Rahman',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email address'),
      'amina@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'StrongPass123!',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm password'),
      'DifferentPass123!',
    );
    await tester.ensureVisible(find.text('Create account').last);
    await tester.tap(find.text('Create account').last);
    await tester.pumpAndSettle();

    expect(find.text('Passwords do not match'), findsOneWidget);
  });

  testWidgets('login requires a password before contacting Supabase', (
    tester,
  ) async {
    await tester.pumpWidget(app(const LoginScreen()));
    await tester.enterText(
      find.byType(TextFormField).first,
      'amina@example.com',
    );
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();

    expect(find.text('Enter your password'), findsOneWidget);
  });

  testWidgets('email verification asks for the emailed OTP', (tester) async {
    await tester.pumpWidget(
      app(const EmailVerificationScreen(email: 'amina@example.com')),
    );

    expect(find.text('Verify your email'), findsOneWidget);
    expect(find.text('Email verification code'), findsOneWidget);
    expect(find.text('Resend code'), findsOneWidget);
  });
}
