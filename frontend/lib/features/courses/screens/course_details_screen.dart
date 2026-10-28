import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/course_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/course_provider.dart';
import '../../../services/course_service.dart';
import '../../../services/resource_service.dart';
import '../../home/explore_catalog_widgets.dart';

class CourseDetailsScreen extends ConsumerStatefulWidget {
  const CourseDetailsScreen({super.key, required this.courseId});
  final String courseId;
  @override
  ConsumerState<CourseDetailsScreen> createState() =>
      _CourseDetailsScreenState();
}

class _CourseDetailsScreenState extends ConsumerState<CourseDetailsScreen> {
  late Future<Course?> _course;
  bool _enrolled = false;
  bool _busy = false;
  CourseService? get _courses => ref.read(courseServiceProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final client = ref.read(supabaseClientProvider);
    if (client == null) {
      _course = Future.value(null);
      return;
    }
    final service = CourseService(client: client);
    _course = service.getCourse(widget.courseId);
    service
        .getEnrolledCourseIds()
        .then((ids) {
          if (mounted) {
            setState(() => _enrolled = ids.contains(widget.courseId));
          }
        })
        .catchError((_) {});
  }

  Future<void> _enroll() async {
    final client = ref.read(supabaseClientProvider);
    final user = client?.auth.currentUser;
    if (client == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connect Supabase to enroll.')),
      );
      return;
    }
    if (user == null) {
      final next = Uri.encodeQueryComponent('/courses/${widget.courseId}');
      await context.push('/login?next=$next');
      return;
    }
    if (user.emailConfirmedAt == null &&
        user.appMetadata['provider'] == 'email') {
      await context.push(
        '/check-email?email=${Uri.encodeQueryComponent(user.email ?? '')}',
      );
      return;
    }

    setState(() => _busy = true);
    try {
      await _courses!.enroll(widget.courseId);
      if (mounted) setState(() => _enrolled = true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Enrollment failed: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review() async {
    final comment = TextEditingController();
    var rating = 5;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Rate this course'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Rating: $rating / 5'),
              Slider(
                value: rating.toDouble(),
                min: 1,
                max: 5,
                divisions: 4,
                onChanged: (v) => update(() => rating = v.round()),
              ),
              TextField(
                controller: comment,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Written review'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (save == true) {
      try {
        await _courses!.saveReview(
          courseId: widget.courseId,
          rating: rating,
          comment: comment.text,
        );
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Review saved.')));
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not save review: $error')),
          );
        }
      }
    }
    comment.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Course details')),
    body: FutureBuilder<Course?>(
      future: _course,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Course details are unavailable: ${snapshot.error}'),
            ),
          );
        }
        final course = snapshot.data;
        if (course == null) {
          return const Center(child: Text('Course not found.'));
        }
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                height: 220,
                child: CourseArtwork(
                  course: course,
                  storageService: ref.read(storageServiceProvider),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              course.category.toUpperCase(),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Text(
              course.title,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text('${course.level} · ${course.instructor}'),
            const SizedBox(height: 18),
            Text(course.description),
            if (course.learningOutcomes.trim().isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                'Learning outcomes',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(course.learningOutcomes),
            ],
            if (course.prerequisites.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Prerequisites',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(course.prerequisites),
            ],
            const SizedBox(height: 20),
            if (_enrolled)
              OutlinedButton.icon(
                onPressed: _review,
                icon: const Icon(Icons.star_outline),
                label: const Text('Write or update review'),
              )
            else
              FilledButton(
                onPressed: _busy ? null : _enroll,
                child: Text(_busy ? 'Enrolling...' : 'Enroll in this course'),
              ),
            const SizedBox(height: 22),
            Text(
              'Course content',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            _ContentList(courseId: course.id, enrolled: _enrolled),
            const SizedBox(height: 22),
            _CourseReviews(courseId: course.id),
          ],
        );
      },
    ),
  );
}

