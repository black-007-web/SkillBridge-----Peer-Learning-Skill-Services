import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'folder_upload_models.dart';

Future<FolderUploadSelection?> pickFolderUpload() {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..multiple = true
    ..style.display = 'none';
  input.setAttribute('webkitdirectory', '');
  input.setAttribute('directory', '');
  web.document.body?.append(input);

  final completer = Completer<FolderUploadSelection?>();
  var finishing = false;
  late JSFunction onChange;
  late JSFunction onCancel;

  void cleanup() {
    input.removeEventListener('change', onChange);
    input.removeEventListener('cancel', onCancel);
    input.remove();
  }

  Future<void> complete(web.FileList? selectedFiles) async {
    if (finishing) return;
    finishing = true;
    cleanup();

    if (selectedFiles == null || selectedFiles.length == 0) {
      completer.complete(null);
      return;
    }

    try {
      final files = <FolderUploadFile>[];
      String? folderName;
      var missingRelativePaths = false;
      for (var index = 0; index < selectedFiles.length; index++) {
        final file = selectedFiles.item(index);
        if (file == null) continue;

        final path = file.webkitRelativePath.replaceAll('\\', '/');
        final segments = path.split('/').where((part) => part.isNotEmpty);
        final parts = segments.toList(growable: false);
        if (parts.length < 2) {
          missingRelativePaths = true;
          folderName ??= 'Selected folder';
          files.add(
            FolderUploadFile(
              relativePath: file.name,
              size: file.size,
              mimeType: file.type,
              readBytes: () => _readBytes(file),
            ),
          );
          continue;
        }

        folderName ??= parts.first;
        files.add(
          FolderUploadFile(
            relativePath: parts.skip(1).join('/'),
            size: file.size,
            mimeType: file.type,
            readBytes: () => _readBytes(file),
          ),
        );
      }
      files.sort((a, b) => a.relativePath.compareTo(b.relativePath));
      completer.complete(
        FolderUploadSelection(
          name: folderName ?? 'Selected folder',
          files: files,
          warning: missingRelativePaths
              ? 'Your browser did not provide the selected folder structure. '
                    'Use a current version of Chrome, Edge, or Safari and try again.'
              : null,
        ),
      );
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    }
  }

  onChange = ((web.Event _) {
    unawaited(complete(input.files));
  }).toJS;
  onCancel = ((web.Event _) {
    unawaited(complete(null));
  }).toJS;
  input.addEventListener('change', onChange);
  input.addEventListener('cancel', onCancel);
  input.click();
  return completer.future;
}

Future<Uint8List> _readBytes(web.File file) async {
  final buffer = await file.arrayBuffer().toDart;
  return Uint8List.view(buffer.toDart);
}
