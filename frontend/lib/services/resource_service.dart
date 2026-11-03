import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'folder_upload_source.dart';

class ResourceService {
  ResourceService(this.client);
  final SupabaseClient client;

  static const bucket = 'course-resources';
  static const maxFileBytes = 50 * 1024 * 1024;
  static const _mimeByExtension = <String, String>{
    '3gp': 'video/3gpp',
    '7z': 'application/x-7z-compressed',
    'aac': 'audio/aac',
    'aiff': 'audio/aiff',
    'amr': 'audio/amr',
    'avi': 'video/x-msvideo',
    'avif': 'image/avif',
    'bmp': 'image/bmp',
    'c': 'text/x-c',
    'cc': 'text/x-c',
    'cpp': 'text/x-c++',
    'cs': 'text/plain',
    'css': 'text/css',
    'csv': 'text/csv',
    'dart': 'text/x-dart',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'flac': 'audio/flac',
    'gif': 'image/gif',
    'go': 'text/x-go',
    'gz': 'application/gzip',
    'heic': 'image/heic',
    'heif': 'image/heif',
    'htm': 'text/plain',
    'html': 'text/plain',
    'xhtml': 'text/plain',
    'ico': 'image/vnd.microsoft.icon',
    'java': 'text/x-java-source',
    'jpeg': 'image/jpeg',
    'jpg': 'image/jpeg',
    'js': 'text/javascript',
    'json': 'application/json',
    'jsx': 'text/jsx',
    'kt': 'text/x-kotlin',
    'm4a': 'audio/mp4',
    'm4v': 'video/x-m4v',
    'md': 'text/markdown',
    'mid': 'audio/midi',
    'midi': 'audio/midi',
    'mkv': 'video/x-matroska',
    'mov': 'video/quicktime',
    'mp3': 'audio/mpeg',
    'mp4': 'video/mp4',
    'mpeg': 'video/mpeg',
    'mpg': 'video/mpeg',
    'mjs': 'text/javascript',
    'oga': 'audio/ogg',
    'ogg': 'audio/ogg',
    'opus': 'audio/opus',
    'pdf': 'application/pdf',
    'php': 'application/x-httpd-php',
    'png': 'image/png',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'ps1': 'text/plain',
    'py': 'text/x-python',
    'rb': 'text/x-ruby',
    'rs': 'text/x-rust',
    'sh': 'text/x-shellscript',
    'sql': 'application/sql',
    'svg': 'text/plain',
    'swift': 'text/x-swift',
    'tar': 'application/x-tar',
    'tgz': 'application/gzip',
    'ts': 'text/typescript',
    'tsx': 'text/tsx',
    'txt': 'text/plain',
    'wav': 'audio/wav',
    'webm': 'video/webm',
    'webp': 'image/webp',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'xml': 'application/xml',
    'yaml': 'application/yaml',
    'yml': 'application/yaml',
    'zip': 'application/zip',
  };

  static void validateFileSize(int? size) {
    if (size == null || size > maxFileBytes) {
      throw const StorageException('Choose a file no larger than 50 MB.');
    }
  }

  static String mimeTypeForFile(String fileName, {String? detectedMimeType}) {
    final extension = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    const unsafeInlineTypes = {
      'text/html',
      'application/xhtml+xml',
      'image/svg+xml',
      'text/javascript',
      'application/javascript',
      'application/ecmascript',
    };
    if (unsafeInlineTypes.contains(detectedMimeType?.toLowerCase())) {
      return 'text/plain';
    }
    if (detectedMimeType != null &&
        RegExp(
          r'^[a-z0-9!#$&^_.+-]+/[a-z0-9!#$&^_.+-]+$',
          caseSensitive: false,
        ).hasMatch(detectedMimeType)) {
      return detectedMimeType.toLowerCase();
    }
    return _mimeByExtension[extension] ?? 'application/octet-stream';
  }