class _CourseReviews extends ConsumerWidget {
  const _CourseReviews({required this.courseId});
  final String courseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(courseServiceProvider);
    if (service == null) return const SizedBox.shrink();
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: service.getReviews(courseId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LinearProgressIndicator();
        }
        if (snapshot.hasError) {
          return const ListTile(title: Text('Reviews are unavailable.'));
        }
        final reviews = snapshot.data!;
        final userId = ref.read(supabaseClientProvider)?.auth.currentUser?.id;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reviews', style: Theme.of(context).textTheme.titleLarge),
            FutureBuilder<Map<String, dynamic>>(
              future: service.getReviewSummary(courseId),
              builder: (context, summary) {
                final rating =
                    (summary.data?['average'] as num?)?.toDouble() ?? 0;
                final count = (summary.data?['count'] as num?)?.toInt() ?? 0;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.star_rounded),
                  title: Text(
                    count == 0
                        ? 'No ratings yet'
                        : '${rating.toStringAsFixed(1)} / 5',
                  ),
                  subtitle: Text('$count published reviews'),
                );
              },
            ),
            if (reviews.isEmpty)
              const Text('Be the first enrolled student to share feedback.'),
            ...reviews.map(
              (review) => Card(
                child: ListTile(
                  title: Text('★ ${review['rating']} / 5'),
                  subtitle: Text('${review['comment']}'),
                  trailing: userId != null && userId != review['student_id']
                      ? IconButton(
                          tooltip: 'Report review',
                          onPressed: () => _report(context, service, review),
                          icon: const Icon(Icons.flag_outlined),
                        )
                      : null,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _report(
    BuildContext context,
    CourseService service,
    Map<String, dynamic> review,
  ) async {
    final reason = TextEditingController();
    final submit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Report this review'),
        content: TextField(
          controller: reason,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Why should an admin review it?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Submit report'),
          ),
        ],
      ),
    );
    if (submit == true) {
      try {
        await service.reportReview(review['id'] as String, reason.text);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Report sent to the admin team.')),
          );
        }
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not report review: $error')),
          );
        }
      }
    }
    reason.dispose();
  }
}

class _ContentList extends ConsumerStatefulWidget {
  const _ContentList({required this.courseId, required this.enrolled});
  final String courseId;
  final bool enrolled;
  @override
  ConsumerState<_ContentList> createState() => _ContentListState();
}

class _ContentListState extends ConsumerState<_ContentList> {
  late ResourceService _resources;
  late Future<List<Map<String, dynamic>>> _modules;
  Future<Set<String>>? _completed;
  Future<Map<String, dynamic>>? _progress;

  @override
  void initState() {
    super.initState();
    final client = ref.read(supabaseClientProvider);
    if (client != null) {
      _resources = ResourceService(client);
      _modules = _resources.modules(widget.courseId);
      _refreshProgress();
    } else {
      _modules = Future.value(const []);
    }
  }

  void _refreshProgress() {
    final service = ref.read(courseServiceProvider);
    if (widget.enrolled && service != null) {
      _completed = service.getCompletedLessonIds(widget.courseId);
      _progress = service.getProgressSummary(widget.courseId);
    }
  }

