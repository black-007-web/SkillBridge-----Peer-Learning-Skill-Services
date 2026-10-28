import 'package:flutter_test/flutter_test.dart';
import 'package:skillbridge_mobile/models/user_profile.dart';

void main() {
  test('parses optional profile and professional details', () {
    final profile = UserProfile.fromJson({
      'id': 'user-id',
      'full_name': 'Amina Rahman',
      'created_at': '2026-10-27T00:00:00Z',
      'cover_image_url': 'lecturer-id/cover_1.webp',
      'phone_number': '+12345678900',
      'bio': 'Learning and teaching software development.',
      'social_links': {
        'github': 'https://github.com/amina',
        'linkedin': 'https://linkedin.com/in/amina',
        'invalid': 42,
      },
      'position': 'Software Engineering Lecturer',
      'skills': ['Flutter', 'Supabase'],
    });

    expect(profile.phoneNumber, '+12345678900');
    expect(profile.coverImagePath, 'lecturer-id/cover_1.webp');
    expect(profile.bio, 'Learning and teaching software development.');
    expect(profile.socialLinks, {
      'github': 'https://github.com/amina',
      'linkedin': 'https://linkedin.com/in/amina',
    });
    expect(profile.position, 'Software Engineering Lecturer');
    expect(profile.skills, ['Flutter', 'Supabase']);
  });

  test('defaults new profile fields for older database rows', () {
    final profile = UserProfile.fromJson({
      'id': 'user-id',
      'full_name': 'Amina Rahman',
    });

    expect(profile.bio, isEmpty);
    expect(profile.socialLinks, isEmpty);
    expect(profile.position, isEmpty);
    expect(profile.skills, isEmpty);
    expect(profile.coverImagePath, isNull);
  });
}
