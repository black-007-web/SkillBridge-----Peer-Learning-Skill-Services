import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../providers/auth_provider.dart';
import '../../auth/widgets/auth_widgets.dart';

class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _password = TextEditingController();
  bool _confirmed = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  bool get _usesEmail =>
      ref.read(authServiceProvider)?.currentUser?.appMetadata['provider'] ==
      'email';

  Future<void> _reauthenticateGoogle() async {
    try {
      await ref.read(authServiceProvider)?.signInWithGoogle();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Google reauthentication could not start. Check OAuth configuration.',
        );
      }
    }
  }

  Future<void> _delete() async {
    if (_loading || !_confirmed || (_usesEmail && _password.text.isEmpty)) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(authServiceProvider)
          ?.deleteAccount(currentPassword: _usesEmail ? _password.text : null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your account and profile data have been deleted.'),
          ),
        );
        context.go('/welcome');
      }
    } on FunctionException catch (error) {
      if (mounted) {
        setState(
          () => _error =
              error.details?.toString() ??
              'Could not delete the account. Reauthenticate and try again.',
        );
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not delete the account. Reauthenticate and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEmail = _usesEmail;
    return Scaffold(
      appBar: AppBar(title: const Text('Delete account')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 54,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'This action cannot be undone',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Your profile, avatar, notification preferences, and enrollments will be removed. Some security records may remain in provider backups according to their retention rules.',
                  textAlign: TextAlign.center,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 18),
                  AuthError(message: _error!),
                ],
                const SizedBox(height: 18),
                if (isEmail)
                  TextField(
                    controller: _password,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(
                      labelText: 'Confirm your password',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _reauthenticateGoogle,
                    icon: const Icon(Icons.g_mobiledata_rounded),
                    label: const Text('Reauthenticate with Google'),
                  ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: _confirmed,
                  onChanged: _loading
                      ? null
                      : (value) => setState(() => _confirmed = value ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'I understand this will permanently delete my account.',
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                      foregroundColor: Theme.of(context).colorScheme.onError,
                    ),
                    onPressed: _loading ? null : _delete,
                    child: _loading
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Delete my account'),
                  ),
                ),
                TextButton(
                  onPressed: _loading ? null : () => context.pop(),
                  child: const Text('Keep my account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
