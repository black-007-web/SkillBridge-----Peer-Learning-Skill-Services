import 'dart:typed_data';

class FolderUploadFile {
  const FolderUploadFile({
    required this.relativePath,
    required this.readBytes,
    this.size,
    this.mimeType,
  });

  final String relativePath;
  final Future<Uint8List> Function() readBytes;
  final int? size;
  final String? mimeType;

  String get name => relativePath.replaceAll('\\', '/').split('/').last;
}

class FolderUploadSelection {
  const FolderUploadSelection({
    required this.name,
    required this.files,
    this.warning,
  });

  final String name;
  final List<FolderUploadFile> files;
  final String? warning;
}
