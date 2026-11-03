import 'package:flutter_test/flutter_test.dart';
import 'package:skillbridge_mobile/services/resource_service.dart';

void main() {
  test('maps nested folder paths to their directory segments', () {
    expect(ResourceService.folderSegmentsForFile('Week 1/Lessons/intro.pdf'), [
      'Week 1',
      'Lessons',
    ]);
    expect(ResourceService.folderSegmentsForFile('intro.pdf'), isEmpty);
    expect(ResourceService.folderSegmentsForFile(r'Week 1\Lessons\intro.pdf'), [
      'Week 1',
      'Lessons',
    ]);
  });

  test('rejects folder paths that could escape the selected directory', () {
    expect(
      () => ResourceService.folderSegmentsForFile('../private.txt'),
      throwsArgumentError,
    );
    expect(
      () => ResourceService.folderSegmentsForFile('Week/../private.txt'),
      throwsArgumentError,
    );
    expect(
      () => ResourceService.folderSegmentsForFile('/private.txt'),
      throwsArgumentError,
    );
    expect(
      () => ResourceService.folderSegmentsForFile(r'C:\private.txt'),
      throwsArgumentError,
    );
  });

  test('finds every nested folder when deleting a folder tree', () {
    final folders = [
      {'id': 'root', 'parent_id': null},
      {'id': 'sibling', 'parent_id': null},
      {'id': 'child', 'parent_id': 'root'},
      {'id': 'grandchild', 'parent_id': 'child'},
      {'id': 'sibling-child', 'parent_id': 'sibling'},
    ];

    expect(ResourceService.folderIdsForDeletion('root', folders).toSet(), {
      'root',
      'child',
      'grandchild',
    });
    expect(
      () => ResourceService.folderIdsForDeletion('missing', folders),
      throwsStateError,
    );
  });

  test('supports common image, media, code, and document file types', () {
    expect(ResourceService.mimeTypeForFile('photo.avif'), 'image/avif');
    expect(ResourceService.mimeTypeForFile('lesson.mp3'), 'audio/mpeg');
    expect(ResourceService.mimeTypeForFile('lecture.mkv'), 'video/x-matroska');
    expect(ResourceService.mimeTypeForFile('data.csv'), 'text/csv');
    expect(ResourceService.mimeTypeForFile('script.py'), 'text/x-python');
    expect(
      ResourceService.mimeTypeForFile('slides.pptx'),
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    );
  });

  test(
    'uses safe inline types for source files and generic unknown formats',
    () {
      expect(ResourceService.mimeTypeForFile('course-data.csv'), 'text/csv');
      expect(
        ResourceService.mimeTypeForFile('unknown.custom'),
        'application/octet-stream',
      );
      expect(ResourceService.mimeTypeForFile('page.html'), 'text/plain');
      expect(ResourceService.mimeTypeForFile('vector.svg'), 'text/plain');
      expect(ResourceService.mimeTypeForFile('page.htm'), 'text/plain');
      expect(
        ResourceService.mimeTypeForFile(
          'page.html',
          detectedMimeType: 'text/html',
        ),
        'text/plain',
      );
      expect(
        ResourceService.mimeTypeForFile(
          'vector.svg',
          detectedMimeType: 'image/svg+xml',
        ),
        'text/plain',
      );
      expect(
        ResourceService.mimeTypeForFile(
          'custom.dat',
          detectedMimeType: 'application/x-course-format',
        ),
        'application/x-course-format',
      );
    },
  );

  test('allows empty files while enforcing the per-file size limit', () {
    expect(() => ResourceService.validateFileSize(0), returnsNormally);
    expect(
      () => ResourceService.validateFileSize(ResourceService.maxFileBytes),
      returnsNormally,
    );
    expect(
      () => ResourceService.validateFileSize(ResourceService.maxFileBytes + 1),
      throwsA(isA<Exception>()),
    );
    expect(
      () => ResourceService.validateFileSize(null),
      throwsA(isA<Exception>()),
    );
  });
}
