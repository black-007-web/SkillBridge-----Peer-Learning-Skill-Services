import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../providers/auth_provider.dart';
import '../../../services/role_admin_service.dart';

class AdminDashboard extends ConsumerStatefulWidget {
  const AdminDashboard({super.key});
  @override
  ConsumerState<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends ConsumerState<AdminDashboard> {
  late Future<_AdminData> _data;
  final _search = TextEditingController();
  late Future<List<Map<String, dynamic>>> _users;
  RoleAdminService? get _service {
    final client = ref.read(supabaseClientProvider);
    return client == null ? null : RoleAdminService(client);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _load() {
    final service = _service;
    _users =
        service?.users(search: _search.text) ??
        Future.error(StateError('Connect Supabase to manage users.'));
    _data = service == null
        ? Future.error(StateError('Connect Supabase to manage SkillBridge.'))
        : Future.wait([
            service.metrics(),
            service.pending('student_verification_requests'),
            service.pending('lecturer_applications'),
            service.submittedCourses(),
            service.openTickets(),
            service.recentAudit(),
            service.openReviewReports(),
          ]).then(
            (values) => _AdminData(
              values[0] as Map<String, dynamic>,
              values[1] as List<Map<String, dynamic>>,
              values[2] as List<Map<String, dynamic>>,
              values[3] as List<Map<String, dynamic>>,
              values[4] as List<Map<String, dynamic>>,
              values[5] as List<Map<String, dynamic>>,
              values[6] as List<Map<String, dynamic>>,
            ),
          );
  }

  Future<void> _decide(
    String table,
    Map<String, dynamic> row,
    String status,
  ) async {
    final reason = TextEditingController();
    if (status == 'rejected') {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Reason for rejection'),
          content: TextField(
            controller: reason,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Explain what the applicant should address',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Reject'),
            ),
          ],
        ),
      );
      if (accepted != true) return;
    } else {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Approve request?'),
          content: Text(
            'This will grant the user the approved ${table == 'lecturer_applications' ? 'lecturer' : 'student'} workflow permissions.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Approve'),
            ),
          ],
        ),
      );
      if (accepted != true) return;
    }
    try {
      await _service!.decide(
        table,
        row['id'] as String,
        status,
        reason: reason.text,
      );
      if (mounted) setState(_load);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _moderateCourse(Map<String, dynamic> row, String status) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          status == 'published' ? 'Publish course?' : 'Reject course?',
        ),
        content: Text('"${row['title']}" will be marked $status.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(status == 'published' ? 'Publish' : 'Reject'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    try {
      await _service!.setCourseStatus(row['id'] as String, status);
      if (mounted) setState(_load);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _changeRole(
    Map<String, dynamic> user,
    String role,
    bool grant,
  ) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${grant ? 'Grant' : 'Revoke'} $role role?'),
        content: Text(
          '${user['email']} will ${grant ? 'receive' : 'lose'} the $role role. This is recorded in the audit history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(grant ? 'Grant role' : 'Revoke role'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    try {
      await _service!.assignRole(
        user['user_id'] as String,
        role,
        grant,
        reason: 'Admin dashboard role management',
      );
      if (mounted) setState(_load);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _changeAccountStatus(
    Map<String, dynamic> user,
    String status,
  ) async {
    final reason = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          '${status == 'active' ? 'Restore' : 'Set'} account ${status == 'active' ? 'access' : 'status'}?',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${user['email']} will be marked $status.'),
            TextField(
              controller: reason,
              decoration: const InputDecoration(labelText: 'Reason'),
              maxLength: 500,
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
            child: Text(status == 'active' ? 'Restore' : status),
          ),
        ],
      ),
    );
    if (accepted == true) {
      try {
        await _service!.setAccountStatus(
          user['user_id'] as String,
          status,
          reason: reason.text,
        );
        if (mounted) setState(_load);
      } catch (error) {
        _showError(error);
      }
    }
    reason.dispose();
  }

  Future<void> _composeAnnouncement() async {
    final form = GlobalKey<FormState>();
    final title = TextEditingController();
    final body = TextEditingController();
    var audience = 'everyone';
    final publish = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Publish announcement'),
          content: SizedBox(
            width: 480,
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: title,
                    decoration: const InputDecoration(labelText: 'Title'),
                    validator: (v) => (v?.trim().length ?? 0) < 3
                        ? 'Enter at least 3 characters.'
                        : null,
                  ),
                  TextFormField(
                    controller: body,
                    decoration: const InputDecoration(labelText: 'Message'),
                    minLines: 3,
                    maxLines: 6,
                    validator: (v) =>
                        (v?.trim().length ?? 0) < 3 ? 'Enter a message.' : null,
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: audience,
                    decoration: const InputDecoration(labelText: 'Audience'),
                    items: const [
                      DropdownMenuItem(
                        value: 'everyone',
                        child: Text('Everyone'),
                      ),
                      DropdownMenuItem(
                        value: 'students',
                        child: Text('Students'),
                      ),
                      DropdownMenuItem(
                        value: 'lecturers',
                        child: Text('Lecturers'),
                      ),
                    ],
                    onChanged: (value) =>
                        update(() => audience = value ?? 'everyone'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) Navigator.pop(context, true);
              },
              child: const Text('Publish'),
            ),
          ],
        ),
      ),
    );
    if (publish == true) {
      try {
        final count = await _service!.publishAnnouncement(
          title: title.text,
          body: body.text,
          audience: audience,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Announcement delivered to $count users.')),
          );
        }
      } catch (error) {
        _showError(error);
      }
    }
    title.dispose();
    body.dispose();
  }

  Future<void> _resolveTicket(Map<String, dynamic> ticket) async {
    final resolution = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Resolve: ${ticket['subject']}'),
        content: TextField(
          controller: resolution,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Resolution notes'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Resolve ticket'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _service!.resolveTicket(ticket['id'] as String, resolution.text);
        if (mounted) setState(_load);
      } catch (error) {
        _showError(error);
      }
    }
    resolution.dispose();
  }

  Future<void> _resolveReviewReport(
    Map<String, dynamic> report,
    bool hideReview,
  ) async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(hideReview ? 'Hide reported review?' : 'Dismiss report?'),
        content: TextField(
          controller: reason,
          decoration: const InputDecoration(labelText: 'Moderation notes'),
          maxLength: 500,
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(hideReview ? 'Hide review' : 'Dismiss'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _service!.resolveReviewReport(
          report['id'] as String,
          hideReview: hideReview,
          reason: reason.text,
        );
        if (mounted) setState(_load);
      } catch (error) {
        _showError(error);
      }
    }
    reason.dispose();
  }

  void _showError(Object error) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Action failed: $error')));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Admin dashboard'),
      actions: [
        IconButton(
          tooltip: 'View announcements',
          onPressed: () => context.push('/announcements'),
          icon: const Icon(Icons.campaign_outlined),
        ),
        IconButton(
          tooltip: 'Publish announcement',
          onPressed: _composeAnnouncement,
          icon: const Icon(Icons.campaign_outlined),
        ),
        IconButton(
          onPressed: () => setState(_load),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<_AdminData>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _Failure(
            message: '${snapshot.error}',
            retry: () => setState(_load),
          );
        }
        final data = snapshot.requireData;
        return RefreshIndicator(
          onRefresh: () async => setState(_load),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Platform overview',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: data.metrics.entries
                    .map(
                      (e) => _Metric(label: _label(e.key), value: '${e.value}'),
                    )
                    .toList(),
              ),
              const SizedBox(height: 26),
              _section(
                'Student verification',
                data.students,
                'student_verification_requests',
                (row) =>
                    '${row['student_number']} · ${row['department']} / ${row['program']}',
              ),
              _section(
                'Lecturer applications',
                data.lecturers,
                'lecturer_applications',
                (row) => '${row['department']} · ${row['qualifications']}',
              ),
              const SizedBox(height: 22),
              Text('User roles', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              TextField(
                controller: _search,
                decoration: InputDecoration(
                  labelText: 'Search by name or email',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    onPressed: () => setState(_load),
                    icon: const Icon(Icons.arrow_forward),
                  ),
                ),
                onSubmitted: (_) => setState(_load),
              ),
              const SizedBox(height: 8),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _users,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: LinearProgressIndicator(),
                    );
                  }
                  if (snapshot.hasError) {
                    return ListTile(
                      title: Text('Could not load users: ${snapshot.error}'),
                    );
                  }
                  return Column(
                    children: snapshot.requireData.map((user) {
                      final roles = (user['roles'] as List? ?? const [])
                          .cast<String>();
                      final accountStatus =
                          user['account_status'] as String? ?? 'active';
                      return Card(
                        child: ListTile(
                          title: Text('${user['full_name'] ?? 'Unnamed user'}'),
                          subtitle: Text(
                            '${user['email']}\nRoles: ${roles.isEmpty ? 'none' : roles.join(', ')} · $accountStatus',
                          ),
                          isThreeLine: true,
                          trailing: PopupMenuButton<String>(
                            tooltip: 'Manage account',
                            onSelected: (value) {
                              if (value.startsWith('role:')) {
                                final role = value.substring(5);
                                _changeRole(user, role, !roles.contains(role));
                              } else {
                                _changeAccountStatus(user, value.substring(7));
                              }
                            },
                            itemBuilder: (_) => [
                              ...['student', 'lecturer', 'admin'].map(
                                (role) => PopupMenuItem(
                                  value: 'role:$role',
                                  child: Text(
                                    '${roles.contains(role) ? 'Remove' : 'Grant'} $role',
                                  ),
                                ),
                              ),
                              if (accountStatus == 'active')
                                const PopupMenuItem(
                                  value: 'status:suspended',
                                  child: Text('Suspend account'),
                                ),
                              if (accountStatus != 'active')
                                const PopupMenuItem(
                                  value: 'status:active',
                                  child: Text('Restore account'),
                                ),
                              if (accountStatus != 'deactivated')
                                const PopupMenuItem(
                                  value: 'status:deactivated',
                                  child: Text('Deactivate account'),
                                ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              Text(
                'Courses awaiting review',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (data.courses.isEmpty)
                const ListTile(
                  title: Text('No courses are waiting for review.'),
                ),
              ...data.courses.map(
                (row) => Card(
                  child: ListTile(
                    title: Text('${row['title']}'),
                    subtitle: Text(
                      '${row['category']} · ${row['level']} · ${row['instructor']}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Reject',
                          onPressed: () => _moderateCourse(row, 'rejected'),
                          icon: const Icon(Icons.close),
                        ),
                        IconButton(
                          tooltip: 'Publish',
                          onPressed: () => _moderateCourse(row, 'published'),
                          icon: const Icon(Icons.check_circle_outline),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Open support tickets',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (data.tickets.isEmpty)
                const ListTile(title: Text('No open support tickets.')),
              ...data.tickets.map(
                (ticket) => Card(
                  child: ListTile(
                    title: Text('${ticket['subject']}'),
                    subtitle: Text(
                      '${ticket['category']} · ${ticket['priority']}\n${ticket['description']}',
                    ),
                    isThreeLine: true,
                    trailing: IconButton(
                      tooltip: 'Resolve ticket',
                      onPressed: () => _resolveTicket(ticket),
                      icon: const Icon(Icons.check_circle_outline),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Recent audit events',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (data.audit.isEmpty)
                const ListTile(title: Text('No audited activity yet.')),
              ...data.audit.map(
                (event) => ListTile(
                  leading: const Icon(Icons.history),
                  title: Text('${event['action']}'),
                  subtitle: Text(
                    '${event['target_type']} ${event['target_id']} · ${event['created_at']}',
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Reported reviews',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (data.reviewReports.isEmpty)
                const ListTile(
                  title: Text(
                    'No reported reviews are waiting for moderation.',
                  ),
                ),
              ...data.reviewReports.map((report) {
                final review = Map<String, dynamic>.from(
                  report['course_reviews'] as Map? ?? const {},
                );
                return Card(
                  child: ListTile(
                    title: Text(
                      'Rating ${review['rating'] ?? '?'} · Course ${review['course_id'] ?? ''}',
                    ),
                    subtitle: Text(
                      '${report['reason']}\n${review['comment'] ?? ''}',
                    ),
                    isThreeLine: true,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Dismiss report',
                          onPressed: () => _resolveReviewReport(report, false),
                          icon: const Icon(Icons.check),
                        ),
                        IconButton(
                          tooltip: 'Hide review',
                          onPressed: () => _resolveReviewReport(report, true),
                          icon: const Icon(Icons.visibility_off_outlined),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    ),
  );

  Widget _section(
    String title,
    List<Map<String, dynamic>> rows,
    String table,
    String Function(Map<String, dynamic>) detail,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 22),
      Text(title, style: Theme.of(context).textTheme.titleLarge),
      if (rows.isEmpty) const ListTile(title: Text('No pending requests.')),
      ...rows.map(
        (row) => Card(
          child: ListTile(
            title: Text('${row['user_id']}'),
            subtitle: Text(
              detail(row),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            isThreeLine: true,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Reject',
                  onPressed: () => _decide(table, row, 'rejected'),
                  icon: const Icon(Icons.close),
                ),
                IconButton(
                  tooltip: 'Approve',
                  onPressed: () => _decide(table, row, 'approved'),
                  icon: const Icon(Icons.check_circle_outline),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

class _AdminData {
  const _AdminData(
    this.metrics,
    this.students,
    this.lecturers,
    this.courses,
    this.tickets,
    this.audit,
    this.reviewReports,
  );
  final Map<String, dynamic> metrics;
  final List<Map<String, dynamic>> students, lecturers, courses, tickets, audit;
  final List<Map<String, dynamic>> reviewReports;
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 150,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            Text(label),
          ],
        ),
      ),
    ),
  );
}

class _Failure extends StatelessWidget {
  const _Failure({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 44),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: retry, child: const Text('Retry')),
          TextButton(
            onPressed: () => context.go('/'),
            child: const Text('Home'),
          ),
        ],
      ),
    ),
  );
}

String _label(String key) => key
    .replaceAll('_', ' ')
    .split(' ')
    .map(
      (word) =>
          word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}',
    )
    .join(' ');
