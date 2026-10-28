import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/screens/email_verification_screen.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/auth/screens/reset_password_screen.dart';
import '../../features/auth/screens/welcome_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/home/explore_catalog_widgets.dart';
import '../../features/profile/screens/account_settings_screen.dart';
import '../../features/profile/screens/change_password_screen.dart';
import '../../features/profile/screens/delete_account_screen.dart';
import '../../features/profile/screens/edit_profile_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/notifications/screens/notifications_screen.dart';
import '../../features/admin/screens/admin_dashboard.dart';
import '../../features/lecturer/screens/lecturer_dashboard.dart';
import '../../features/lecturer/screens/course_editor_screen.dart';
import '../../features/lecturer/screens/lecturer_application_screen.dart';
import '../../features/lecturer/screens/course_content_screen.dart';
import '../../features/lecturer/screens/course_reviews_screen.dart';
import '../../features/lecturer/screens/course_insights_screen.dart';
import '../../features/profile/screens/student_verification_screen.dart';
import '../../features/support/support_tickets_screen.dart';
import '../../features/courses/screens/course_details_screen.dart';
import '../../features/announcements/screens/announcements_screen.dart';

class AppRouter {
  AppRouter({required this.supabaseConfigured})
    : _authRefresh = supabaseConfigured
          ? _AuthRefresh(Supabase.instance.client.auth.onAuthStateChange)
          : null {
    router = GoRouter(
      initialLocation: '/',
      refreshListenable: _authRefresh,
      redirect: _redirect,
      routes: [
        GoRoute(
          path: '/',
          builder: (_, state) => AppShell(
            supabaseConfigured: supabaseConfigured,
            initialTab: switch (state.uri.queryParameters['tab']) {
              'explore' => 1,
              'lecturers' => 4,
              _ => 0,
            },
          ),
        ),
        GoRoute(
          path: '/lecturers',
          builder: (_, _) =>
              AppShell(supabaseConfigured: supabaseConfigured, initialTab: 4),
        ),
        GoRoute(
          path: '/lecturers/:lecturerId/courses',
          builder: (_, state) => LecturerCoursesPage(
            lecturerId: state.pathParameters['lecturerId']!,
            supabaseConfigured: supabaseConfigured,
          ),
        ),
        GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
        GoRoute(
          path: '/login',
          builder: (_, state) =>
              LoginScreen(nextPath: state.uri.queryParameters['next'] ?? '/'),
        ),
        GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
        GoRoute(
          path: '/check-email',
          builder: (_, state) => EmailVerificationScreen(
            email: state.uri.queryParameters['email'],
          ),
        ),
        GoRoute(
          path: '/verify-email',
          builder: (_, state) => EmailVerificationScreen(
            email: state.uri.queryParameters['email'],
          ),
        ),
        GoRoute(
          path: '/auth-callback',
          builder: (_, _) => const _AuthCallbackScreen(),
        ),
        GoRoute(
          path: '/forgot-password',
          builder: (_, _) => const ForgotPasswordScreen(),
        ),
        GoRoute(
          path: '/reset-password',
          builder: (_, _) => const ResetPasswordScreen(),
        ),
        GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
        GoRoute(
          path: '/notifications',
          builder: (_, _) => const NotificationsScreen(),
        ),
        GoRoute(
          path: '/announcements',
          builder: (_, _) => const AnnouncementsScreen(),
        ),
        GoRoute(
          path: '/workspace-unavailable',
          builder: (_, state) => _WorkspaceUnavailableScreen(
            retryPath: state.uri.queryParameters['retry'] == '/admin'
                ? '/admin'
                : '/lecturer',
            details: state.uri.queryParameters['details'],
          ),
        ),
        GoRoute(
          path: '/workspace-access-denied',
          builder: (_, state) => _WorkspaceAccessDeniedScreen(
            requiredRole: state.uri.queryParameters['requiredRole'] ?? 'active',
          ),
        ),
        GoRoute(
          path: '/courses/:id',
          builder: (_, state) =>
              CourseDetailsScreen(courseId: state.pathParameters['id']!),
        ),
        GoRoute(path: '/admin', builder: (_, _) => const AdminDashboard()),
        GoRoute(
          path: '/lecturer',
          builder: (_, _) => const LecturerDashboard(),
        ),
        GoRoute(
          path: '/lecturer/apply',
          builder: (_, _) => const LecturerApplicationScreen(),
        ),
        GoRoute(
          path: '/student/verification',
          builder: (_, _) => const StudentVerificationScreen(),
        ),
        GoRoute(
          path: '/support',
          builder: (_, _) => const SupportTicketsScreen(),
        ),
        GoRoute(
          path: '/lecturer/courses/new',
          builder: (_, _) => const CourseEditorScreen(),
        ),
        GoRoute(
          path: '/lecturer/courses/:id/edit',
          builder: (_, state) =>
              CourseEditorScreen(courseId: state.pathParameters['id']),
        ),
        GoRoute(
          path: '/lecturer/courses/:id/content',
          builder: (_, state) =>
              CourseContentScreen(courseId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/lecturer/courses/:id/reviews',
          builder: (_, state) =>
              CourseReviewsScreen(courseId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/lecturer/courses/:id/insights',
          builder: (_, state) =>
              CourseInsightsScreen(courseId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/profile/edit',
          builder: (_, _) => const EditProfileScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, _) => const AccountSettingsScreen(),
        ),
        GoRoute(
          path: '/settings/change-password',
          builder: (_, _) => const ChangePasswordScreen(),
        ),
        GoRoute(
          path: '/settings/delete-account',
          builder: (_, _) => const DeleteAccountScreen(),
        ),
      ],
      errorBuilder: (context, state) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.route_outlined, size: 44),
                const SizedBox(height: 12),
                Text(
                  'This page could not be opened.',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => context.go('/'),
                  child: const Text('Go home'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  final bool supabaseConfigured;
  final _AuthRefresh? _authRefresh;
  late final GoRouter router;

  Future<String?> _redirect(BuildContext context, GoRouterState state) async {
    final path = state.uri.path;
    if (!supabaseConfigured) {
      if ({
        '/profile',
        '/profile/edit',
        '/settings',
        '/settings/change-password',
        '/settings/delete-account',
      }.contains(path)) {
        return '/login';
      }
      return null;
    }

    final auth = Supabase.instance.client.auth;
    final user = auth.currentUser;
    final emailVerified =
        user != null &&
        (user.emailConfirmedAt != null ||
            user.appMetadata['provider'] != 'email');
    final isRecovery = _authRefresh?.recoveryInProgress ?? false;
    final publicRoutes = {
      '/',
      '/welcome',
      '/lecturers',
      '/login',
      '/register',
      '/check-email',
      '/verify-email',
      '/forgot-password',
      '/auth-callback',
    };

    if (isRecovery && user != null && path != '/reset-password') {
      return '/reset-password';
    }
    if (path == '/reset-password') {
      return user == null ? '/forgot-password' : null;
    }
    if ((path == '/login' || path == '/register' || path == '/welcome') &&
        emailVerified) {
      return '/';
    }
    if (path == '/auth-callback') {
      if (user == null) return '/login';
      if (!emailVerified) {
        return '/check-email?email=${Uri.encodeQueryComponent(user.email ?? '')}';
      }
      return '/';
    }
    final isPublicLecturerRoute =
        path == '/lecturers' || path.startsWith('/lecturers/');
    if (!publicRoutes.contains(path) && !isPublicLecturerRoute) {
      if (user == null) {
        return '/login?next=${Uri.encodeQueryComponent(state.uri.toString())}';
      }
      if (!emailVerified) {
        return '/check-email?email=${Uri.encodeQueryComponent(user.email ?? '')}';
      }
    }
    final isLecturerWorkspace =
        path == '/lecturer' || path.startsWith('/lecturer/');
    if (user != null &&
        (path == '/admin' ||
            (isLecturerWorkspace && path != '/lecturer/apply'))) {
      try {
        final profile = await Supabase.instance.client
            .from('profiles')
            .select('account_status')
            .eq('id', user.id)
            .maybeSingle();
        if (profile == null || profile['account_status'] != 'active') {
          return Uri(
            path: '/workspace-access-denied',
            queryParameters: {'requiredRole': 'active'},
          ).toString();
        }
        final rows = await Supabase.instance.client
            .from('user_roles')
            .select('role')
            .eq('user_id', user.id);
        final roles = rows.map((row) => row['role'] as String).toSet();
        if (path == '/admin' && !roles.contains('admin')) {
          return Uri(
            path: '/workspace-access-denied',
            queryParameters: {'requiredRole': 'admin'},
          ).toString();
        }
        if (isLecturerWorkspace &&
            path != '/lecturer/apply' &&
            !roles.contains('lecturer') &&
            !roles.contains('admin')) {
          return Uri(
            path: '/workspace-access-denied',
            queryParameters: {'requiredRole': 'lecturer'},
          ).toString();
        }
      } catch (error) {
        final retryPath = path == '/admin' ? '/admin' : '/lecturer';
        return Uri(
          path: '/workspace-unavailable',
          queryParameters: {'retry': retryPath, 'details': error.toString()},
        ).toString();
      }
    }
    if (path == '/check-email' && emailVerified) {
      return '/';
    }
    return null;
  }

  void dispose() {
    router.dispose();
    _authRefresh?.dispose();
  }
}

class _WorkspaceUnavailableScreen extends StatelessWidget {
  const _WorkspaceUnavailableScreen({required this.retryPath, this.details});

  final String retryPath;
  final String? details;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Workspace unavailable')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 44),
            const SizedBox(height: 12),
            const Text(
              'We could not verify your workspace access. Check your connection and try again.',
              textAlign: TextAlign.center,
            ),
            if (details != null && details!.isNotEmpty) ...[
              const SizedBox(height: 12),
              SelectableText(
                'Technical details: $details',
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.go(retryPath),
              child: const Text('Try again'),
            ),
            TextButton(
              onPressed: () => context.go('/'),
              child: const Text('Go to home'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _WorkspaceAccessDeniedScreen extends StatelessWidget {
  const _WorkspaceAccessDeniedScreen({required this.requiredRole});

  final String requiredRole;

  @override
  Widget build(BuildContext context) {
    final message = requiredRole == 'active'
        ? 'This account is inactive. Contact an administrator for help.'
        : 'This account does not have the $requiredRole role. If you expect this workspace, ask an administrator to check your role assignment.';
    return Scaffold(
      appBar: AppBar(title: const Text('Workspace access')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 44),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go('/profile'),
                child: const Text('View profile and roles'),
              ),
              TextButton(
                onPressed: () => context.go('/'),
                child: const Text('Go to home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Stream<AuthState> stream) {
    _subscription = stream.listen((state) {
      if (state.event == AuthChangeEvent.passwordRecovery) {
        recoveryInProgress = true;
      } else if (state.event == AuthChangeEvent.signedOut ||
          state.event == AuthChangeEvent.userUpdated) {
        recoveryInProgress = false;
      }
      notifyListeners();
    });
  }

  late final StreamSubscription<AuthState> _subscription;
  bool recoveryInProgress = false;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

class _AuthCallbackScreen extends StatelessWidget {
  const _AuthCallbackScreen();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
