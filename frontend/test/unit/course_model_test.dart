import 'package:flutter_test/flutter_test.dart';
import 'package:skillbridge_mobile/models/course_model.dart';

void main() {
  test('parses a course row and defaults optional fields', () {
    final course = Course.fromJson({
      'id': 'course-id',
      'title': 'Learning Flutter',
    });

    expect(course.id, 'course-id');
    expect(course.title, 'Learning Flutter');
    expect(course.description, isEmpty);
    expect(course.category, 'General');
    expect(course.level, 'All levels');
    expect(course.instructor, 'SkillBridge lecturer');
    expect(course.status, CourseStatus.draft);
  });

  test('parses published lifecycle status', () {
    final course = Course.fromJson({
      'id': 'course-id',
      'title': 'Learning Flutter',
      'status': 'published',
      'is_published': true,
    });

    expect(course.status, CourseStatus.published);
    expect(course.isPublished, isTrue);
  });

  test('parses an optional cover image URL', () {
    final course = Course.fromJson({
      'id': 'course-id',
      'cover_image_path': 'https://images.example/course.jpg',
    });

    expect(course.coverImagePath, 'https://images.example/course.jpg');
  });
}
