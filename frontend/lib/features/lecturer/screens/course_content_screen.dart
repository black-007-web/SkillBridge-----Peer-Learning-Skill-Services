import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/course_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/course_provider.dart';
import '../../../services/resource_service.dart';

class CourseContentScreen extends ConsumerStatefulWidget {
  const CourseContentScreen({super.key, required this.courseId});
  final String courseId;
  @override
  ConsumerState<CourseContentScreen> createState() =>
      _CourseContentScreenState();
}

class _CourseContentScreenState extends ConsumerState<CourseContentScreen> {
  late Future<_ContentData> _data;
  ResourceService? get _resources => ref.read(resourceServiceProvider);
  bool _editable = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _data = _fetch();
  }

  Future<_ContentData> _fetch() async {
    final course = await ref
        .read(courseServiceProvider)
        ?.getCourse(widget.courseId);
    _editable =
        course != null &&
        {
          CourseStatus.draft,
          CourseStatus.rejected,
          CourseStatus.unpublished,
          CourseStatus.published,
        }.contains(course.status);
    final service = _resources;
    if (service == null) {
      throw StateError('Connect Supabase to view course content.');
    }
    final data = await Future.wait([
      service.modules(widget.courseId),
      service.folders(widget.courseId),
      service.resources(widget.courseId),
    ]);
    return _ContentData(
      course?.title ?? 'Course content',
      data[0],
      data[1],
      data[2],
    );
  }

  Future<String?> _textDialog(
    String title,
    String label, {
    bool multiline = false,
    String initialValue = '',
  }) async {
    final controller = TextEditingController(text: initialValue);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: multiline ? 3 : 1,
          maxLines: multiline ? 6 : 1,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _addModule() async {
    final title = await _textDialog('Add module', 'Module title');
    if (title == null) return;
    final description =
        await _textDialog(
          'Module description',
          'Description',
          multiline: true,
        ) ??
        '';
    try {
      await _resources!.createModule(widget.courseId, title, description);
      if (mounted) setState(_load);
    } catch (error) {
      _error(error);
    }
  }

  Future<void> _editModule(Map<String, dynamic> module) async {
    final title = await _textDialog(
      'Edit module',
      'Module title',
      initialValue: '${module['title']}',
    );
    if (title == null) return;
    final description = await _textDialog(
      'Module description',
      'Description',
      multiline: true,
      initialValue: '${module['description'] ?? ''}',
    );
    if (description == null) return;
    try {
      await _resources!.updateModule(
        module['id'] as String,
        title,
        description,
      );
      if (mounted) setState(_load);
    } catch (error) {
      _error(error);
    }
  }

  Future<void> _deleteModule(String id) async {
    try {
      await _resources!.deleteModule(id);
      if (mounted) setState(_load);
    } catch (error) {
      _error(error);
    }
  }

  Future<void> _addLesson(String moduleId) async {
    final title = await _textDialog('Add lesson', 'Lesson title');
    if (title == null) return;
    final body =
        await _textDialog(
          'Lesson content',
          'Text lesson content',
          multiline: true,
        ) ??
        '';
    try {
      await _resources!.createLesson(moduleId, title, body);
      if (mounted) setState(_load);
    } catch (error) {
      _error(error);
    }
  }

  Future<void> _editLesson(Map<String, dynamic> lesson) async {
    final title = await _textDialog(
      'Edit lesson',
      'Lesson title',
      initialValue: '${lesson['title']}',
    );
    if (title == null) return;
    final body = await _textDialog(
      'Lesson content',
      'Text lesson content',
      multiline: true,
      initialValue: '${lesson['body'] ?? ''}',
    );
    if (body == null) return;
    try {
      await _resources!.updateLesson(lesson['id'] as String, title, body);
      if (mounted) setState(_load);
    } catch (error) {
      _error(error);
    }
  }

  Future<void> _deleteLesson(String id) async {
    try {
      await _resources!.deleteLesson(id);
      if (mounted) setState(_load);
    } catch (error) {
      _error(error);
    }
  }

  Future<void> _addFolder() async {
    final name = await _textDialog('Add resource folder', 'Folder name');
    if (name == null) return;
    try {
      await _resources!.createFolder(widget.courseId, name);
      if (mounted) setState(_load);
    } catch (error) {
      _error(error);
    }
  }

  Future<void> _renameFolder(Map<String, dynamic> folder) async {
    final name = await _textDialog(
      'Rename folder',
      'Folder name',
      initialValue: '${folder['name']}',
    );
    if (name == null) return;
    try {
      await _resources!.renameFolder(folder['id'] as String, name);
      if (mounted) setState(_load);
    } catch (error) {
      _error(error);
    }
  }

  Future<void> _deleteFolder(String id) async {
    try {
      await _resources!.deleteFolder(id);
      if (mounted) setState(_load);
    } catch (error) {
      _error(error);
    }
  }

  Future<void> _upload({String? folderId, String? lessonId}) async {
    if (_uploading) return;
    setState(() => _uploading = true);
    try {
      final path = await _resources!.pickAndUpload(
        courseId: widget.courseId,
        folderId: folderId,
        lessonId: lessonId,
      );
      if (path != null && mounted) {
        setState(_load);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Resource uploaded privately.')),
        );
      }
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _addLink({String? folderId, String? lessonId}) async {
    final form = GlobalKey<FormState>();
    final title = TextEditingController();
    final url = TextEditingController();
    final submit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add external learning link'),
        content: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: title,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (v) =>
                    (v?.trim().length ?? 0) < 2 ? 'Enter a title.' : null,
              ),
              TextFormField(
                controller: url,
                decoration: const InputDecoration(labelText: 'HTTPS URL'),
                keyboardType: TextInputType.url,
                validator: (v) => Uri.tryParse(v ?? '')?.scheme == 'https'
                    ? null
                    : 'Enter a valid HTTPS URL.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(context, true);
            },
            child: const Text('Add link'),
          ),
        ],
      ),
    );
    if (submit == true) {
      try {
        await _resources!.addExternalLink(
          courseId: widget.courseId,
          folderId: folderId,
          lessonId: lessonId,
          title: title.text,
          url: url.text,
        );
        if (mounted) setState(_load);
      } catch (error) {
        _error(error);
      }
    }
    title.dispose();
    url.dispose();
  }

  Future<void> _editResource(Map<String, dynamic> resource) async {
    final title = TextEditingController(text: '${resource['title']}');
    final url = TextEditingController(
      text: resource['external_url'] as String? ?? '',
    );
    final isLink = resource['resource_type'] == 'link';
    final form = GlobalKey<FormState>();
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit resource'),
        content: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: title,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (value) =>
                    (value?.trim().length ?? 0) < 2 ? 'Enter a title.' : null,
              ),
              if (isLink)
                TextFormField(
                  controller: url,
                  decoration: const InputDecoration(labelText: 'HTTPS URL'),
                  keyboardType: TextInputType.url,
                  validator: (value) {
                    final uri = Uri.tryParse(value ?? '');
                    return uri != null &&
                            uri.scheme == 'https' &&
                            uri.host.isNotEmpty
                        ? null
                        : 'Enter a valid HTTPS URL.';
                  },
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (save == true) {
      try {
        await _resources!.updateResource(
          id: resource['id'] as String,
          title: title.text,
          externalUrl: isLink ? url.text : null,
        );
        if (mounted) setState(_load);
      } catch (error) {
        _error(error);
      }
    }
    title.dispose();
    url.dispose();
  }

  void _error(Object error) {
    final message = switch (error) {
      StorageException(statusCode: '403') => 'Supabase blocked this upload. Apply the latest course-resource RLS migration and confirm the signed-in lecturer owns this course.',
      PostgrestException(code: '42501') => 'Supabase denied this content change. Apply the latest course-resource RLS migration and confirm this account has the lecturer role.',
      _ => 'Content update failed: $error',
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Course content'),
      actions: [
        if (_editable)
          IconButton(
            tooltip: 'Add module',
            onPressed: _addModule,
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
        if (_editable)
          IconButton(
            tooltip: 'Add folder',
            onPressed: _addFolder,
            icon: const Icon(Icons.folder_open_outlined),
          ),
        IconButton(
          onPressed: () => setState(_load),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<_ContentData>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load course content: ${snapshot.error}'),
            ),
          );
        }
        final data = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              data.courseTitle,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (_uploading) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
              const SizedBox(height: 6),
              const Text('Uploading and saving resource metadata…'),
            ],
            if (!_editable)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  'Content editing is unavailable while this course is awaiting review or archived.',
                ),
              ),
            const SizedBox(height: 12),
            Text(
              'Modules and lessons',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (data.modules.isEmpty)
              const ListTile(title: Text('No modules have been added.')),
            ...data.modules.map(
              (module) => _ModuleTile(
                module: module,
                editable: _editable,
                service: _resources!,
                onEditModule: () => _editModule(module),
                onDeleteModule: () => _deleteModule(module['id'] as String),
                onAddLesson: () => _addLesson(module['id'] as String),
                onEditLesson: _editLesson,
                onDeleteLesson: _deleteLesson,
                onAddFile: (lessonId) => _upload(lessonId: lessonId),
                onAddLink: (lessonId) => _addLink(lessonId: lessonId),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Resource folders',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (data.folders.isEmpty)
              const ListTile(
                title: Text('No resource folders have been added.'),
              ),
            ...data.folders.map(
              (folder) => ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text('${folder['name']}'),
                trailing: _editable
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Rename folder',
                            onPressed: () => _renameFolder(folder),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: 'Upload to folder',
                            onPressed: () =>
                                _upload(folderId: folder['id'] as String),
                            icon: const Icon(Icons.upload_file),
                          ),
                          IconButton(
                            tooltip: 'Add link to folder',
                            onPressed: () =>
                                _addLink(folderId: folder['id'] as String),
                            icon: const Icon(Icons.link),
                          ),
                          IconButton(
                            tooltip: 'Delete folder',
                            onPressed: () =>
                                _deleteFolder(folder['id'] as String),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      )
                    : null,
              ),
            ),
            if (_editable)
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _upload,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Upload file'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _addLink,
                    icon: const Icon(Icons.link),
                    label: const Text('Add HTTPS link'),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            Text('Resources', style: Theme.of(context).textTheme.titleLarge),
            if (data.resources.isEmpty)
              const ListTile(title: Text('No resources yet.')),
            ...data.resources.map(
              (resource) => ListTile(
                leading: Icon(
                  resource['resource_type'] == 'link'
                      ? Icons.link
                      : Icons.insert_drive_file_outlined,
                ),
                title: Text('${resource['title']}'),
                subtitle: Text('${resource['resource_type']}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Open resource',
                      onPressed: () => _openResource(resource),
                      icon: const Icon(Icons.open_in_new),
                    ),
                    if (_editable)
                      IconButton(
                        tooltip: 'Edit resource',
                        onPressed: () => _editResource(resource),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    if (_editable)
                      IconButton(
                        tooltip: 'Delete resource',
                        onPressed: () async {
                          try {
                            await _resources!.deleteResource(resource);
                            if (mounted) setState(_load);
                          } catch (error) {
                            _error(error);
                          }
                        },
                        icon: const Icon(Icons.delete_outline),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    ),
  );

  Future<void> _openExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the resource link.')),
      );
    }
  }

  Future<void> _openResource(Map<String, dynamic> resource) async {
    try {
      final url =
          resource['external_url'] as String? ??
          await _resources!.signedUrl(resource['storage_path'] as String);
      await _openExternal(url);
    } catch (error) {
      _error(error);
    }
  }
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({
    required this.module,
    required this.editable,
    required this.service,
    required this.onEditModule,
    required this.onDeleteModule,
    required this.onAddLesson,
    required this.onEditLesson,
    required this.onDeleteLesson,
    required this.onAddFile,
    required this.onAddLink,
  });
  final Map<String, dynamic> module;
  final bool editable;
  final ResourceService service;
  final VoidCallback onEditModule;
  final VoidCallback onDeleteModule;
  final VoidCallback onAddLesson;
  final void Function(Map<String, dynamic> lesson) onEditLesson;
  final void Function(String lessonId) onDeleteLesson;
  final void Function(String lessonId) onAddFile, onAddLink;
  @override
  Widget build(BuildContext context) => Card(
    child: ExpansionTile(
      title: Text('${module['title']}'),
      subtitle: Text('${module['description']}'),
      children: [
        if (editable)
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              children: [
                TextButton.icon(
                  onPressed: onEditModule,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit module'),
                ),
                TextButton.icon(
                  onPressed: onDeleteModule,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete module'),
                ),
              ],
            ),
          ),
        if (editable)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onAddLesson,
              icon: const Icon(Icons.post_add),
              label: const Text('Add lesson'),
            ),
          ),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: service.lessons(module['id'] as String),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(12),
                child: LinearProgressIndicator(),
              );
            }
            if (snapshot.data!.isEmpty) {
              return const ListTile(title: Text('No lessons in this module.'));
            }
            return Column(
              children: snapshot.data!
                  .map(
                    (lesson) => ListTile(
                      leading: const Icon(Icons.play_lesson_outlined),
                      title: Text('${lesson['title']}'),
                      subtitle: Text('${lesson['body']}'),
                      isThreeLine: true,
                      trailing: editable
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Edit lesson',
                                  onPressed: () => onEditLesson(lesson),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  tooltip: 'Attach file',
                                  onPressed: () =>
                                      onAddFile(lesson['id'] as String),
                                  icon: const Icon(Icons.upload_file),
                                ),
                                IconButton(
                                  tooltip: 'Attach link',
                                  onPressed: () =>
                                      onAddLink(lesson['id'] as String),
                                  icon: const Icon(Icons.link),
                                ),
                                IconButton(
                                  tooltip: 'Delete lesson',
                                  onPressed: () =>
                                      onDeleteLesson(lesson['id'] as String),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            )
                          : null,
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    ),
  );
}

class _ContentData {
  const _ContentData(
    this.courseTitle,
    this.modules,
    this.folders,
    this.resources,
  );
  final String courseTitle;
  final List<Map<String, dynamic>> modules, folders, resources;
}
