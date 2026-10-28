import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../providers/auth_provider.dart';
import '../../../core/supabase_config.dart';
import '../widgets/auth_widgets.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  static const _genders = {
    'male': 'Male',
    'female': 'Female',
    'non_binary': 'Non-binary',
    'prefer_not_to_say': 'Prefer not to say',
  };

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _studentNumber = TextEditingController();
  final _department = TextEditingController();
  final _program = TextEditingController();
  final _phone = TextEditingController();
  final _dob = TextEditingController();
  final _nationality = TextEditingController();
  final _address = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  DateTime? _dateOfBirth;
  String? _gender;
  Uint8List? _avatarBytes;
  String? _avatarMime;
  String? _avatarName;
  bool _terms = false;
  bool _loading = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _studentNumber.dispose();
    _department.dispose();
    _program.dispose();
    _phone.dispose();
    _dob.dispose();
    _nationality.dispose();
    _address.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final latestEligible = DateTime(now.year - 13, now.month, now.day);
    final selected = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 20, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: latestEligible,
      helpText: 'Date of birth (13 or older)',
    );
    if (selected == null) return;
    setState(() {
      _dateOfBirth = selected;
      _dob.text = _formatDate(selected);
    });
    _formKey.currentState?.validate();
  }

  Future<void> _pickAvatar() async {
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (image == null) return;
      final storage = ref.read(storageServiceProvider);
      final mime = storage?.mimeForFileName(image.name);
      if (mime == null) {
        setState(() => _error = 'Choose a JPG, PNG, or WebP image.');
        return;
      }
      final bytes = await image.readAsBytes();
      if (bytes.isEmpty || bytes.length > 2 * 1024 * 1024) {
        setState(() => _error = 'Choose an image smaller than 2 MB.');
        return;
      }
      setState(() {
        _avatarBytes = bytes;
        _avatarMime = mime;
        _avatarName = image.name;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not open the photo picker.');
    }
  }

  Future<void> _submit() async {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    final valid = _formKey.currentState!.validate();
    if (!valid) return;
    if (!_terms) {
      setState(
        () => _error =
            'Accept the Terms of Service and Privacy Policy to continue.',
      );
      return;
    }
    final auth = ref.read(authServiceProvider);
    if (auth == null) {
      setState(() => _error = 'Connect Supabase before creating an account.');
      return;
    }
    final avatarBytes = _avatarBytes;
    final avatarMime = _avatarMime;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await auth.register(
        email: _email.text,
        password: _password.text,
        profile: {
          'full_name': _name.text.trim(),
          'student_number': _studentNumber.text.trim(),
          'department': _department.text.trim(),
          'program': _program.text.trim(),
          'phone_number': _phone.text.trim(),
          'date_of_birth': _formatDate(_dateOfBirth!),
          'gender': _gender,
          'nationality': _nationality.text.trim(),
          'address': _address.text.trim(),
          'terms_accepted_at': DateTime.now().toUtc().toIso8601String(),
        },
      );

      if (response.session != null && response.user != null) {
        if (avatarBytes != null && avatarMime != null) {
          try {
            final path = await ref
                .read(storageServiceProvider)!
                .uploadAvatar(
                  userId: response.user!.id,
                  bytes: avatarBytes,
                  mimeType: avatarMime,
                );
            await ref.read(profileServiceProvider)!.updateAvatarPath(path);
          } catch (_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Account created. You can add your photo from your profile.',
                  ),
                ),
              );
            }
          }
        }
        if (mounted) context.go('/');
      } else {
        if (mounted) {
          context.go(
            '/check-email?email=${Uri.encodeQueryComponent(_email.text.trim())}',
          );
        }
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = _friendlyRegisterError(error));
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not create your account. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _validateInstitutionEmail(String? value) {
    final email = value?.trim() ?? '';
    if (!_validEmail(email)) return 'Enter a valid email address';
    const config = SupabaseConfig.fromEnvironment();
    final domain = config.eduEmailDomain.trim().toLowerCase();
    if (domain.isEmpty) {
      return 'Student email domain is not configured for this build.';
    }
    if (!config.isAllowedEduEmail(email)) {
      return 'Use your university email address ending in @$domain';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final busy = _loading;
    return AuthFrame(
      title: 'Create your account',
      subtitle: 'Build new skills with your university community.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            AuthError(message: _error!),
            const SizedBox(height: 14),
          ],
          Center(
            child: Column(
              children: [
                Semantics(
                  button: true,
                  label: _avatarBytes == null
                      ? 'Add profile photo'
                      : 'Change profile photo',
                  child: InkWell(
                    onTap: busy ? null : _pickAvatar,
                    customBorder: const CircleBorder(),
                    child: CircleAvatar(
                      radius: 48,
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .primaryContainer,
                      backgroundImage: _avatarBytes == null
                          ? null
                          : MemoryImage(_avatarBytes!),
                      child: _avatarBytes == null
                          ? const Icon(Icons.add_a_photo_outlined, size: 30)
                          : null,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: busy ? null : _pickAvatar,
                  child: Text(
                    _avatarBytes == null
                        ? 'Add profile photo (optional)'
                        : 'Change photo',
                  ),
                ),
                if (_avatarName != null)
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() {
                            _avatarBytes = null;
                            _avatarMime = null;
                            _avatarName = null;
                          }),
                    child: const Text('Remove photo'),
                  ),
              ],
            ),
          ),
          AutofillGroup(
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _name,
                    enabled: !busy,
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.name],
                    decoration: const InputDecoration(
                      labelText: 'Full name',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                    validator: (value) => (value?.trim().length ?? 0) >= 2
                        ? null
                        : 'Enter your full name',
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _email,
                    enabled: !busy,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Email address',
                      prefixIcon: Icon(Icons.mail_outline_rounded),
                    ),
                    validator: _validateInstitutionEmail,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _studentNumber,
                    enabled: !busy,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Student number',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                    validator: (value) => (value?.trim().length ?? 0) >= 2 &&
                            (value?.trim().length ?? 0) <= 40
                        ? null
                        : 'Enter a valid student number',
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _department,
                    enabled: !busy,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Department',
                      prefixIcon: Icon(Icons.account_balance_outlined),
                    ),
                    validator: (value) => (value?.trim().length ?? 0) >= 2
                        ? null
                        : 'Enter your department',
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _program,
                    enabled: !busy,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Program',
                      prefixIcon: Icon(Icons.school_outlined),
                    ),
                    validator: (value) => (value?.trim().length ?? 0) >= 2
                        ? null
                        : 'Enter your program',
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _phone,
                    enabled: !busy,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    decoration: const InputDecoration(
                      labelText: 'Phone number',
                      hintText: '+8801XXXXXXXXX',
                      helperText: 'Include country code, e.g. +880 or +1',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                    validator: (value) => _validPhone(value?.trim() ?? '')
                        ? null
                        : 'Enter a valid number with country code',
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _dob,
                    enabled: !busy,
                    readOnly: true,
                    onTap: busy ? null : _pickDate,
                    decoration: const InputDecoration(
                      labelText: 'Date of birth',
                      prefixIcon: Icon(Icons.cake_outlined),
                      suffixIcon: Icon(Icons.calendar_month_outlined),
                    ),
                    validator: (_) => _dateOfBirth == null
                        ? 'Choose your date of birth (13 or older)'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _gender,
                    decoration: const InputDecoration(
                      labelText: 'Gender (optional)',
                      prefixIcon: Icon(Icons.wc_outlined),
                    ),
                    items: [
                      for (final item in _genders.entries)
                        DropdownMenuItem(
                          value: item.key,
                          child: Text(item.value),
                        ),
                    ],
                    onChanged: busy
                        ? null
                        : (value) => setState(() => _gender = value),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _nationality,
                    enabled: !busy,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nationality (optional)',
                      prefixIcon: Icon(Icons.flag_outlined),
                    ),
                    validator: (value) => (value?.length ?? 0) <= 80
                        ? null
                        : 'Use 80 characters or fewer',
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _address,
                    enabled: !busy,
                    maxLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Address (optional)',
                      prefixIcon: Icon(Icons.home_outlined),
                    ),
                    validator: (value) => (value?.length ?? 0) <= 300
                        ? null
                        : 'Use 300 characters or fewer',
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _password,
                    enabled: !busy,
                    obscureText: !_showPassword,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        onPressed: () =>
                            setState(() => _showPassword = !_showPassword),
                        icon: Icon(
                          _showPassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                    ),
                    validator: (value) => (value?.length ?? 0) >= 8
                        ? null
                        : 'Use at least 8 characters',
                  ),
                  const SizedBox(height: 8),
                  _PasswordStrength(password: _password),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _confirm,
                    enabled: !busy,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.newPassword],
                    onFieldSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(
                      labelText: 'Confirm password',
                      prefixIcon: Icon(Icons.lock_reset_outlined),
                    ),
                    validator: (value) => value == _password.text
                        ? null
                        : 'Passwords do not match',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: _terms,
            onChanged: busy
                ? null
                : (value) => setState(() => _terms = value ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'I agree to the Terms of Service and Privacy Policy.',
            ),
          ),
          const LegalLinks(),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: busy ? null : _submit,
              child: busy
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create account'),
            ),
          ),
          const SizedBox(height: 8),
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
          const SizedBox(height: 12),
          GoogleSignInButton(
            loading: busy,
            onPressed: busy
                ? null
                : () async {
                    try {
                      await ref.read(authServiceProvider)?.signInWithGoogle();
                    } catch (_) {
                      if (mounted) {
                        setState(
                          () => _error = 'Google sign-up could not start. Check OAuth configuration.',
                        );
                      }
                    }
                  },
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: busy ? null : () => context.go('/login'),
            child: const Text('Already have an account? Log in'),
          ),
        ],
      ),
    );
  }
}

