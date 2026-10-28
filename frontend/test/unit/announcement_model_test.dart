import 'package:flutter_test/flutter_test.dart';
import 'package:skillbridge_mobile/models/announcement_model.dart';

void main() {
  test('parses a published announcement', () {
    final announcement = Announcement.fromJson({
      'id': 'announcement-id',
      'title': 'Campus update',
      'body': 'A new course is available.',
      'audience': 'students',
      'published_at': '2026-10-21T10:00:00Z',
      'expires_at': null,
    });

    expect(announcement.id, 'announcement-id');
    expect(announcement.title, 'Campus update');
    expect(announcement.audience, 'students');
    expect(announcement.publishedAt, DateTime.utc(2026, 10, 21, 10));
    expect(announcement.expiresAt, isNull);
  });
}