  Future<List<Map<String, dynamic>>> modules(String courseId) async {
    final rows = await client
        .from('course_modules')
        .select('id,course_id,title,description,position')
        .eq('course_id', courseId)
        .order('position');
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<List<Map<String, dynamic>>> lessons(String moduleId) async {
    final rows = await client
        .from('lessons')
        .select('id,module_id,title,body,position,duration_minutes')
        .eq('module_id', moduleId)
        .order('position');
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<List<Map<String, dynamic>>> folders(String courseId) async {
    final rows = await client
        .from('resource_folders')
        .select('id,course_id,parent_id,name,position')
        .eq('course_id', courseId)
        .order('position');
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<List<Map<String, dynamic>>> resources(String courseId) async {
    final rows = await client
        .from('resources')
        .select(
          'id,course_id,folder_id,lesson_id,title,resource_type,storage_path,external_url,mime_type,file_size_bytes,position',
        )
        .eq('course_id', courseId)
        .order('position');
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<void> createModule(
    String courseId,
    String title,
    String description,
  ) async {
    final count = await client
        .from('course_modules')
        .select('id')
        .eq('course_id', courseId);
    await client.from('course_modules').insert({
      'course_id': courseId,
      'title': title.trim(),
      'description': description.trim(),
      'position': count.length,
    });
  }

  Future<void> updateModule(String id, String title, String description) async {
    await client
        .from('course_modules')
        .update({
          'title': title.trim(),
          'description': description.trim(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id);
  }

  Future<void> deleteModule(String id) async {
    await client.from('course_modules').delete().eq('id', id);
  }

  Future<void> createLesson(
    String moduleId,
    String title,
    String body, {
    int? durationMinutes,
  }) async {
    final count = await client
        .from('lessons')
        .select('id')
        .eq('module_id', moduleId);
    await client.from('lessons').insert({
      'module_id': moduleId,
      'title': title.trim(),
      'body': body.trim(),
      'duration_minutes': durationMinutes,
      'position': count.length,
    });
  }

  Future<void> updateLesson(String id, String title, String body) async {
    await client
        .from('lessons')
        .update({
          'title': title.trim(),
          'body': body.trim(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id);
  }

  Future<void> deleteLesson(String id) async {
    await client.from('lessons').delete().eq('id', id);
  }

  Future<String> createFolder(
    String courseId,
    String name, {
    String? parentId,
  }) => _createFolder(courseId, name, parentId: parentId);

  Future<void> renameFolder(String id, String name) async {
    await client
        .from('resource_folders')
        .update({'name': name.trim()})
        .eq('id', id);
  }

  Future<int> deleteFolder(String id) async {
    final root = await client
        .from('resource_folders')
        .select('id,course_id,parent_id')
        .eq('id', id)
        .maybeSingle();
    if (root == null) {
      throw StateError('The selected resource folder no longer exists.');
    }
    final courseId = root['course_id'] as String;
    const pageSize = 500;
    final folders = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += pageSize) {
      final page = await client
          .from('resource_folders')
          .select('id,parent_id')
          .eq('course_id', courseId)
          .order('id')
          .range(offset, offset + pageSize - 1);
      folders.addAll(page.map((row) => Map<String, dynamic>.from(row)));
      if (page.length < pageSize) break;
    }
    final folderIds = folderIdsForDeletion(id, folders);

    final resourceRows = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += pageSize) {
      final page = await client
          .from('resources')
          .select('id,storage_path')
          .eq('course_id', courseId)
          .inFilter('folder_id', folderIds)
          .order('id')
          .range(offset, offset + pageSize - 1);
      resourceRows.addAll(page.map((row) => Map<String, dynamic>.from(row)));
      if (page.length < pageSize) break;
    }

    final resources = resourceRows;
    final storagePaths = resources
        .map((resource) => resource['storage_path'] as String?)
        .whereType<String>()
        .toList();
    for (var offset = 0; offset < storagePaths.length; offset += 100) {
      await client.storage
          .from(bucket)
          .remove(storagePaths.skip(offset).take(100).toList());
    }

    await client.from('resources').delete().inFilter('folder_id', folderIds);
    await client.from('resource_folders').delete().eq('id', id);
    return resources.length;
  }

  static List<String> folderIdsForDeletion(
    String rootId,
    List<Map<String, dynamic>> folders,
  ) {
    final parentById = {
      for (final folder in folders)
        folder['id'] as String: folder['parent_id'] as String?,
    };
    if (!parentById.containsKey(rootId)) {
      throw StateError('The selected resource folder no longer exists.');
    }

    final ids = <String>{rootId};
    var changed = true;
    while (changed) {
      changed = false;
      for (final entry in parentById.entries) {
        if (entry.value != null &&
            ids.contains(entry.value) &&
            ids.add(entry.key)) {
          changed = true;
        }
      }
    }
    return ids.toList(growable: false);
  }

  Future<void> addExternalLink({
    required String courseId,
    String? folderId,
    String? lessonId,
    required String title,
    required String url,
  }) async {
    final parsed = Uri.tryParse(url.trim());
    if (parsed == null || parsed.scheme != 'https' || parsed.host.isEmpty) {
      throw ArgumentError('Enter a valid HTTPS learning link.');
    }
    await client.from('resources').insert({
      'course_id': courseId,
      'folder_id': folderId,
      'lesson_id': lessonId,
      'title': title.trim(),
      'resource_type': 'link',
      'external_url': parsed.toString(),
      'created_by': client.auth.currentUser!.id,
    });
  }

  Future<String?> pickAndUpload({
    required String courseId,
    String? folderId,
    String? lessonId,
  }) async {
    final file = await FilePicker.pickFile(type: FileType.any);
    if (file == null) return null;
    final declaredSize = file.lengthSync() ?? await file.length();
    validateFileSize(declaredSize);
    final bytes = await file.readAsBytes();
    if (bytes.length != declaredSize || bytes.length > maxFileBytes) {
      throw const StorageException('The file changed while it was being read.');
    }
    return _uploadBytes(
      courseId: courseId,
      folderId: folderId,
      lessonId: lessonId,
      fileName: file.name,
      bytes: bytes,
    );
  }

  Future<FolderUploadResult?> pickAndUploadFolder({
    required String courseId,
    String? folderId,
    void Function(int completed, int total)? onProgress,
  }) async {
    final selection = await pickFolderUpload();
    if (selection == null) return null;
    if (selection.files.isEmpty) {
      return FolderUploadResult(
        folderName: selection.name,
        total: 0,
        uploaded: const [],
        failures: const [],
        warning: selection.warning,
      );
    }

    final folderIds = <String, String>{};
    if (folderId != null) folderIds[''] = folderId;

    final uploaded = <String>[];
    final failures = <FolderUploadFailure>[];
    var completed = 0;
    for (final file in selection.files) {
      try {
        final declaredSize = file.size;
        validateFileSize(declaredSize);
        final bytes = await file.readBytes();
        if (bytes.length != declaredSize || bytes.length > maxFileBytes) {
          throw const StorageException(
            'The file changed while it was being read.',
          );
        }
        if (!folderIds.containsKey('')) {
          folderIds[''] = await _createFolder(courseId, selection.name);
        }
        final destinationFolderId = await _folderForFile(
          courseId: courseId,
          relativePath: file.relativePath,
          folderIds: folderIds,
        );
        await _uploadBytes(
          courseId: courseId,
          folderId: destinationFolderId,
          fileName: file.name,
          detectedMimeType: file.mimeType,
          bytes: bytes,
        );
        uploaded.add(file.relativePath);
      } catch (error) {
        failures.add(FolderUploadFailure(file.relativePath, error.toString()));
      } finally {
        completed++;
        onProgress?.call(completed, selection.files.length);
      }
    }
    return FolderUploadResult(
      folderName: selection.name,
      total: selection.files.length,
      uploaded: uploaded,
      failures: failures,
      warning: selection.warning,
    );
  }

  static List<String> folderSegmentsForFile(String relativePath) {
    final normalizedPath = relativePath.replaceAll('\\', '/');
    final segments = normalizedPath.split('/');
    if (normalizedPath.isEmpty ||
        normalizedPath.startsWith('/') ||
        RegExp(r'^[a-zA-Z]:').hasMatch(normalizedPath) ||
        normalizedPath.contains('\u0000') ||
        segments.any(
          (segment) => segment.isEmpty || segment == '..' || segment == '.',
        )) {
      throw ArgumentError.value(relativePath, 'relativePath', 'Invalid path.');
    }
    return segments
        .take(segments.length - 1)
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
  }

  Future<String> _folderForFile({
    required String courseId,
    required String relativePath,
    required Map<String, String> folderIds,
  }) async {
    final segments = folderSegmentsForFile(relativePath);
    var parentPath = '';
    for (final segment in segments) {
      final path = parentPath.isEmpty ? segment : '$parentPath/$segment';
      if (!folderIds.containsKey(path)) {
        folderIds[path] = await _createFolder(
          courseId,
          segment,
          parentId: folderIds[parentPath],
        );
      }
      parentPath = path;
    }
    return folderIds[parentPath]!;
  }

  Future<String> _createFolder(
    String courseId,
    String name, {
    String? parentId,
  }) async {
    final normalizedName = name.trim();
    final existingId = await _existingFolderId(
      courseId,
      normalizedName,
      parentId: parentId,
    );
    if (existingId != null) return existingId;

    final count = await client
        .from('resource_folders')
        .select('id')
        .eq('course_id', courseId);
    try {
      final row = await client
          .from('resource_folders')
          .insert({
            'course_id': courseId,
            'parent_id': parentId,
            'name': normalizedName,
            'position': count.length,
          })
          .select('id')
          .single();
      return row['id'] as String;
    } on PostgrestException catch (error) {
      if (error.code != '23505') rethrow;
      final racedId = await _existingFolderId(
        courseId,
        normalizedName,
        parentId: parentId,
      );
      if (racedId == null) rethrow;
      return racedId;
    }
  }

  Future<String?> _existingFolderId(
    String courseId,
    String name, {
    String? parentId,
  }) async {
    final query = client
        .from('resource_folders')
        .select('id')
        .eq('course_id', courseId)
        .eq('name', name);
    final row = parentId == null
        ? await query.isFilter('parent_id', null).limit(1).maybeSingle()
        : await query.eq('parent_id', parentId).limit(1).maybeSingle();
    return row?['id'] as String?;
  }

  Future<String> _uploadBytes({
    required String courseId,
    String? folderId,
    String? lessonId,
    required String fileName,
    String? detectedMimeType,
    required Uint8List bytes,
  }) async {
    if (bytes.length > maxFileBytes) {
      throw const StorageException('Choose a file no larger than 50 MB.');
    }
    final extension = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    final safeExtension = RegExp(r'^[a-z0-9]{1,16}$').hasMatch(extension)
        ? extension
        : 'bin';
    final mimeType = mimeTypeForFile(
      fileName,
      detectedMimeType: detectedMimeType,
    );
    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      throw const AuthException('Sign in before uploading course resources.');
    }
    final path =
        '$courseId/$userId/${DateTime.now().microsecondsSinceEpoch}.$safeExtension';
    await client.storage
        .from(bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );
    try {
      final type = switch (extension) {
        'pdf' => 'pdf',
        'doc' ||
        'docx' ||
        'ppt' ||
        'pptx' ||
        'xls' ||
        'xlsx' ||
        'csv' ||
        'css' ||
        'dart' ||
        'go' ||
        'htm' ||
        'html' ||
        'java' ||
        'js' ||
        'json' ||
        'jsx' ||
        'kt' ||
        'md' ||
        'php' ||
        'ps1' ||
        'py' ||
        'rb' ||
        'rs' ||
        'sh' ||
        'sql' ||
        'swift' ||
        'ts' ||
        'tsx' ||
        'txt' ||
        'yml' ||
        'yaml' => 'document',
        _ when mimeType.startsWith('image/') => 'image',
        _ when mimeType.startsWith('video/') => 'video',
        _ => 'other',
      };
      await client.from('resources').insert({
        'course_id': courseId,
        'folder_id': folderId,
        'lesson_id': lessonId,
        'title': fileName,
        'resource_type': type,
        'storage_path': path,
        'mime_type': mimeType,
        'file_size_bytes': bytes.length,
        'created_by': userId,
      });
    } catch (_) {
      await client.storage.from(bucket).remove([path]);
      rethrow;
    }
    return path;
  }

  Future<Uint8List> download(String storagePath) async {
    if (storagePath.split('/').length < 3) {
      throw const StorageException('Invalid resource path.');
    }
    return client.storage.from(bucket).download(storagePath);
  }

  Future<String> signedUrl(String storagePath, {String? downloadAs}) => client
      .storage
      .from(bucket)
      .createSignedUrl(
        storagePath,
        300,
        download: downloadAs == null
            ? null
            : DownloadBehavior.named(_safeDownloadName(downloadAs)),
      );

  static String _safeDownloadName(String fileName) {
    final safeName = fileName.replaceAll(RegExp(r'[/\\\r\n]'), '_').trim();
    return safeName.isEmpty ? 'course-resource' : safeName;
  }

  Future<void> updateResource({
    required String id,
    required String title,
    String? externalUrl,
  }) async {
    final update = <String, dynamic>{'title': title.trim()};
    if (externalUrl != null) {
      final parsed = Uri.tryParse(externalUrl.trim());
      if (parsed == null || parsed.scheme != 'https' || parsed.host.isEmpty) {
        throw ArgumentError('Enter a valid HTTPS learning link.');
      }
      update['external_url'] = parsed.toString();
    }
    await client.from('resources').update(update).eq('id', id);
  }

  Future<void> deleteResource(Map<String, dynamic> resource) async {
    final id = resource['id'] as String;
    await client.from('resources').delete().eq('id', id);
    final path = resource['storage_path'] as String?;
    if (path != null) await client.storage.from(bucket).remove([path]);
  }
}

class FolderUploadResult {
  const FolderUploadResult({
    required this.folderName,
    required this.total,
    required this.uploaded,
    required this.failures,
    this.warning,
  });

  final String folderName;
  final int total;
  final List<String> uploaded;
  final List<FolderUploadFailure> failures;
  final String? warning;
}

class FolderUploadFailure {
  const FolderUploadFailure(this.filePath, this.message);

  final String filePath;
  final String message;
}
