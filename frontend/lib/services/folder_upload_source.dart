import 'folder_upload_models.dart';
import 'folder_upload_source_stub.dart'
    if (dart.library.io) 'folder_upload_source_io.dart'
    if (dart.library.html) 'folder_upload_source_web.dart'
    as platform;

export 'folder_upload_models.dart';

Future<FolderUploadSelection?> pickFolderUpload() =>
    platform.pickFolderUpload();
