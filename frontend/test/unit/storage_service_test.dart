import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:skillbridge_mobile/services/storage_service.dart';

void main() {
  test('allows avatar and cover images up to 5 MiB', () {
    expect(StorageService.maxAvatarBytes, 5 * 1024 * 1024);
  });

  test('maps supported image extensions to upload MIME types', () {
    expect(StorageService.mimeForFileName('portrait.jpeg'), 'image/jpeg');
    expect(StorageService.mimeForFileName('portrait.png'), 'image/png');
    expect(StorageService.mimeForFileName('portrait.webp'), 'image/webp');
    expect(StorageService.mimeForFileName('portrait.gif'), 'image/gif');
    expect(StorageService.mimeForFileName('portrait.bmp'), 'image/bmp');
    expect(StorageService.mimeForFileName('portrait.svg'), isNull);
  });

  test('validates image signatures before upload', () {
    expect(
      StorageService.validatedImageExtension(
        Uint8List.fromList([0x42, 0x4D]),
        'image/bmp',
      ),
      'bmp',
    );
    expect(
      StorageService.validatedImageExtension(
        Uint8List.fromList('GIF89a'.codeUnits),
        'image/gif',
      ),
      'gif',
    );
    expect(
      () => StorageService.validatedImageExtension(
        Uint8List.fromList([0x00, 0x00]),
        'image/png',
      ),
      throwsA(isA<Exception>()),
    );
    expect(
      () => StorageService.validatedImageExtension(
        Uint8List(5 * 1024 * 1024 + 1),
        'image/png',
      ),
      throwsA(isA<Exception>()),
    );
  });
}
