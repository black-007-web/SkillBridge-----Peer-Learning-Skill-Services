import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/course_model.dart';
import '../../../providers/course_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/storage_service.dart';

class CourseEditorScreen extends ConsumerStatefulWidget {
  const CourseEditorScreen({super.key, this.courseId});
  final String? courseId;
  @override
  ConsumerState<CourseEditorScreen> createState() => _CourseEditorScreenState();
}

class _CourseEditorScreenState extends ConsumerState<CourseEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _category = TextEditingController();
  final _coverImage = TextEditingController();
  final _outcomes = TextEditingController();
  final _prerequisites = TextEditingController();
  final _duration = TextEditingController();
  Uint8List? _coverBytes;
  String? _coverMime;
  Future<String>? _storedCoverUrl;
  String _level = 'Beginner';
  String _visibility = 'enrolled_students';
  CourseStatus? _status;
  bool _loading = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _pickCoverImage() async {
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
        _message('Choose a JPG, PNG, or WebP course image.');
        return;
      }
      final bytes = await image.readAsBytes();
      if (bytes.isEmpty || bytes.length > StorageService.maxAvatarBytes) {
        _message('Choose an image smaller than 2 MB.');
        return;
      }
      setState(() {
        _coverBytes = bytes;
        _coverMime = mime;
      });
    } catch (_) {
      if (mounted) _message('Could not open the image picker.');
    }
  }

  Future<void> _load() async {
    final id = widget.courseId;
    if (id == null) {
      if (mounted) setState(() => _ready = true);
      return;
    }
    try {
      final course = await ref.read(courseServiceProvider)?.getCourse(id);
      if (!mounted) return;
      if (course != null) {
        _title.text = course.title;
        _description.text = course.description;
        _category.text = course.category;
        _coverImage.text = course.coverImagePath ?? '';
        final storage = ref.read(storageServiceProvider);
        if (storage != null &&
            storage.isCourseCoverPath(_coverImage.text.trim())) {
          _storedCoverUrl = storage.signedCourseCoverUrl(
            _coverImage.text.trim(),
          );
        }
        _outcomes.text = course.learningOutcomes;
        _prerequisites.text = course.prerequisites;
        _duration.text = course.estimatedMinutes?.toString() ?? '';
        _level = course.level;
        _visibility = course.visibility;
        _status = course.status;
      }
      setState(() => _ready = true);
    } catch (error) {
      if (mounted) {
        setState(() => _ready = true);
        _message('Could not load course: $error');
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _category.dispose();
    _coverImage.dispose();
    _outcomes.dispose();
    _prerequisites.dispose();
    _duration.dispose();
    super.dispose();
  }

  Future<void> _save({required bool submit, bool addContent = false}) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    var courseSaved = false;
    var savingCover = false;
    String? stagedCoverPath;
    StorageService? coverStorage;
    try {
      final service = ref.read(courseServiceProvider)!;
      final minutes = int.tryParse(_duration.text.trim());
      final priorCover = _coverImage.text.trim();
      var course = widget.courseId == null
          ? await service.createCourse(
              title: _title.text,
              description: _description.text,
              category: _category.text,
              level: _level,
              learningOutcomes: _outcomes.text,
              prerequisites: _prerequisites.text,
              visibility: _visibility,
              estimatedMinutes: minutes,
              coverImagePath: _coverImage.text,
            )
          : await service.updateCourse(
              id: widget.courseId!,
              title: _title.text,
              description: _description.text,
              category: _category.text,
              level: _level,
              learningOutcomes: _outcomes.text,
              prerequisites: _prerequisites.text,
              visibility: _visibility,
              estimatedMinutes: minutes,
              coverImagePath: _coverImage.text,
            );
      courseSaved = true;
      if (_coverBytes != null && _coverMime != null) {
        savingCover = true;
        final storage = ref.read(storageServiceProvider);
        final user = ref.read(authServiceProvider)?.currentUser;
        if (storage == null || user == null) {
          throw StateError('Sign in before uploading a course image.');
        }
        coverStorage = storage;
        final coverUrl = await storage.uploadCourseCover(
          courseId: course.id,
          userId: user.id,
          bytes: _coverBytes!,
          mimeType: _coverMime!,
        );
        stagedCoverPath = storage.courseCoverPathFromUrl(coverUrl);
        course = await service.updateCourse(
          id: course.id,
          title: _title.text,
          description: _description.text,
          category: _category.text,
          level: _level,
          learningOutcomes: _outcomes.text,
          prerequisites: _prerequisites.text,
          visibility: _visibility,
          estimatedMinutes: minutes,
          coverImagePath: coverUrl,
        );
        _coverImage.text = coverUrl;
        _storedCoverUrl = storage.signedCourseCoverUrl(coverUrl);
        _coverBytes = null;
        _coverMime = null;
        stagedCoverPath = null;
        savingCover = false;
      }
      if (priorCover.isNotEmpty && priorCover != _coverImage.text.trim()) {
        final storage = coverStorage ?? ref.read(storageServiceProvider);
        final previousPath = storage?.courseCoverPathFromUrl(priorCover);
        if (storage != null && previousPath != null) {
          try {
            await storage.removeCourseCover(previousPath);
          } on StorageException catch (error) {
            _message(
              'Course saved, but the previous image was not removed: ${error.message}',
            );
          }
        }
      }
      if (submit && _status != CourseStatus.published) {
        await service.submitCourse(course.id);
      }
      ref.invalidate(myCoursesProvider);
      if (!mounted) return;
      if (addContent) {
        await context.push('/lecturer/courses/${course.id}/content');
        ref.invalidate(myCoursesProvider);
      } else {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        if (stagedCoverPath != null && coverStorage != null) {
          try {
            await coverStorage.removeCourseCover(stagedCoverPath);
          } on StorageException catch (cleanupError) {
            _message(
              'Cover update failed and the uploaded image could not be removed: $cleanupError',
            );
          }
        }
        _message(
          courseSaved && savingCover
              ? 'Course was saved, but the cover image could not be updated: $error'
              : 'Could not save course: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Widget _coverPreview() {
    if (_coverBytes != null) {
      return Image.memory(_coverBytes!, fit: BoxFit.cover);
    }
    final path = _coverImage.text.trim();
    final storage = ref.read(storageServiceProvider);
    if (storage != null && storage.isCourseCoverPath(path)) {
      return FutureBuilder<String>(
        future: _storedCoverUrl ??= storage.signedCourseCoverUrl(path),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.hasError) {
            return _coverPlaceholder();
          }
          return Image.network(
            snapshot.data!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _coverPlaceholder(),
          );
        },
      );
    }
    if (path.isNotEmpty) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _coverPlaceholder(),
      );
    }
    return _coverPlaceholder();
  }

  Widget _coverPlaceholder() => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF3752A4), Color(0xFF14786F)],
      ),
    ),
    child: const Center(
      child: Icon(Icons.auto_stories_outlined, size: 44, color: Colors.white70),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.courseId == null ? 'Create course' : 'Edit course'),
    ),
    body: !_ready
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Course information',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: 'Course title'),
                  maxLength: 160,
                  validator: (v) => (v?.trim().length ?? 0) < 3
                      ? 'Enter at least 3 characters.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _description,
                  decoration: const InputDecoration(labelText: 'Description'),
                  minLines: 4,
                  maxLines: 7,
                  maxLength: 5000,
                  validator: (v) => (v?.trim().length ?? 0) < 10
                      ? 'Add a little more detail.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  maxLength: 80,
                  validator: (v) =>
                      (v?.trim().length ?? 0) < 2 ? 'Enter a category.' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _coverImage,
                  onChanged: (_) {
                    setState(() {
                      _coverBytes = null;
                      _coverMime = null;
                      _storedCoverUrl = null;
                    });
                  },
                  decoration: const InputDecoration(
                    labelText: 'Course cover image URL (optional)',
                    hintText: 'https://example.com/course-cover.jpg',
                    helperText: 'Paste a public HTTPS image URL or choose an image below.',
                    prefixIcon: Icon(Icons.image_outlined),
                  ),
                  keyboardType: TextInputType.url,
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) return null;
                    if (ref
                            .read(storageServiceProvider)
                            ?.isCourseCoverPath(text) ==
                        true) {
                      return null;
                    }
                    final uri = Uri.tryParse(text);
                    return uri == null ||
                            uri.scheme != 'https' ||
                            uri.host.isEmpty
                        ? 'Enter a valid HTTPS image URL.'
                        : null;
                  },
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: 170,
                    width: double.infinity,
                    child: _coverPreview(),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _pickCoverImage,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Choose topic image'),
                    ),
                    if (_coverBytes != null || _coverImage.text.isNotEmpty)
                      TextButton.icon(
                        onPressed: _loading
                            ? null
                            : () => setState(() {
                                _coverBytes = null;
                                _coverMime = null;
                              _storedCoverUrl = null;
                              _coverImage.clear();
                            }),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Remove image'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _level,
                  decoration: const InputDecoration(labelText: 'Level'),
                  items:
                      const [
                            'Beginner',
                            'Intermediate',
                            'Advanced',
                            'All levels',
                          ]
                          .map(
                            (v) => DropdownMenuItem(value: v, child: Text(v)),
                          )
                          .toList(),
                  onChanged: (v) => setState(() => _level = v ?? _level),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _outcomes,
                  decoration: const InputDecoration(
                    labelText: 'Learning outcomes (one per line)',
                  ),
                  minLines: 2,
                  maxLines: 5,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _prerequisites,
                  decoration: const InputDecoration(labelText: 'Prerequisites'),
                  minLines: 2,
                  maxLines: 4,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _duration,
                  decoration: const InputDecoration(
                    labelText: 'Estimated minutes (optional)',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if ((v ?? '').trim().isEmpty) return null;
                    final n = int.tryParse(v!);
                    return n == null || n < 1
                        ? 'Enter a positive number.'
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _visibility,
                  decoration: const InputDecoration(
                    labelText: 'Course content access',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'enrolled_students',
                      child: Text('Enrollment required (course stays listed)'),
                    ),
                    DropdownMenuItem(
                      value: 'public',
                      child: Text('Public content preview'),
                    ),
                  ],
                  onChanged: (v) =>
                      setState(() => _visibility = v ?? _visibility),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _loading ? null : () => _save(submit: false),
                  icon: const Icon(Icons.save_outlined),
                  label: Text(
                    _loading
                        ? 'Saving…'
                        : _status == CourseStatus.published
                        ? 'Save course changes'
                        : 'Save draft',
                  ),
                ),
                if (_status != CourseStatus.published) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _loading
                        ? null
                        : () => _save(submit: false, addContent: true),
                    icon: const Icon(Icons.library_add_outlined),
                    label: const Text('Save draft and add course content'),
                  ),
                ],
                if (_status != CourseStatus.published) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : () => _save(submit: true),
                    icon: const Icon(Icons.send_outlined),
                    label: const Text('Save and submit for review'),
                  ),
                ],
              ],
            ),
          ),
  );
}
