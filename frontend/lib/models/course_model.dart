enum CourseStatus {
  draft,
  submitted,
  published,
  rejected,
  unpublished,
  archived;

  static CourseStatus parse(Object? value, {bool isPublished = false}) =>
      CourseStatus.values.firstWhere(
        (status) => status.name == value,
        orElse: () => isPublished ? published : draft,
      );
}

class Course {
  const Course({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.level,
    required this.instructor,
    this.ownerId,
    this.status = CourseStatus.published,
    this.visibility = 'enrolled_students',
    this.coverImagePath,
    this.learningOutcomes = '',
    this.prerequisites = '',
    this.estimatedMinutes,
    this.createdAt,
    this.publishedAt,
  });

  final String id;
  final String title;
  final String description;
  final String category;
  final String level;
  final String instructor;
  final String? ownerId;
  final CourseStatus status;
  final String visibility;
  final String? coverImagePath;
  final String learningOutcomes;
  final String prerequisites;
  final int? estimatedMinutes;
  final DateTime? createdAt;
  final DateTime? publishedAt;

  bool get isPublished => status == CourseStatus.published;

  factory Course.fromJson(Map<String, dynamic> json) {
    final published = json['is_published'] == true;
    return Course(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      category: json['category'] as String? ?? 'General',
      level: json['level'] as String? ?? 'All levels',
      instructor: json['instructor'] as String? ?? 'SkillBridge lecturer',
      ownerId: json['owner_id'] as String?,
      status: CourseStatus.parse(json['status'], isPublished: published),
      visibility: json['visibility'] as String? ?? 'enrolled_students',
      coverImagePath: json['cover_image_path'] as String?,
      learningOutcomes: json['learning_outcomes'] as String? ?? '',
      prerequisites: json['prerequisites'] as String? ?? '',
      estimatedMinutes: (json['estimated_minutes'] as num?)?.toInt(),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      publishedAt: DateTime.tryParse(json['published_at'] as String? ?? ''),
    );
  }
}
