import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/course_provider.dart';

class CourseReviewsScreen extends ConsumerStatefulWidget {
  const CourseReviewsScreen({super.key, required this.courseId});
  final String courseId;

  @override
  ConsumerState<CourseReviewsScreen> createState() =>
      _CourseReviewsScreenState();
}

class _CourseReviewsScreenState extends ConsumerState<CourseReviewsScreen> {
  late Future<List<Map<String, dynamic>>> _reviews;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _reviews = ref
        .read(courseServiceProvider)!
        .getOwnedCourseReviews(widget.courseId);
  }

  Future<void> _reply(Map<String, dynamic> review) async {
    final controller = TextEditingController(
      text: review['lecturer_response'] as String? ?? '',
    );
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reply to review'),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 8,
          maxLength: 2000,
          decoration: const InputDecoration(labelText: 'Your response'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save reply'),
          ),
        ],
      ),
    );
    if (save == true) {
      try {
        await ref
            .read(courseServiceProvider)!
            .respondToReview(review['id'] as String, controller.text);
        if (mounted) {
          setState(_load);
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not save reply: $error')),
          );
        }
      }
    }
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Course reviews')),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _reviews,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Reviews could not be loaded: ${snapshot.error}'),
            ),
          );
        }
        final reviews = snapshot.data!;
        if (reviews.isEmpty) {
          return const Center(child: Text('No reviews for this course yet.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: reviews.length,
          itemBuilder: (context, index) {
            final review = reviews[index];
            final reply = review['lecturer_response'] as String?;
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '★ ${review['rating']} / 5',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text('${review['comment']}'),
                    if (reply != null && reply.isNotEmpty) ...[
                      const Divider(height: 24),
                      Text(
                        'Your reply',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      Text(reply),
                    ],
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => _reply(review),
                        icon: const Icon(Icons.reply),
                        label: Text(
                          reply == null || reply.isEmpty
                              ? 'Reply'
                              : 'Edit reply',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ),
  );
}
