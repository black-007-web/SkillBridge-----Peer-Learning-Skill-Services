import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class StorageService {
  StorageService(this.client);

  final SupabaseClient client;
  static const bucket = 'avatars';
  static const maxAvatarBytes = 2 * 1024 * 1024;
  static const allowedMimeTypes = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
  };

  String? mimeForFileName(String name) {
    final extension = name.split('.').last.toLowerCase();
    return allowedMimeTypes[extension];
  }

  Future<String> uploadAvatar({
    required String userId,
    required Uint8List bytes,
    required String mimeType,
  }) => _uploadUserImage(
    userId: userId,
    prefix: 'avatar',
    bytes: bytes,
    mimeType: mimeType,
  );

  Future<String> uploadProfileCover({
    required String userId,
    required Uint8List bytes,
    required String mimeType,
  }) => _uploadUserImage(
    userId: userId,
    prefix: 'cover',
    bytes: bytes,
    mimeType: mimeType,
  );

  Future<String> _uploadUserImage({
    required String userId,
    required String prefix,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final extension = _validatedImageExtension(bytes, mimeType);
    final path =
        '$userId/${prefix}_${DateTime.now().microsecondsSinceEpoch}.$extension';
    await client.storage
        .from(bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: true),
        );
    return path;
  }

  Future<String> uploadCourseCover({
    required String courseId,
    required String userId,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final extension = _validatedImageExtension(bytes, mimeType);
    final path =
        '$userId/course_covers/$courseId/cover_${DateTime.now().microsecondsSinceEpoch}.$extension';
    await client.storage
        .from(bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: true),
        );
    return path;
  }

  Future<String> signedAvatarUrl(String path) =>
      client.storage.from(bucket).createSignedUrl(path, 60 * 60);

  Future<String> signedCourseCoverUrl(String path) =>
      client.storage.from(bucket).createSignedUrl(path, 60 * 60);

  bool isCourseCoverPath(String path) {
    final parts = path.split('/');
    return parts.length == 4 &&
        _isUuid(parts[0]) &&
        parts[1] == 'course_covers' &&
        _isUuid(parts[2]) &&
        parts[3].isNotEmpty;
  }

  Future<void> removeAvatar(String path) async {
    await client.storage.from(bucket).remove([path]);
  }

  String? courseCoverPathFromUrl(String url) {
    if (url.contains('/course_covers/')) return url;
    final segments = Uri.tryParse(url)?.pathSegments;
    if (segments == null) return null;
    final bucketIndex = segments.indexOf('course-covers');
    if (bucketIndex == -1 || bucketIndex == segments.length - 1) return null;
    return 'course-covers:${segments.skip(bucketIndex + 1).join('/')}';
  }

  Future<void> removeCourseCover(String path) async {
    if (path.startsWith('course-covers:')) {
      await client.storage
          .from('course-covers')
          .remove([path.substring('course-covers:'.length)]);
      return;
    }
    await client.storage.from(bucket).remove([path]);
  }

  String _validatedImageExtension(Uint8List bytes, String mimeType) {
    if (bytes.isEmpty || bytes.length > maxAvatarBytes) {
      throw const StorageException('Images must be smaller than 2 MB.');
    }
    if (!allowedMimeTypes.values.contains(mimeType)) {
      throw const StorageException('Choose a JPG, PNG, or WebP image.');
    }
    if (!_matchesMime(bytes, mimeType)) {
      throw const StorageException(
        'The selected file does not match its image type.',
      );
    }
    return switch (mimeType) {
      'image/jpeg' => 'jpg',
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => throw const StorageException('Unsupported image format.'),
    };
  }

  bool _isUuid(String value) => RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  ).hasMatch(value);

  bool _matchesMime(Uint8List bytes, String mimeType) {
    bool at(int index, int value) =>
        index < bytes.length && bytes[index] == value;
    return switch (mimeType) {
      'image/jpeg' =>
        bytes.length >= 3 && at(0, 0xFF) && at(1, 0xD8) && at(2, 0xFF),
      'image/png' =>
        bytes.length >= 8 &&
            at(0, 0x89) &&
            at(1, 0x50) &&
            at(2, 0x4E) &&
            at(3, 0x47) &&
            at(4, 0x0D) &&
            at(5, 0x0A) &&
            at(6, 0x1A) &&
            at(7, 0x0A),
      'image/webp' =>
        bytes.length >= 12 &&
            String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
            String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP',
      _ => false,
    };
  }
}
