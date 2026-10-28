import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../providers/auth_provider.dart';
import '../widgets/auth_widgets.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.nextPath = '/'});

  final String nextPath;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _googleLoading = false;
  bool _showPassword = false;
  bool _needsRegistrationConfirmation = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading || _googleLoading || !_formKey.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    final auth = ref.read(authServiceProvider);
    if (auth == null) {
      setState(() => _error = 'Connect Supabase to sign in.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _needsRegistrationConfirmation = false;
    });
    try {
      await auth.login(email: _email.text, password: _password.text);
      if (mounted) context.go(_safeNextPath(widget.nextPath));
    } on AuthException catch (error) {
      if (!mounted) return;
      final unverified = error.message.toLowerCase().contains(
        'email not confirmed',
      );
      setState(() {
        _error = unverified
            ? 'Confirm the email address used during registration before signing in.'
            : _friendlyAuthError(error);
        _needsRegistrationConfirmation = unverified;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not sign in. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _google() async {
    final auth = ref.read(authServiceProvider);
    if (auth == null || _loading || _googleLoading) return;
    setState(() {
      _googleLoading = true;
      _error = null;
    });
    try {
      await auth.signInWithGoogle();
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = _friendlyAuthError(error));
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Google sign-in could not start. Check OAuth configuration.',
        );
      }
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _loading || _googleLoading;
    final auth = ref.watch(authServiceProvider);
    return AuthFrame(
      title: 'Welcome back',
      subtitle: 'Sign in and pick up where your learning left off.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            AuthError(
              message: _error!,
              action: _needsRegistrationConfirmation
                  ? TextButton(
                      onPressed: busy
                          ? null
                          : () => context.go(
                              '/check-email?email=${Uri.encodeQueryComponent(_email.text.trim())}',
                            ),
                      child: const Text('Confirm registration'),
                    )
                  : null,
            ),
            const SizedBox(height: 16),
          ],
          if (auth == null) ...[
            const AuthError(
              message: 'Supabase is not configured. Use the setup guide in backend/README.md.',
            ),
            const SizedBox(height: 16),
          ],
          AutofillGroup(
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _email,
                    enabled: !busy,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Email address',
                      prefixIcon: Icon(Icons.mail_outline_rounded),
                    ),
                    validator: (value) => _validEmail(value?.trim() ?? '')
                        ? null
                        : 'Enter a valid email address',
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _password,
                    enabled: !busy,
                    obscureText: !_showPassword,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    onFieldSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        tooltip: _showPassword
                            ? 'Hide password'
                            : 'Show password',
                        onPressed: () =>
                            setState(() => _showPassword = !_showPassword),
                        icon: Icon(
                          _showPassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                    ),
                    validator: (value) =>
                        (value ?? '').isNotEmpty ? null : 'Enter your password',
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: busy ? null : () => context.push('/forgot-password'),
              child: const Text('Forgot password?'),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: busy ? null : _submit,
              child: _loading
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Log in'),
            ),
          ),
          const SizedBox(height: 18),
          const Row(
            children: [
              Expanded(child: Divider()),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('or'),
              ),
              Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 18),
          GoogleSignInButton(
            onPressed: auth == null || busy ? null : _google,
            loading: _googleLoading,
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('New to SkillBridge?'),
              TextButton(
                onPressed: busy ? null : () => context.go('/register'),
                child: const Text('Create account'),
              ),
            ],
          ),
          TextButton(
            onPressed: () => context.go('/'),
            child: const Text('Continue in preview mode'),
          ),
        ],
      ),
    );
  }
}

bool _validEmail(String email) =>
    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);

String _friendlyAuthError(AuthException error) {
  final message = error.message.toLowerCase();
  if (message.contains('invalid login credentials')) {
    return 'Email or password is incorrect.';
  }
  if (message.contains('rate limit')) {
    return 'Too many attempts. Wait a little and try again.';
  }
  return error.message;
}

String _safeNextPath(String value) {
  const allowed = {
    '/',
    '/profile',
    '/profile/edit',
    '/notifications',
    '/settings',
    '/settings/change-password',
    '/settings/delete-account',
  };
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      !allowed.contains(uri.path)) {
    return '/';
  }
  return uri.toString();
}
