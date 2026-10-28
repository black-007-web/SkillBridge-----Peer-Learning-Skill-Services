import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/course_model.dart';

class CourseService {
  CourseService({this.client});

  final SupabaseClient? client;

  bool get isConnected => client != null;

  Future<List<Course>> getCourses({
    String search = '',
    String? category,
    String? level,
    double? minimumRating,
    int limit = 24,
    int offset = 0,
  }) async {
    final supabase = client;
    if (supabase == null) return const [];
    if (minimumRating != null) {
      final rows = await supabase.rpc(
        'discover_courses',
        params: {
          'p_search': search.trim(),
          'p_category': category,
          'p_level': level,
          'p_minimum_rating': minimumRating,
          'p_limit': limit,
          'p_offset': offset,
        },
      ) as List;
      return rows
          .map(
            (row) => Course.fromJson(
              Map<String, dynamic>.from(row['course'] as Map),
            ),
          )
          .toList(growable: false);
    }
    var query = supabase
        .from('courses')
        .select(
          'id,title,description,category,level,instructor,owner_id,status,visibility,cover_image_path,learning_outcomes,prerequisites,estimated_minutes,created_at,published_at,is_published',
        )
        .eq('status', 'published');
    if (category != null && category.isNotEmpty) {
      query = query.eq('category', category);
    }
    if (level != null && level.isNotEmpty) query = query.eq('level', level);
    final term = _escapeFilterText(search.trim());
    if (term.isNotEmpty) {
      query = query.or(
        'title.ilike.%$term%,description.ilike.%$term%,category.ilike.%$term%,instructor.ilike.%$term%',
      );
    }
    final rows = await query
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return rows
        .map((row) => Course.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<Course>> getLecturerCourses(String lecturerId) async {
    final supabase = client;
    if (supabase == null) return const [];
    if (lecturerId.trim().isEmpty) {
      throw ArgumentError.value(lecturerId, 'lecturerId', 'Must not be empty.');
    }
    final rows = await supabase
        .from('courses')
        .select(
          'id,title,description,category,level,instructor,owner_id,status,visibility,cover_image_path,learning_outcomes,prerequisites,estimated_minutes,created_at,published_at,is_published',
        )
        .eq('owner_id', lecturerId)
        .eq('status', 'published')
        .order('created_at', ascending: false)
        .limit(100);
    return rows
        .map((row) => Course.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<Course>> getMyCourses() async {
    final supabase = _requireSignedIn();
    final user = supabase.auth.currentUser!;
    final rows = await supabase
        .from('courses')
        .select(
          'id,title,description,category,level,instructor,owner_id,status,visibility,cover_image_path,learning_outcomes,prerequisites,estimated_minutes,created_at,published_at,is_published',
        )
        .eq('owner_id', user.id)
        .order('updated_at', ascending: false);
    return rows
        .map((row) => Course.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<Course?> getCourse(String id) async {
    final supabase = client;
    if (supabase == null) return null;
    final rows = await supabase
        .from('courses')
        .select(
          'id,title,description,category,level,instructor,owner_id,status,visibility,cover_image_path,learning_outcomes,prerequisites,estimated_minutes,created_at,published_at,is_published',
        )
        .eq('id', id)
        .maybeSingle();
    return rows == null
        ? null
        : Course.fromJson(Map<String, dynamic>.from(rows));
  }

  Future<Course> createCourse({
    required String title,
    required String description,
    required String category,
    required String level,
    required String learningOutcomes,
    required String prerequisites,
    required String visibility,
    int? estimatedMinutes,
    String? coverImagePath,
  }) async {
    final supabase = _requireSignedIn();
    final user = supabase.auth.currentUser!;
    final displayName = (user.userMetadata?['full_name'] as String?)?.trim();
    final row = await supabase
        .from('courses')
        .insert({
          'owner_id': user.id,
          'title': title.trim(),
          'description': description.trim(),
          'category': category.trim(),
          'level': level,
          'instructor': displayName?.isNotEmpty == true
              ? displayName
              : user.email ?? 'SkillBridge lecturer',
          'learning_outcomes': learningOutcomes.trim(),
          'prerequisites': prerequisites.trim(),
          'visibility': visibility,
          'estimated_minutes': estimatedMinutes,
          'cover_image_path': _normalizedCoverImageUrl(coverImagePath),
          'status': 'draft',
          'is_published': false,
        })
        .select(
          'id,title,description,category,level,instructor,owner_id,status,visibility,cover_image_path,learning_outcomes,prerequisites,estimated_minutes,created_at,published_at,is_published',
        )
        .single();
    return Course.fromJson(Map<String, dynamic>.from(row));
  }

  Future<Course> updateCourse({
    required String id,
    required String title,
    required String description,
    required String category,
    required String level,
    required String learningOutcomes,
    required String prerequisites,
    required String visibility,
    int? estimatedMinutes,
    String? coverImagePath,
  }) async {
    final supabase = _requireSignedIn();
    final row = await supabase
        .from('courses')
        .update({
          'title': title.trim(),
          'description': description.trim(),
          'category': category.trim(),
          'level': level,
          'learning_outcomes': learningOutcomes.trim(),
          'prerequisites': prerequisites.trim(),
          'visibility': visibility,
          'estimated_minutes': estimatedMinutes,
          'cover_image_path': _normalizedCoverImageUrl(coverImagePath),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .select(
          'id,title,description,category,level,instructor,owner_id,status,visibility,cover_image_path,learning_outcomes,prerequisites,estimated_minutes,created_at,published_at,is_published',
        )
        .single();
    return Course.fromJson(Map<String, dynamic>.from(row));
  }

  Future<void> submitCourse(String id) async {
    final supabase = _requireSignedIn();
    final current = await getCourse(id);
    if (current?.status == CourseStatus.rejected) {
      await supabase.from('courses').update({'status': 'draft'}).eq('id', id);
    }
    await supabase.from('courses').update({'status': 'submitted'}).eq('id', id);
  }

  Future<void> moderateCourse(String id, CourseStatus status) async {
    if (!{
      CourseStatus.published,
      CourseStatus.rejected,
      CourseStatus.unpublished,
      CourseStatus.archived,
    }.contains(status)) {
      throw ArgumentError.value(status, 'status', 'Invalid moderation status');
    }
    final supabase = _requireSignedIn();
    await supabase.from('courses').update({'status': status.name}).eq('id', id);
  }

  Future<void> setOwnedCourseStatus(String id, CourseStatus status) async {
    if (!{CourseStatus.unpublished, CourseStatus.archived}.contains(status)) {
      throw ArgumentError.value(
        status,
        'status',
        'Invalid lecturer status transition',
      );
    }
    final supabase = _requireSignedIn();
    await supabase.from('courses').update({'status': status.name}).eq('id', id);
  }

  Future<List<String>> getEnrolledCourseIds() async {
    final supabase = client;
    if (supabase == null || supabase.auth.currentUser == null) return const [];
    final rows = await supabase
        .from('enrollments')
        .select('course_id')
        .inFilter('status', ['active', 'completed']);
    return rows
        .map((row) => row['course_id'] as String)
        .toList(growable: false);
  }

  Future<List<Course>> getEnrolledCourses() async {
    final supabase = client;
    if (supabase == null || supabase.auth.currentUser == null) return const [];
    final enrollmentRows = await supabase
        .from('enrollments')
        .select('course_id')
        .inFilter('status', ['active', 'completed'])
        .order('enrolled_at', ascending: false);
    final courseIds = enrollmentRows
        .map((row) => row['course_id'] as String)
        .toList();
    if (courseIds.isEmpty) return const [];
    final courseRows = await supabase
        .from('courses')
        .select(
          'id,title,description,category,level,instructor,owner_id,status,visibility,cover_image_path,learning_outcomes,prerequisites,estimated_minutes,created_at,published_at,is_published',
        )
        .inFilter('id', courseIds);
    final byId = {
      for (final row in courseRows)
        row['id'] as String: Course.fromJson(Map<String, dynamic>.from(row)),
    };
    return [
      for (final id in courseIds)
        if (byId[id] != null) byId[id]!,
    ];
  }

  Future<void> enroll(String courseId) async {
    final supabase = _requireSignedIn();
    await supabase.from('enrollments').insert({
      'user_id': supabase.auth.currentUser!.id,
      'course_id': courseId,
      'status': 'active',
    });
  }

  Future<void> saveReview({
    required String courseId,
    required int rating,
    required String comment,
  }) async {
    if (rating < 1 || rating > 5 || comment.trim().length < 3) {
      throw ArgumentError(
        'Choose a 1–5 rating and write at least 3 characters.',
      );
    }
    final supabase = _requireSignedIn();
    final studentId = supabase.auth.currentUser!.id;
    final existing = await supabase
        .from('course_reviews')
        .select('id')
        .eq('course_id', courseId)
        .eq('student_id', studentId)
        .maybeSingle();
    if (existing == null) {
      await supabase.from('course_reviews').insert({
        'course_id': courseId,
        'student_id': studentId,
        'rating': rating,
        'comment': comment.trim(),
      });
    } else {
      await supabase
          .from('course_reviews')
          .update({'rating': rating, 'comment': comment.trim()})
          .eq('id', existing['id']);
    }
  }

  Future<List<Map<String, dynamic>>> getReviews(String courseId) async {
    final supabase = _requireSignedIn();
    final rows = await supabase
        .from('course_reviews')
        .select('id,student_id,rating,comment,lecturer_response,created_at')
        .eq('course_id', courseId)
        .eq('status', 'published')
        .order('created_at', ascending: false)
        .limit(50);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<Map<String, dynamic>> getReviewSummary(String courseId) async {
    final supabase = _requireSignedIn();
    final result = await supabase.rpc(
      'course_review_summary',
      params: {'p_course_id': courseId},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<void> reportReview(String reviewId, String reason) async {
    if (reason.trim().length < 5) {
      throw ArgumentError('Explain why this review should be checked.');
    }
    final supabase = _requireSignedIn();
    await supabase.rpc(
      'submit_course_review_report',
      params: {'p_review_id': reviewId, 'p_reason': reason.trim()},
    );
  }

  Future<void> setLessonCompleted(String lessonId, bool completed) async {
    await _requireSignedIn().rpc(
      'set_lesson_progress',
      params: {'p_lesson_id': lessonId, 'p_completed': completed},
    );
  }

  Future<Map<String, dynamic>> getProgressSummary(String courseId) async {
    final result = await _requireSignedIn().rpc(
      'course_progress_summary',
      params: {'p_course_id': courseId},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Set<String>> getCompletedLessonIds(String courseId) async {
    final result = await _requireSignedIn().rpc(
      'course_completed_lessons',
      params: {'p_course_id': courseId},
    );
    return (result as List).whereType<String>().toSet();
  }

  Future<void> respondToReview(String reviewId, String response) async {
    await _requireSignedIn().rpc(
      'lecturer_respond_to_course_review',
      params: {'p_review_id': reviewId, 'p_response': response.trim()},
    );
  }

  Future<List<Map<String, dynamic>>> getOwnedCourseReviews(
    String courseId,
  ) async {
    final rows = await _requireSignedIn()
        .from('course_reviews')
        .select(
          'id,course_id,student_id,rating,comment,status,lecturer_response,created_at',
        )
        .eq('course_id', courseId)
        .order('created_at', ascending: false);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<Map<String, dynamic>> getLecturerCourseInsights(
    String courseId,
  ) async {
    final result = await _requireSignedIn().rpc(
      'lecturer_course_insights',
      params: {'p_course_id': courseId},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<Map<String, dynamic>>> getLecturerCourseRoster(
    String courseId,
  ) async {
    final rows = await _requireSignedIn().rpc(
      'lecturer_course_roster',
      params: {'p_course_id': courseId},
    );
    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  SupabaseClient _requireSignedIn() {
    final supabase = client;
    if (supabase == null) {
      throw StateError('Connect Supabase before using courses.');
    }
    if (supabase.auth.currentUser == null) {
      throw const AuthException('Sign in before using courses.');
    }
    return supabase;
  }

  String _escapeFilterText(String input) => input
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_')
      .replaceAll(',', r'\,')
      .replaceAll('(', r'\(')
      .replaceAll(')', r'\)');

  String? _normalizedCoverImageUrl(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}
