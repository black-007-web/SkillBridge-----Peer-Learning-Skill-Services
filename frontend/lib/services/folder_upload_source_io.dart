import 'dart:io';

import 'package:file_picker/file_picker.dart';

import 'folder_upload_models.dart';

Future<FolderUploadSelection?> pickFolderUpload() async {
  final directoryPath = await FilePicker.getDirectoryPath(
    dialogTitle: 'Choose a course content folder',
  );
  if (directoryPath == null) return null;

  final directory = Directory(directoryPath);
  if (!await directory.exists()) {
    return _pickFilesFallback();
  }

  final files = <FolderUploadFile>[];
  try {
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final relativePath = entity.path
          .substring(directoryPath.length)
          .replaceAll('\\', '/')
          .replaceFirst(RegExp(r'^/+'), '');
      files.add(
        FolderUploadFile(
          relativePath: relativePath,
          size: await entity.length(),
          readBytes: entity.readAsBytes,
        ),
      );
    }
  } on FileSystemException {
    return _pickFilesFallback();
  }
  files.sort((a, b) => a.relativePath.compareTo(b.relativePath));

  final normalizedPath = directoryPath
      .replaceAll('\\', '/')
      .replaceFirst(RegExp(r'/+$'), '');
  final directoryName = normalizedPath.split('/').last;
  return FolderUploadSelection(name: directoryName, files: files);
}

Future<FolderUploadSelection?> _pickFilesFallback() async {
  final files = await FilePicker.pickFiles(
    dialogTitle: 'Folder access is unavailable; select course files',
    type: FileType.any,
  );
  if (files.isEmpty) return null;

  final selectedFiles = <FolderUploadFile>[];
  for (final file in files) {
    selectedFiles.add(
      FolderUploadFile(
        relativePath: file.name,
        size: file.lengthSync() ?? await file.length(),
        readBytes: file.readAsBytes,
      ),
    );
  }
  return FolderUploadSelection(
    name: 'Imported files',
    files: selectedFiles,
    warning:
        'The device did not allow direct folder access. The selected files '
        'will be uploaded without their nested folder structure.',
  );
}
