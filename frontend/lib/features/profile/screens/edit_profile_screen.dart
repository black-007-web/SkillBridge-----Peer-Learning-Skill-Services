import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../providers/auth_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../services/storage_service.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _nationality = TextEditingController();
  final _address = TextEditingController();
  final _bio = TextEditingController();
  final _github = TextEditingController();
  final _linkedin = TextEditingController();
  final _website = TextEditingController();
  final _otherSocial = TextEditingController();
  final _position = TextEditingController();
  final _skills = TextEditingController();
  final _dobText = TextEditingController();
  DateTime? _dob;
  String? _gender;
  String? _avatarPath;
  Uint8List? _avatarBytes;
  String? _avatarMime;
  String? _coverPath;
  Uint8List? _coverBytes;
  String? _coverMime;
  bool _removeAvatar = false;
  bool _removeCover = false;
  bool _initialized = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _nationality.dispose();
    _address.dispose();
    _bio.dispose();
    _github.dispose();
    _linkedin.dispose();
    _website.dispose();
    _otherSocial.dispose();
    _position.dispose();
    _skills.dispose();
    _dobText.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(today.year - 20, today.month, today.day),
      firstDate: DateTime(1900),
      lastDate: today,
    );
    if (selected == null) return;
    setState(() {
      _dob = selected;
      _dobText.text = _date(selected);
    });
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
      if (bytes.isEmpty || bytes.length > StorageService.maxAvatarBytes) {
        setState(() => _error = 'Choose an image smaller than 2 MB.');
        return;
      }
      setState(() {
        _avatarBytes = bytes;
        _avatarMime = mime;
        _removeAvatar = false;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not open the photo picker.');
    }
  }

  Future<void> _pickCover() async {
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 900,
        imageQuality: 85,
      );
      if (image == null) return;
      final storage = ref.read(storageServiceProvider);
      final mime = storage?.mimeForFileName(image.name);
      if (mime == null) {
        setState(() => _error = 'Choose a JPG, PNG, or WebP cover image.');
        return;
      }
      final bytes = await image.readAsBytes();
      if (bytes.isEmpty || bytes.length > StorageService.maxAvatarBytes) {
        setState(() => _error = 'Choose a cover image smaller than 2 MB.');
        return;
      }
      setState(() {
        _coverBytes = bytes;
        _coverMime = mime;
        _removeCover = false;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not open the cover picker.');
    }
  }

  Future<void> _save() async {
    if (_loading || !_formKey.currentState!.validate()) return;
    final profileService = ref.read(profileServiceProvider);
    final storage = ref.read(storageServiceProvider);
    final user = ref.read(authServiceProvider)?.currentUser;
    if (profileService == null || storage == null || user == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    String? uploadedPath;
    String? uploadedCoverPath;
    var profileSaved = false;
    try {
      String? nextAvatar = _avatarPath;
      if (_avatarBytes != null && _avatarMime != null) {
        nextAvatar = await storage.uploadAvatar(
          userId: user.id,
          bytes: _avatarBytes!,
          mimeType: _avatarMime!,
        );
        uploadedPath = nextAvatar;
      } else if (_removeAvatar) {
        nextAvatar = null;
      }

      String? nextCover = _coverPath;
      if (_coverBytes != null && _coverMime != null) {
        nextCover = await storage.uploadProfileCover(
          userId: user.id,
          bytes: _coverBytes!,
          mimeType: _coverMime!,
        );
        uploadedCoverPath = nextCover;
      } else if (_removeCover) {
        nextCover = null;
      }

      final metadataFallback = await profileService.updateProfile(
        fullName: _name.text,
        phoneNumber: _phone.text,
        dateOfBirth: _dob,
        gender: _gender,
        nationality: _nationality.text,
        address: _address.text,
        bio: _bio.text,
        socialLinks: {
          if (_github.text.trim().isNotEmpty) 'github': _github.text.trim(),
          if (_linkedin.text.trim().isNotEmpty)
            'linkedin': _linkedin.text.trim(),
          if (_website.text.trim().isNotEmpty) 'website': _website.text.trim(),
          if (_otherSocial.text.trim().isNotEmpty)
            'other': _otherSocial.text.trim(),
        },
        position: _position.text,
        skills: _skills.text
            .split(RegExp(r'[,;\n]'))
            .map((skill) => skill.trim())
            .where((skill) => skill.isNotEmpty)
            .toSet()
            .toList(growable: false),
        coverImagePath: nextCover,
      );
      profileSaved = true;
      if (nextAvatar != _avatarPath) {
        await profileService.updateAvatarPath(nextAvatar);
      }
      if (nextAvatar != _avatarPath && _avatarPath != null) {
        try {
          await storage.removeAvatar(_avatarPath!);
        } catch (_) {
          // An old object left by a failed cleanup remains private and owner-only.
        }
      }
      if (nextCover != _coverPath && _coverPath != null) {
        try {
          await storage.removeAvatar(_coverPath!);
        } catch (_) {
          // A stale cover image remains private and owner-only.
        }
      }
      ref.invalidate(currentProfileProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              metadataFallback
                  ? 'Profile updated. Apply the pending Supabase migrations to sync all fields to profiles.'
                  : 'Profile updated.',
            ),
          ),
        );
        context.pop();
      }
    } catch (error) {
      if (uploadedPath != null) {
        try {
          await storage.removeAvatar(uploadedPath);
        } catch (_) {}
      }
      if (!profileSaved && uploadedCoverPath != null) {
        try {
          await storage.removeAvatar(uploadedCoverPath);
        } catch (_) {}
      }
      if (mounted) {
        setState(() => _error = _saveErrorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentProfileProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('Could not load your profile.')),
        data: (value) {
          if (value == null) {
            return const Center(child: Text('Sign in to edit your profile.'));
          }
          if (!_initialized) {
            _name.text = value.fullName;
            _phone.text = value.phoneNumber ?? '';
            _nationality.text = value.nationality ?? '';
            _address.text = value.address ?? '';
            _bio.text = value.bio;
            _github.text = value.socialLinks['github'] ?? '';
            _linkedin.text = value.socialLinks['linkedin'] ?? '';
            _website.text = value.socialLinks['website'] ?? '';
            _otherSocial.text = value.socialLinks['other'] ?? '';
            _position.text = value.position;
            _skills.text = value.skills.join(', ');
            _dob = value.dateOfBirth;
            _dobText.text = _dob == null ? '' : _date(_dob!);
            _gender = value.gender;
            _avatarPath = value.avatarPath;
            _coverPath = value.coverImagePath;
            _initialized = true;
          }
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 30),
              children: [
                SizedBox(
                  height: 214,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _EditCoverPreview(
                        path: _coverPath,
                        bytes: _coverBytes,
                        storage: ref.watch(storageServiceProvider),
                        onTap: _loading ? null : _pickCover,
                      ),
                      Align(
                        alignment: const Alignment(0, -0.02),
                        child: _EditAvatar(
                          path: _avatarPath,
                          bytes: _avatarBytes,
                          onTap: _loading ? null : () => _pickAvatar(),
                        ),
                      ),
                      Positioned(
                        left: 10,
                        bottom: 10,
                        child: OutlinedButton.icon(
                          onPressed: _loading ? null : _pickCover,
                          icon: const Icon(Icons.wallpaper_outlined, size: 18),
                          label: const Text('Choose cover'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: Colors.black45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Center(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    children: [
                      TextButton(
                        onPressed: _loading ? null : _pickAvatar,
                        child: const Text('Choose profile photo'),
                      ),
                      if (_avatarPath != null || _avatarBytes != null)
                        TextButton(
                          onPressed: _loading
                              ? null
                              : () => setState(() {
                                  _avatarBytes = null;
                                  _avatarMime = null;
                                  _removeAvatar = true;
                                }),
                          child: const Text('Remove photo'),
                        ),
                      if (_coverPath != null || _coverBytes != null)
                        TextButton(
                          onPressed: _loading
                              ? null
                              : () => setState(() {
                                  _coverBytes = null;
                                  _coverMime = null;
                                  _removeCover = true;
                                }),
                          child: const Text('Remove cover'),
                        ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(_error!),
                  ),
                  const SizedBox(height: 14),
                ],
                TextFormField(
                  controller: _name,
                  enabled: !_loading,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Full name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (value) => (value?.trim().length ?? 0) >= 2
                      ? null
                      : 'Enter your full name',
                ),
                const SizedBox(height: 14),
                TextFormField(
                  initialValue:
                      ref.read(authServiceProvider)?.currentUser?.email ?? '',
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Email address',
                    prefixIcon: Icon(Icons.mail_outline),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phone,
                  enabled: !_loading,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone number',
                    hintText: '+12345678900',
                    prefixIcon: Icon(Icons.phone_outlined),
                    helperText: 'Profile contact number. Updating it does not change sign-in verification.',
                  ),
                  validator: (value) {
                    final phone = value?.trim() ?? '';
                    return phone.isEmpty ||
                            RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(phone)
                        ? null
                        : 'Use a number with country code, such as +12345678900.';
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _dobText,
                  readOnly: true,
                  enabled: !_loading,
                  onTap: _pickDate,
                  decoration: const InputDecoration(
                    labelText: 'Date of birth',
                    prefixIcon: Icon(Icons.cake_outlined),
                    suffixIcon: Icon(Icons.calendar_month_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _gender,
                  decoration: const InputDecoration(
                    labelText: 'Gender',
                    prefixIcon: Icon(Icons.wc_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'male', child: Text('Male')),
                    DropdownMenuItem(value: 'female', child: Text('Female')),
                    DropdownMenuItem(
                      value: 'non_binary',
                      child: Text('Non-binary'),
                    ),
                    DropdownMenuItem(
                      value: 'prefer_not_to_say',
                      child: Text('Prefer not to say'),
                    ),
                  ],
                  onChanged: _loading
                      ? null
                      : (value) => setState(() => _gender = value),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _nationality,
                  enabled: !_loading,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nationality',
                    prefixIcon: Icon(Icons.flag_outlined),
                  ),
                  validator: (value) => (value?.length ?? 0) <= 80
                      ? null
                      : 'Use 80 characters or fewer',
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _address,
                  enabled: !_loading,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Address',
                    prefixIcon: Icon(Icons.home_outlined),
                  ),
                  validator: (value) => (value?.length ?? 0) <= 300
                      ? null
                      : 'Use 300 characters or fewer',
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _bio,
                  enabled: !_loading,
                  maxLines: 4,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: 'Bio',
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Social profiles',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                _socialField(_github, 'GitHub profile URL'),
                const SizedBox(height: 12),
                _socialField(_linkedin, 'LinkedIn profile URL'),
                const SizedBox(height: 12),
                _socialField(_website, 'Portfolio or website URL'),
                const SizedBox(height: 12),
                _socialField(_otherSocial, 'Other social profile URL'),
                const SizedBox(height: 18),
                Text(
                  'Professional representation',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _position,
                  enabled: !_loading,
                  maxLength: 160,
                  decoration: const InputDecoration(
                    labelText: 'Position or professional title',
                    prefixIcon: Icon(Icons.work_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _skills,
                  enabled: !_loading,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Skills or technologies',
                    hintText: 'Separate items with commas',
                    prefixIcon: Icon(Icons.code),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: _loading ? null : _save,
                    child: _loading
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save changes'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _socialField(TextEditingController controller, String label) =>
      TextFormField(
        controller: controller,
        enabled: !_loading,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.link_outlined),
        ),
        validator: (value) {
          final link = value?.trim() ?? '';
          if (link.isEmpty) return null;
          final uri = Uri.tryParse(link);
          return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty
              ? null
              : 'Enter a valid HTTPS URL.';
        },
      );
}

String _saveErrorMessage(Object error) {
  if (error is StorageException) {
    return 'Photo upload failed: ${error.message}';
  }
  if (error is PostgrestException) {
    if (error.code == 'PGRST204' ||
        error.message.toLowerCase().contains('schema cache')) {
      return 'Supabase profile columns are missing or cached. Apply the latest Supabase migrations, then reload the API schema.';
    }
    if (error.code == 'PGRST205' ||
        error.code == '42P01' ||
        error.message.toLowerCase().contains('public.profiles')) {
      return 'The profiles table is missing in Supabase. Apply the backend migrations, then try again.';
    }
    if (error.code == '42501') {
      return 'Supabase denied this update. Apply the profile security migrations and confirm this email is verified.';
    }
    return 'Profile database save failed: ${error.message}';
  }
  return 'Could not save your profile: $error';
}

class _EditAvatar extends ConsumerWidget {
  const _EditAvatar({
    required this.path,
    required this.bytes,
    required this.onTap,
  });
  final String? path;
  final Uint8List? bytes;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storage = ref.watch(storageServiceProvider);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          Container(
            width: 144,
            height: 144,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Theme.of(context).colorScheme.secondary,
                width: 3,
              ),
            ),
            child: bytes != null
                ? Image.memory(bytes!, fit: BoxFit.cover)
                : path != null && storage != null
                ? FutureBuilder<String>(
                    future: storage.signedAvatarUrl(path!),
                    builder: (context, snapshot) {
                      if (snapshot.hasError || !snapshot.hasData) {
                        return const Icon(Icons.person_outline, size: 42);
                      }
                      return Image.network(
                        snapshot.data!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.person_outline, size: 42),
                      );
                    },
                  )
                : const Icon(Icons.person_outline, size: 42),
          ),
          CircleAvatar(
            radius: 16,
            backgroundColor: Theme.of(context).colorScheme.secondary,
            child: const Icon(
              Icons.camera_alt_outlined,
              size: 16,
              color: Color(0xFF06231E),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditCoverPreview extends StatefulWidget {
  const _EditCoverPreview({
    required this.path,
    required this.bytes,
    required this.storage,
    required this.onTap,
  });

  final String? path;
  final Uint8List? bytes;
  final StorageService? storage;
  final VoidCallback? onTap;

  @override
  State<_EditCoverPreview> createState() => _EditCoverPreviewState();
}

class _EditCoverPreviewState extends State<_EditCoverPreview> {
  Future<String>? _coverUrl;

  @override
  void initState() {
    super.initState();
    _loadCover();
  }

  @override
  void didUpdateWidget(covariant _EditCoverPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path || oldWidget.storage != widget.storage) {
      _loadCover();
    }
  }

  void _loadCover() {
    _coverUrl = widget.path == null || widget.storage == null
        ? null
        : widget.storage!.signedAvatarUrl(widget.path!);
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.bytes != null
        ? Image.memory(widget.bytes!, fit: BoxFit.cover)
        : _coverUrl == null
        ? null
        : FutureBuilder<String>(
            future: _coverUrl,
            builder: (context, snapshot) => snapshot.hasData
                ? Image.network(
                    snapshot.data!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _fallback(),
                  )
                : _fallback(),
          );
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (image != null) image else _fallback(),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x28000000), Color(0x99000000)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallback() => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF234A72), Color(0xFF274878), Color(0xFF236A66)],
      ),
    ),
    child: Center(
      child: Icon(Icons.landscape_outlined, size: 56, color: Colors.white54),
    ),
  );
}

String _date(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
