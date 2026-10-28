import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../models/course_model.dart';
import '../../../providers/course_provider.dart';

class LecturerDashboard extends ConsumerWidget {
  const LecturerDashboard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courses = ref.watch(myCoursesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lecturer workspace'),
        actions: [
          IconButton(
            tooltip: 'Announcements',
            onPressed: () => context.push('/announcements'),
            icon: const Icon(Icons.campaign_outlined),
          ),
          IconButton(
            onPressed: () => ref.invalidate(myCoursesProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/lecturer/courses/new');
          ref.invalidate(myCoursesProvider);
        },
        icon: const Icon(Icons.add),
        label: const Text('New course'),
      ),
      body: courses.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not load your courses: $error'),
          ),
        ),
        data: (items) => items.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(30),
                  child: Text(
                    'Your course workspace is empty. Create a draft to get started.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Your courses',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  ...items.map(
                    (course) => _CourseCard(
                      course: course,
                      onChanged: () => ref.invalidate(myCoursesProvider),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _CourseCard extends ConsumerWidget {
  const _CourseCard({required this.course, required this.onChanged});
  final Course course;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editable = {
      CourseStatus.draft,
      CourseStatus.rejected,
      CourseStatus.unpublished,
    }.contains(course.status);
    final detailsEditable = editable || course.status == CourseStatus.published;
    return Card(
      child: ListTile(
        title: Text(course.title),
        subtitle: Text(
          '${course.category} · ${course.level} · ${course.status.name.toUpperCase()}',
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: (action) async {
            final service = ref.read(courseServiceProvider);
            final router = GoRouter.of(context);
            try {
              if (action == 'edit') {
                await router.push('/lecturer/courses/${course.id}/edit');
              }
              if (action == 'content') {
                await router.push('/lecturer/courses/${course.id}/content');
              }
              if (action == 'reviews') {
                await router.push('/lecturer/courses/${course.id}/reviews');
              }
              if (action == 'insights') {
                await router.push('/lecturer/courses/${course.id}/insights');
              }
              if (action == 'submit') await service?.submitCourse(course.id);
              if (action == 'unpublish') {
                await service?.setOwnedCourseStatus(
                  course.id,
                  CourseStatus.unpublished,
                );
              }
              if (action == 'archive') {
                await service?.setOwnedCourseStatus(
                  course.id,
                  CourseStatus.archived,
                );
              }
              onChanged();
            } catch (error) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Action failed: $error')),
                );
              }
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'content',
              child: Text('Course content'),
            ),
            const PopupMenuItem(
              value: 'reviews',
              child: Text('Student reviews'),
            ),
            const PopupMenuItem(
              value: 'insights',
              child: Text('Analytics and students'),
            ),
            if (detailsEditable)
              const PopupMenuItem(
                value: 'edit',
                child: Text('Edit course details'),
              ),
            if (editable)
              const PopupMenuItem(
                value: 'submit',
                child: Text('Submit for review'),
              ),
            if (course.status == CourseStatus.published)
              const PopupMenuItem(value: 'unpublish', child: Text('Unpublish')),
            if ({
              CourseStatus.unpublished,
              CourseStatus.published,
            }.contains(course.status))
              const PopupMenuItem(value: 'archive', child: Text('Archive')),
          ],
        ),
        onTap: detailsEditable
            ? () => context.push('/lecturer/courses/${course.id}/edit')
            : null,
      ),
    );
  }
}
