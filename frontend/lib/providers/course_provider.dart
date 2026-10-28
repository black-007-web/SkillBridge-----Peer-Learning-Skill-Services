
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/course_model.dart';
import '../services/course_service.dart';
import 'auth_provider.dart';

final courseServiceProvider = Provider<CourseService?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : CourseService(client: client);
});

final publishedCoursesProvider = FutureProvider.family<List<Course>, String>((
  ref,
  search,
) async {
  final service = ref.watch(courseServiceProvider);
  return service?.getCourses(search: search) ?? const [];
});

final myCoursesProvider = FutureProvider<List<Course>>((ref) async {
  final service = ref.watch(courseServiceProvider);
  return service?.getMyCourses() ?? const [];
});