  @override
  void didUpdateWidget(covariant _ContentList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enrolled != widget.enrolled) _refreshProgress();
    if (!oldWidget.enrolled && widget.enrolled) {
      _modules = _resources.modules(widget.courseId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(supabaseClientProvider);
    if (client == null) {
      return const Text('Sign in to view available lessons and resources.');
    }
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _modules,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LinearProgressIndicator();
        }
        if (snapshot.hasError) {
          return Text(
            widget.enrolled
                ? 'Content could not be loaded.'
                : 'Enroll or verify access to view restricted content.',
          );
        }
        if (snapshot.data!.isEmpty) {
          return Column(
            children: [
              ListTile(
                title: Text(
                  widget.enrolled
                      ? 'No course lessons have been added yet.'
                      : 'Enroll to view course lessons.',
                ),
              ),
              _progressIndicator(),
              _ResourcesList(
                courseId: widget.courseId,
                service: _resources,
                openResource: (resource) =>
                    _open(context, _resources, resource),
              ),
            ],
          );
        }
        return Column(
          children: [
            ...snapshot.data!.map(
              (module) => Card(
                child: ExpansionTile(
                  title: Text('${module['title']}'),
                  subtitle: Text('${module['description']}'),
                  children: [
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: _resources.lessons(module['id'] as String),
                      builder: (context, lessonSnapshot) {
                        if (lessonSnapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.all(12),
                            child: LinearProgressIndicator(),
                          );
                        }
                        if (lessonSnapshot.hasError) {
                          return const ListTile(
                            title: Text(
                              'Lessons are unavailable for this account.',
                            ),
                          );
                        }
                        return FutureBuilder<Set<String>>(
                          future: _completed,
                          builder: (context, progressSnapshot) => Column(
                            children: lessonSnapshot.data!.map((lesson) {
                              final id = lesson['id'] as String;
                              final done =
                                  progressSnapshot.data?.contains(id) ?? false;
                              return ListTile(
                                leading: widget.enrolled
                                    ? Checkbox(
                                        value: done,
                                        onChanged:
                                            progressSnapshot.connectionState ==
                                                ConnectionState.done
                                            ? (value) => _setLessonDone(
                                                id,
                                                value ?? false,
                                              )
                                            : null,
                                      )
                                    : const Icon(Icons.play_lesson_outlined),
                                title: Text('${lesson['title']}'),
                                subtitle: Text('${lesson['body']}'),
                                isThreeLine: true,
                              );
                            }).toList(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            _progressIndicator(),
            _ResourcesList(
              courseId: widget.courseId,
              service: _resources,
              openResource: (resource) => _open(context, _resources, resource),
            ),
          ],
        );
      },
    );
  }

  Widget _progressIndicator() {
    if (!widget.enrolled || _progress == null) return const SizedBox.shrink();
    return FutureBuilder<Map<String, dynamic>>(
      future: _progress,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final done = (snapshot.data!['completed'] as num).toInt();
        final total = (snapshot.data!['total'] as num).toInt();
        final percent = (snapshot.data!['percentage'] as num).toInt();
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your progress: $done of $total lessons ($percent%)'),
              const SizedBox(height: 6),
              LinearProgressIndicator(value: total == 0 ? 0 : done / total),
            ],
          ),
        );
      },
    );
  }

  Future<void> _setLessonDone(String id, bool completed) async {
    try {
      await ref.read(courseServiceProvider)!.setLessonCompleted(id, completed);
      if (mounted) setState(_refreshProgress);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update progress: $error')),
        );
      }
    }
  }

  Future<void> _open(
    BuildContext context,
    ResourceService service,
    Map<String, dynamic> resource,
  ) async {
    try {
      final link =
          resource['external_url'] as String? ??
          await service.signedUrl(resource['storage_path'] as String);
      final uri = Uri.tryParse(link);
      if (uri == null ||
          uri.scheme != 'https' ||
          !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('The resource could not be opened.');
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }
}

class _ResourcesList extends StatelessWidget {
  const _ResourcesList({
    required this.courseId,
    required this.service,
    required this.openResource,
  });
  final String courseId;
  final ResourceService service;
  final ValueChanged<Map<String, dynamic>> openResource;
  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<Map<String, dynamic>>>(
        future: service.resources(courseId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LinearProgressIndicator();
          }
          if (snapshot.hasError) {
            return const ListTile(
              title: Text('Resources are unavailable for this account.'),
            );
          }
          if (snapshot.data!.isEmpty) {
            return const ListTile(title: Text('No course resources yet.'));
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Resources',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              ...snapshot.data!.map(
                (resource) => ListTile(
                  leading: const Icon(Icons.attach_file),
                  title: Text('${resource['title']}'),
                  subtitle: Text('${resource['resource_type']}'),
                  onTap: () => openResource(resource),
                ),
              ),
            ],
          );
        },
      );
}
