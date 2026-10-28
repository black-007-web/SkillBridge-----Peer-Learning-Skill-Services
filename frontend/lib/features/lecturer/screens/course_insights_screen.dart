import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/course_provider.dart';

class CourseInsightsScreen extends ConsumerStatefulWidget {
  const CourseInsightsScreen({super.key, required this.courseId});
  final String courseId;

  @override
  ConsumerState<CourseInsightsScreen> createState() =>
      _CourseInsightsScreenState();
}

class _CourseInsightsScreenState extends ConsumerState<CourseInsightsScreen> {
  late Future<Map<String, dynamic>> _insights;
  late Future<List<Map<String, dynamic>>> _roster;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final service = ref.read(courseServiceProvider)!;
    _insights = service.getLecturerCourseInsights(widget.courseId);
    _roster = service.getLecturerCourseRoster(widget.courseId);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Course insights')),
    body: RefreshIndicator(
      onRefresh: () async => setState(_load),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Course analytics',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          FutureBuilder<Map<String, dynamic>>(
            future: _insights,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LinearProgressIndicator();
              }
              if (snapshot.hasError) {
                return ListTile(
                  title: Text('Analytics unavailable: ${snapshot.error}'),
                );
              }
              final data = snapshot.data!;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _Metric(
                    label: 'Active learners',
                    value: data['active_enrollments'],
                  ),
                  _Metric(
                    label: 'Completed enrollments',
                    value: data['completed_enrollments'],
                  ),
                  _Metric(
                    label: 'Average rating',
                    value: data['average_rating'],
                  ),
                  _Metric(
                    label: 'Published reviews',
                    value: data['published_reviews'],
                  ),
                  _Metric(label: 'Modules', value: data['module_count']),
                  _Metric(label: 'Lessons', value: data['lesson_count']),
                  _Metric(label: 'Resources', value: data['resource_count']),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          Text(
            'Enrolled students',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _roster,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: LinearProgressIndicator(),
                );
              }
              if (snapshot.hasError) {
                return ListTile(
                  title: Text('Student list unavailable: ${snapshot.error}'),
                );
              }
              final students = snapshot.data!;
              if (students.isEmpty) {
                return const ListTile(title: Text('No active learners yet.'));
              }
              return Column(
                children: students
                    .map(
                      (student) => ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.person_outline),
                        ),
                        title: Text(
                          (student['full_name'] as String?)?.isNotEmpty == true
                              ? student['full_name'] as String
                              : 'SkillBridge student',
                        ),
                        subtitle: Text(
                          'Enrolled ${_date(student['enrolled_at'] as String?)}',
                        ),
                        trailing: Text('${student['enrollment_status']}'),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    ),
  );

  String _date(String? value) {
    final date = DateTime.tryParse(value ?? '')?.toLocal();
    if (date == null) return 'recently';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final Object? value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 165,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$value', style: Theme.of(context).textTheme.headlineSmall),
            Text(label),
          ],
        ),
      ),
    ),
  );
}
