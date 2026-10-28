import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ResourceService {
  ResourceService(this.client);
  final SupabaseClient client;

  static const bucket = 'course-resources';
  static const maxFileBytes = 50 * 1024 * 1024;
  static const _mimeByExtension = <String, String>{
    'pdf': 'application/pdf',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'gif': 'image/gif',
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
    'webm': 'video/webm',
    'txt': 'text/plain',
  };

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
    await client.from('course_modules').update({
        'title': title.trim(),
        'description': description.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id);
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
    await client.from('lessons').update({
        'title': title.trim(),
        'body': body.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id);
  }

  Future<void> deleteLesson(String id) async {
    await client.from('lessons').delete().eq('id', id);
  }

  Future<void> createFolder(
    String courseId,
    String name, {
    String? parentId,
  }) async {
    final count = await client
        .from('resource_folders')
        .select('id')
        .eq('course_id', courseId);
    await client.from('resource_folders').insert({
      'course_id': courseId,
      'parent_id': parentId,
      'name': name.trim(),
      'position': count.length,
    });
  }

  Future<void> renameFolder(String id, String name) async {
    await client.from('resource_folders').update({'name': name.trim()}).eq('id', id);
  }

  Future<void> deleteFolder(String id) async {
    await client.from('resource_folders').delete().eq('id', id);
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
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: _mimeByExtension.keys.toList(growable: false),
    );
    if (file == null) return null;
    final declaredSize = file.lengthSync() ?? await file.length();
    if (declaredSize == null ||
        declaredSize <= 0 ||
        declaredSize > maxFileBytes) {
      throw const StorageException(
        'Choose a non-empty file no larger than 50 MB.',
      );
    }
    final bytes = await file.readAsBytes();
    if (bytes.length != declaredSize || bytes.length > maxFileBytes) {
      throw const StorageException('The file changed while it was being read.');
    }
    final extension = (file.extension ?? file.name.split('.').last)
        .toLowerCase();
    final mimeType = _mimeByExtension[extension];
    if (mimeType == null) {
      throw const StorageException('This file type is not supported.');
    }
    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      throw const AuthException('Sign in before uploading course resources.');
    }
    final path =
        '$courseId/$userId/${DateTime.now().microsecondsSinceEpoch}.$extension';
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
        'txt' => 'document',
        'jpg' || 'jpeg' || 'png' || 'webp' || 'gif' => 'image',
        'mp4' || 'mov' || 'webm' => 'video',
        _ => 'other',
      };
      await client.from('resources').insert({
        'course_id': courseId,
        'folder_id': folderId,
        'lesson_id': lessonId,
        'title': file.name,
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

  Future<String> signedUrl(String storagePath) =>
      client.storage.from(bucket).createSignedUrl(storagePath, 300);

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