bool _validEmail(String email) =>
    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);

bool _validPhone(String phone) => RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(phone);

String _formatDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

String _friendlyRegisterError(AuthException error) {
  final message = error.message.toLowerCase();
  if (message.contains('already registered')) {
    return 'This email may already be registered. Try logging in or resetting your password.';
  }
  if (message.contains('rate limit')) {
    return 'Too many registration attempts. Wait a little and try again.';
  }
  return error.message;
}

class _PasswordStrength extends StatelessWidget {
  const _PasswordStrength({required this.password});
  final TextEditingController password;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: password,
        builder: (context, value, _) {
          final text = value.text;
          if (text.isEmpty) return const SizedBox.shrink();
          var score = 0;
          if (text.length >= 8) score++;
          if (RegExp(r'[A-Z]').hasMatch(text) &&
              RegExp(r'[a-z]').hasMatch(text)) {
            score++;
          }
          if (RegExp(r'\d').hasMatch(text)) score++;
          if (RegExp(r'[^A-Za-z0-9]').hasMatch(text)) score++;
          const labels = ['Weak', 'Fair', 'Good', 'Strong', 'Very strong'];
          final color = score <= 1
              ? Colors.redAccent
              : score == 2
              ? Colors.orangeAccent
              : score == 3
              ? Colors.lightBlueAccent
              : Colors.greenAccent;
          return Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: score / 4,
                  color: color,
                  backgroundColor: color.withValues(alpha: 0.16),
                ),
              ),
              const SizedBox(width: 10),
              Text(labels[score], style: TextStyle(color: color, fontSize: 12)),
            ],
          );
        },
      );
}
