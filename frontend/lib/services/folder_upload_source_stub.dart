import 'package:file_picker/file_picker.dart';

import 'folder_upload_models.dart';

Future<FolderUploadSelection?> pickFolderUpload() async {
  final files = await FilePicker.pickFiles(
    dialogTitle: 'Select course content files',
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
        'This platform selects multiple files rather than whole folders, so '
        'the selected files will be uploaded without nested folder structure.',
  );
}
