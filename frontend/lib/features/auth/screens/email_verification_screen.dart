import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../providers/auth_provider.dart';
import '../widgets/auth_widgets.dart';

class EmailVerificationScreen extends ConsumerStatefulWidget {
  const EmailVerificationScreen({super.key, this.email});
  final String? email;

  @override
  ConsumerState<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState
    extends ConsumerState<EmailVerificationScreen> {
  Timer? _timer;
  final _code = TextEditingController();
  int _secondsRemaining = 0;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  String? get _email =>
      widget.email ?? ref.read(authServiceProvider)?.currentUser?.email;

  Future<void> _resend() async {
    final email = _email;
    final auth = ref.read(authServiceProvider);
    if (_loading || _secondsRemaining > 0 || email == null || auth == null) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await auth.resendVerification(email);
      setState(() => _secondsRemaining = 60);
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return timer.cancel();
        if (_secondsRemaining <= 1) {
          timer.cancel();
          setState(() => _secondsRemaining = 0);
        } else {
          setState(() => _secondsRemaining--);
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verification email sent.')),
        );
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not resend the email. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verify() async {
    final auth = ref.read(authServiceProvider);
    final email = _email;
    if (auth == null || email == null) return;
    if (_code.text.trim().length < 4) {
      setState(() => _error = 'Enter the code from your email.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await auth.verifyEmailOtp(
        email: email,
        token: _code.text,
      );
      if (mounted) context.go(response.session == null ? '/login' : '/');
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not verify the code. Check it and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AuthFrame(
    title: 'Verify your email',
    subtitle: _email == null
        ? 'Enter the one-time code we sent to your inbox.'
        : 'Enter the one-time code we sent to $_email.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer
                .withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            children: [
              Icon(
                Icons.mark_email_read_outlined,
                size: 42,
                color: Theme.of(context).colorScheme.secondary,
              ),
              const SizedBox(height: 12),
              const Text(
                'Use the one-time code in your email to activate your account.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          AuthError(message: _error!),
        ],
        const SizedBox(height: 18),
        TextField(
          controller: _code,
          enabled: !_loading,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          autofillHints: const [AutofillHints.oneTimeCode],
          decoration: const InputDecoration(
            labelText: 'Email verification code',
            prefixIcon: Icon(Icons.password_rounded),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: _loading || _email == null ? null : _verify,
            child: _loading
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Verify email'),
          ),
        ),
        OutlinedButton(
          onPressed: _loading || _secondsRemaining > 0 ? null : _resend,
          child: Text(
            _secondsRemaining > 0
                ? 'Resend in ${_secondsRemaining}s'
                : 'Resend code',
          ),
        ),
        TextButton(
          onPressed: _loading ? null : () => context.go('/login'),
          child: const Text('Return to log in'),
        ),
      ],
    ),
  );
}
