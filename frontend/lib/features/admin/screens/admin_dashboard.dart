import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../providers/auth_provider.dart';
import '../../../services/role_admin_service.dart';

// ─────────────────────────────────────────────────────────────
// Design tokens — mapped from the Capitalio (Watermelon UI) dashboard:
// dark surfaces, 1px borders, rounded-lg cards, gradient icon badges,
// 10%-tint tags, secondary "ghost" buttons, chart-1..4 palette.
// Tweak _primary to re-brand the whole screen.
// ─────────────────────────────────────────────────────────────
const _bg = Color(0xFF09090B); // --background
const _side = Color(0xFF0C0C0F); // sidebar
const _card = Color(0xFF111114); // --card
const _border = Color(0xFF242428); // --border
const _muted = Color(0xFF8E8E98); // --muted-foreground
const _primary = Color(0xFFFF5B2E); // --primary
const _green = Color(0xFF34D399); // --chart-4 (positive)
const _blue = Color(0xFF60A5FA); // --chart-1
const _amber = Color(0xFFFBBF24); // --chart-2
const _violet = Color(0xFFA78BFA); // --chart-3
const _red = Color(0xFFF87171); // --destructive
const _radius = 12.0;

class AdminDashboard extends ConsumerStatefulWidget {
  const AdminDashboard({super.key});
  @override
  ConsumerState<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends ConsumerState<AdminDashboard> {
  late Future<_AdminData> _data;
  final _search = TextEditingController();
  late Future<List<Map<String, dynamic>>> _users;
  int _tab = 0; // UI-only: 0 dashboard · 1 analytics · 2 approvals · 3 users · 4 support
  _AdminData? _cache; // UI-only: last loaded data (drawer badges)
  DateTime _updatedAt = DateTime.now(); // UI-only: "Last updates" label

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
    _updatedAt = DateTime.now();
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


  static const _titles = ['Dashboard', 'Analytics', 'Approvals', 'Users', 'Support'];

  ThemeData _theme() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: _side,
      colorScheme: const ColorScheme.dark(
        primary: _primary,
        onPrimary: Colors.white,
        surface: _card,
        error: _red,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: _bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: _card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
          side: const BorderSide(color: _border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _card,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _primary),
        ),
      ),
    );
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) => Theme(
    data: _theme(),
    child: Scaffold(
      drawer: _SideNav(
        tab: _tab,
        data: _cache,
        onSelect: (i) => setState(() => _tab = i),
      ),
      body: SafeArea(
        child: Padding(
          // main panel inset like `main p-0.5`
          padding: const EdgeInsets.all(2),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: ColoredBox(
              color: _bg,
              child: Column(
                children: [
                  _topbar(context),
                  Expanded(
                    child: FutureBuilder<_AdminData>(
                      future: _data,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(color: _primary),
                          );
                        }
                        if (snapshot.hasError) {
                          return _Failure(
                            message: '${snapshot.error}',
                            retry: () => setState(_load),
                          );
                        }
                        final data = snapshot.requireData;
                        _cache = data;
                        return RefreshIndicator(
                          color: _primary,
                          backgroundColor: _card,
                          onRefresh: () async => setState(_load),
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 280),
                                switchInCurve: Curves.easeOutCubic,
                                transitionBuilder: (child, anim) =>
                                    FadeTransition(
                                      opacity: anim,
                                      child: SlideTransition(
                                        position: Tween(
                                          begin: const Offset(0, .02),
                                          end: Offset.zero,
                                        ).animate(anim),
                                        child: child,
                                      ),
                                    ),
                                child: Column(
                                  key: ValueKey(_tab),
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: _tabBody(context, data),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  // Topbar: hamburger · title + "Last updates" · action buttons
  Widget _topbar(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 12, 12, 12),
    child: Row(
      children: [
        Builder(
          builder: (context) => IconButton(
            tooltip: 'Menu',
            onPressed: () => Scaffold.of(context).openDrawer(),
            icon: const Icon(Icons.menu_rounded),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _titles[_tab],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    'Last updates ${_two(_updatedAt.hour)}:${_two(_updatedAt.minute)}',
                    style: const TextStyle(fontSize: 12, color: _muted),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: _muted.withValues(alpha: .5),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'SkillBridge',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
          ),
        ),
        _TopAction(
          icon: Icons.campaign_outlined,
          tooltip: 'View announcements',
          onPressed: () => context.push('/announcements'),
        ),
        const SizedBox(width: 6),
        _TopAction(
          icon: Icons.add_alert_outlined,
          tooltip: 'Publish announcement',
          onPressed: _composeAnnouncement,
        ),
        const SizedBox(width: 6),
        _TopAction(
          icon: Icons.refresh_rounded,
          tooltip: 'Refresh',
          primary: true,
          onPressed: () => setState(_load),
        ),
      ],
    ),
  );

  // ── Overview ─────────────────────────────────────────────────
  List<Widget> _tabBody(BuildContext context, _AdminData data) {
    switch (_tab) {
      case 1:
        return _analytics(data);
      case 2:
        return [
          _requestSection(
            0,
            'Student verification',
            Icons.badge_outlined,
            data.students,
            'student_verification_requests',
            (row) =>
                '${row['student_number']} · ${row['department']} / ${row['program']}',
          ),
          _requestSection(
            1,
            'Lecturer applications',
            Icons.school_outlined,
            data.lecturers,
            'lecturer_applications',
            (row) => '${row['department']} · ${row['qualifications']}',
          ),
          _coursesSection(data.courses),
        ];
      case 3:
        return [_usersSection()];
      case 4:
        return [
          _ticketsSection(data.tickets),
          _reportsSection(data.reviewReports),
        ];
      default:
        return _overview(data);
    }
  }

  List<_Slice> _slices(_AdminData data) => [
    _Slice('Students', data.students.length, _blue),
    _Slice('Lecturers', data.lecturers.length, _green),
    _Slice('Courses', data.courses.length, _violet),
    _Slice('Tickets', data.tickets.length, _amber),
    _Slice('Reports', data.reviewReports.length, _red),
  ];

  List<Widget> _overview(_AdminData data) {
    final approvals = data.students.length + data.lecturers.length;
    final slices = _slices(data);
    final total = slices.fold<int>(0, (a, b) => a + b.value);

    final cards = <_SummaryData>[
      _SummaryData(
        'Pending approvals',
        Icons.verified_user_outlined,
        approvals,
        '${data.students.length} students · ${data.lecturers.length} lecturers',
        _blue,
      ),
      _SummaryData(
        'Courses in review',
        Icons.menu_book_outlined,
        data.courses.length,
        'Awaiting publish',
        _violet,
      ),
      _SummaryData(
        'Open tickets',
        Icons.support_agent_outlined,
        data.tickets.length,
        'Support queue',
        _amber,
      ),
      _SummaryData(
        'Reported reviews',
        Icons.flag_outlined,
        data.reviewReports.length,
        'Moderation queue',
        _red,
      ),
    ];

    final metricEntries = data.metrics.isEmpty
        ? <MapEntry<String, dynamic>>[
            const MapEntry('total_users', 0),
            const MapEntry('total_courses', 0),
            const MapEntry('open_tickets', 0),
            const MapEntry('pending_reviews', 0),
          ]
        : data.metrics.entries.toList();

    return [
      _pairs([
        for (var i = 0; i < cards.length; i++)
          _Reveal(
            index: i,
            child: _SummaryCard(data: cards[i], total: total),
          ),
      ]),
      const SizedBox(height: 12),

      // Open work — donut + compact legend
      _Reveal(
        index: 4,
        child: _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PanelHeader(
                title: 'Open work',
                icon: Icons.donut_large_rounded,
                trailing: _Tag(
                  total == 0 ? 'All clear' : '$total open',
                  color: total == 0 ? _green : _primary,
                  small: true,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  SizedBox(
                    width: 132,
                    height: 132,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 1100),
                      curve: Curves.easeOutCubic,
                      builder: (context, t, _) => CustomPaint(
                        painter: _DonutPainter(
                          slices.map((e) => e.value.toDouble()).toList(),
                          slices.map((e) => e.color).toList(),
                          t,
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${(total * t).round()}',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                  height: 1,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'open',
                                style: TextStyle(color: _muted, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      children: [
                        for (final s in slices)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              children: [
                                _Marker(color: s.color),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    s.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xCCFFFFFF),
                                    ),
                                  ),
                                ),
                                Text(
                                  '${s.value}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(
                                  width: 40,
                                  child: Text(
                                    total == 0
                                        ? '0%'
                                        : '${(s.value / total * 100).round()}%',
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      color: _muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),

      // Platform overview — compact fixed-size tiles
      _Reveal(
        index: 5,
        child: _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _PanelHeader(
                title: 'Platform overview',
                icon: Icons.insights_outlined,
                trailing: _Tag('Live', color: _green, small: true, dot: true),
              ),
              const SizedBox(height: 14),
              _pairs([
                for (final e in metricEntries)
                  _MetricTile(
                    label: _label(e.key),
                    value: e.value,
                    icon: _metricIcon(e.key),
                  ),
              ], gap: 10),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),

      _Reveal(index: 6, child: _insightsPanel(data)),
      const SizedBox(height: 12),

      _Reveal(
        index: 7,
        child: _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PanelHeader(
                title: 'Recent audit events',
                icon: Icons.history,
                trailing: _Tag('${data.audit.length}', color: _blue, small: true),
              ),
              const SizedBox(height: 12),
              if (data.audit.isEmpty)
                const _GhostChart(message: 'No audited activity yet.')
              else
                for (final event in data.audit)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _border),
                    ),
                    child: Row(
                      children: [
                        const _IconBadge(icon: Icons.history, size: 32),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${event['action']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${event['target_type']} ${event['target_id']} · ${event['created_at']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: _muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ),
    ];
  }

  // ── Analytics (bars, breakdowns) — all derived from loaded data ──
  List<Widget> _analytics(_AdminData data) {
    final slices = _slices(data);
    final total = slices.fold<int>(0, (a, b) => a + b.value);
    final day = _auditByDay(data.audit);
    final actions = _countBy(data.audit, 'action', 5);
    final priorities = _countBy(data.tickets, 'priority', 5);
    final categories = _countBy(data.courses, 'category', 5);
    final metricBars = <_BarItem>[];
    var ci = 0;
    for (final e in data.metrics.entries) {
      final n = e.value is num ? (e.value as num).toDouble() : double.tryParse('${e.value}');
      if (n != null) {
        metricBars.add(_BarItem(_label(e.key), n, _palette[ci++ % _palette.length]));
      }
    }
    final acts = <_BarItem>[
      for (var i = 0; i < actions.length; i++)
        _BarItem(actions[i].key, actions[i].value.toDouble(), _palette[i % _palette.length]),
    ];
    final prios = <_BarItem>[
      for (final p in priorities)
        _BarItem(p.key, p.value.toDouble(), _priorityColor(p.key)),
    ];
    final cats = <_BarItem>[
      for (var i = 0; i < categories.length; i++)
        _BarItem(categories[i].key, categories[i].value.toDouble(), _palette[(i + 2) % _palette.length]),
    ];

    return [
      _pairs([
        _Reveal(
          index: 0,
          child: _KpiCard(
            icon: Icons.inbox_outlined,
            label: 'Open items',
            value: total,
            color: _primary,
          ),
        ),
        _Reveal(
          index: 1,
          child: _KpiCard(
            icon: Icons.bolt_outlined,
            label: 'Audit events',
            value: data.audit.length,
            color: _blue,
          ),
        ),
      ], gap: 12),
      const SizedBox(height: 12),

      _Reveal(
        index: 2,
        child: _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PanelHeader(
                title: 'Open work by queue',
                icon: Icons.bar_chart_rounded,
                trailing: _Tag('$total total', color: _primary, small: true),
              ),
              const SizedBox(height: 14),
              _BarChart(
                labels: slices.map((e) => e.label).toList(),
                values: slices.map((e) => e.value.toDouble()).toList(),
                colors: slices.map((e) => e.color).toList(),
              ),
              const SizedBox(height: 14),
              _StackedBar(slices: slices),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),

      _Reveal(
        index: 3,
        child: _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PanelHeader(
                title: 'Audit activity by day',
                icon: Icons.show_chart_rounded,
                trailing: _Tag(
                  day.$1.isEmpty ? 'No data' : 'Last ${day.$1.length} days',
                  color: _green,
                  small: true,
                ),
              ),
              const SizedBox(height: 14),
              if (day.$1.isEmpty)
                const _GhostChart(message: 'Activity will appear here.')
              else
                _BarChart(
                  labels: day.$1,
                  values: day.$2,
                  colors: List.filled(day.$1.length, _green),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),

      _Reveal(
        index: 4,
        child: _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _PanelHeader(
                title: 'Top audit actions',
                icon: Icons.leaderboard_outlined,
              ),
              const SizedBox(height: 10),
              if (acts.isEmpty)
                const _GhostChart(message: 'No audit actions yet.', height: 90)
              else
                _HBars(items: acts),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),

      _Reveal(
        index: 5,
        child: _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _PanelHeader(
                title: 'Tickets by priority',
                icon: Icons.support_agent_outlined,
              ),
              const SizedBox(height: 10),
              if (prios.isEmpty)
                const _GhostChart(message: 'No open tickets.', height: 90)
              else
                _HBars(items: prios),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),

      _Reveal(
        index: 6,
        child: _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _PanelHeader(
                title: 'Courses in review by category',
                icon: Icons.menu_book_outlined,
              ),
              const SizedBox(height: 10),
              if (cats.isEmpty)
                const _GhostChart(message: 'No courses in review.', height: 90)
              else
                _HBars(items: cats),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),

      _Reveal(
        index: 7,
        child: _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _PanelHeader(
                title: 'Platform metrics',
                icon: Icons.insights_outlined,
                trailing: _Tag('Live', color: _green, small: true, dot: true),
              ),
              const SizedBox(height: 10),
              if (metricBars.isEmpty)
                const _GhostChart(message: 'No metrics available.', height: 90)
              else
                _HBars(items: metricBars),
            ],
          ),
        ),
      ),
    ];
  }


  Widget _insightsPanel(_AdminData data) {
    final items = <_Insight>[
      if (data.students.length + data.lecturers.length > 0)
        _Insight(
          Icons.verified_user_outlined,
          'Verification requests waiting',
          '${data.students.length} student and ${data.lecturers.length} lecturer requests need a decision.',
          'Review',
          2,
        ),
      if (data.courses.isNotEmpty)
        _Insight(
          Icons.menu_book_outlined,
          'Courses ready for moderation',
          '${data.courses.length} submitted course(s) are waiting to be published or rejected.',
          'Review',
          2,
        ),
      if (data.tickets.isNotEmpty)
        _Insight(
          Icons.support_agent_outlined,
          'Open support tickets',
          '${data.tickets.length} ticket(s) are unresolved.',
          'Open queue',
          4,
        ),
      if (data.reviewReports.isNotEmpty)
        _Insight(
          Icons.flag_outlined,
          'Reported reviews',
          '${data.reviewReports.length} review report(s) need moderation.',
          'Moderate',
          4,
        ),
    ];
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelHeader(
            title: 'Needs your attention',
            trailing: _Tag(
              items.isEmpty ? 'Clear' : '${items.length} items',
              color: items.isEmpty ? _green : _primary,
            ),
          ),
          const SizedBox(height: 18),
          if (items.isEmpty)
            const _EmptyRow('Nothing is waiting for review. Nice work!')
          else
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Divider(height: 1, color: _border),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _IconBadge(icon: items[i].icon),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          items[i].title,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          items[i].description,
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 14,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: _GhostButton(
                            label: items[i].action,
                            trailingIcon: Icons.north_east_rounded,
                            onPressed: () => setState(() => _tab = items[i].tab),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
        ],
      ),
    );
  }

  // ── Approvals ────────────────────────────────────────────────
  Widget _requestSection(
    int index,
    String title,
    IconData icon,
    List<Map<String, dynamic>> rows,
    String table,
    String Function(Map<String, dynamic>) detail,
  ) => _Reveal(
    index: index,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(title: title, count: rows.length),
          if (rows.isEmpty) const _EmptyCard('No pending requests.'),
          ...rows.map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _IconBadge(icon: icon),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${row['user_id']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                detail(row),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _GhostButton(
                            label: 'Reject',
                            leadingIcon: Icons.close,
                            color: _red,
                            expand: true,
                            onPressed: () => _decide(table, row, 'rejected'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _PrimaryButton(
                            label: 'Approve',
                            icon: Icons.check,
                            onPressed: () => _decide(table, row, 'approved'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _coursesSection(List<Map<String, dynamic>> courses) => _Reveal(
    index: 2,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: 'Courses awaiting review', count: courses.length),
        if (courses.isEmpty)
          const _EmptyCard('No courses are waiting for review.'),
        ...courses.map(
          (row) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const _IconBadge(icon: Icons.menu_book_outlined),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${row['title']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${row['category']} · ${row['level']} · ${row['instructor']}',
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _GhostButton(
                          label: 'Reject',
                          leadingIcon: Icons.close,
                          color: _red,
                          expand: true,
                          onPressed: () => _moderateCourse(row, 'rejected'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _PrimaryButton(
                          label: 'Publish',
                          icon: Icons.check_circle_outline,
                          onPressed: () => _moderateCourse(row, 'published'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );

  // ── Users (holdings-table mobile card style) ─────────────────
  Widget _usersSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _SectionTitle(title: 'User roles'),
      TextField(
        controller: _search,
        decoration: InputDecoration(
          hintText: 'Search by name or email',
          prefixIcon: const Icon(Icons.search, color: _muted, size: 20),
          suffixIcon: IconButton(
            tooltip: 'Search',
            onPressed: () => setState(_load),
            icon: const Icon(Icons.arrow_forward, color: _primary, size: 20),
          ),
        ),
        onSubmitted: (_) => setState(_load),
      ),
      const SizedBox(height: 14),
      FutureBuilder<List<Map<String, dynamic>>>(
        future: _users,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(color: _primary),
            );
          }
          if (snapshot.hasError) {
            return _EmptyCard('Could not load users: ${snapshot.error}');
          }
          return Column(
            children: [
              for (var i = 0; i < snapshot.requireData.length; i++)
                _Reveal(index: i, child: _userCard(snapshot.requireData[i])),
            ],
          );
        },
      ),
    ],
  );

  Widget _userCard(Map<String, dynamic> user) {
    final roles = (user['roles'] as List? ?? const []).cast<String>();
    final accountStatus = user['account_status'] as String? ?? 'active';
    final name = '${user['full_name'] ?? 'Unnamed user'}';
    final statusColor = accountStatus == 'active'
        ? _green
        : accountStatus == 'suspended'
        ? _amber
        : _red;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _Panel(
        padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Avatar(name: name),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${user['email']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Manage account',
                  icon: const Icon(Icons.more_vert, color: _muted),
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
              ],
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Roles',
                          style: TextStyle(color: _muted, fontSize: 12),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: roles.isEmpty
                              ? const [_Tag('none', color: _muted, small: true)]
                              : roles
                                    .map((r) => _Tag(r, color: _blue, small: true))
                                    .toList(),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Status',
                        style: TextStyle(color: _muted, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      _Tag(accountStatus, color: statusColor, small: true),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Support ──────────────────────────────────────────────────
  Widget _ticketsSection(List<Map<String, dynamic>> tickets) => _Reveal(
    index: 0,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(title: 'Open support tickets', count: tickets.length),
          if (tickets.isEmpty) const _EmptyCard('No open support tickets.'),
          ...tickets.map(
            (ticket) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _IconBadge(icon: Icons.support_agent_outlined),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${ticket['subject']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${ticket['category']}',
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _Tag(
                          '${ticket['priority']}',
                          color: _priorityColor('${ticket['priority']}'),
                          small: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${ticket['description']}',
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: _PrimaryButton(
                        label: 'Resolve ticket',
                        icon: Icons.check_circle_outline,
                        onPressed: () => _resolveTicket(ticket),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _reportsSection(List<Map<String, dynamic>> reports) => _Reveal(
    index: 1,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: 'Reported reviews', count: reports.length),
        if (reports.isEmpty)
          const _EmptyCard('No reported reviews are waiting for moderation.'),
        ...reports.map((report) {
          final review = Map<String, dynamic>.from(
            report['course_reviews'] as Map? ?? const {},
          );
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const _IconBadge(icon: Icons.flag_outlined),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Rating ${review['rating'] ?? '?'} · Course ${review['course_id'] ?? ''}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _Tag('${report['reason']}', color: _red, small: true),
                  const SizedBox(height: 10),
                  Text(
                    '${review['comment'] ?? ''}',
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _GhostButton(
                          label: 'Dismiss',
                          leadingIcon: Icons.check,
                          expand: true,
                          onPressed: () => _resolveReviewReport(report, false),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _GhostButton(
                          label: 'Hide review',
                          leadingIcon: Icons.visibility_off_outlined,
                          color: _red,
                          expand: true,
                          onPressed: () => _resolveReviewReport(report, true),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────
// Sidebar (as a Drawer on mobile)
// ─────────────────────────────────────────────────────────────
class _SideNav extends StatelessWidget {
  const _SideNav({
    required this.tab,
    required this.data,
    required this.onSelect,
  });
  final int tab;
  final _AdminData? data;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final approvals = data == null
        ? 0
        : data!.students.length + data!.lecturers.length + data!.courses.length;
    final support = data == null
        ? 0
        : data!.tickets.length + data!.reviewReports.length;
    final items = [
      (Icons.space_dashboard_outlined, 'Dashboard', 0, 0),
      (Icons.bar_chart_rounded, 'Analytics', 1, 0),
      (Icons.verified_user_outlined, 'Approvals', 2, approvals),
      (Icons.people_alt_outlined, 'Users', 3, 0),
      (Icons.support_agent_outlined, 'Support', 4, support),
    ];
    return Drawer(
      backgroundColor: _side,
      width: 270,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  _IconBadge(icon: Icons.hub_outlined, size: 40),
                  SizedBox(width: 12),
                  Text(
                    'SkillBridge',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 0, 8, 10),
                child: Text(
                  'Admin',
                  style: TextStyle(color: Color(0xB38E8E98), fontSize: 15),
                ),
              ),
              for (final item in items)
                _NavItem(
                  icon: item.$1,
                  label: item.$2,
                  count: item.$4,
                  active: tab == item.$3,
                  onTap: () {
                    onSelect(item.$3);
                    Navigator.pop(context);
                  },
                ),
              const Spacer(),
              const Divider(color: _border),
              const SizedBox(height: 8),
              Row(
                children: [
                  const _Avatar(name: 'Admin', square: true),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Administrator',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        SizedBox(height: 4),
                        _Tag('Admin', color: _primary, small: true),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Back to app',
                    onPressed: () => context.go('/'),
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    color: _muted,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.count = 0,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final int count;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(
          color: active ? _primary.withValues(alpha: .12) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? _primary.withValues(alpha: .35) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: active ? _primary : _muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active ? Colors.white : _muted,
                ),
              ),
            ),
            if (count > 0) _Tag('$count', color: _primary, small: true),
          ],
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────
// Layout + motion helpers
// ─────────────────────────────────────────────────────────────
const _palette = [_primary, _blue, _green, _violet, _amber, _red];

/// Lays children out two-per-row with equal widths (standard card grid).
Widget _pairs(List<Widget> items, {double gap = 12}) {
  final rows = <Widget>[];
  for (var i = 0; i < items.length; i += 2) {
    rows.add(
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: items[i]),
          SizedBox(width: gap),
          Expanded(
            child: i + 1 < items.length ? items[i + 1] : const SizedBox.shrink(),
          ),
        ],
      ),
    );
    if (i + 2 < items.length) rows.add(SizedBox(height: gap));
  }
  return Column(children: rows);
}

(List<String>, List<double>) _auditByDay(List<Map<String, dynamic>> audit) {
  final counts = <DateTime, int>{};
  for (final e in audit) {
    final dt = DateTime.tryParse('${e['created_at']}')?.toLocal();
    if (dt == null) continue;
    final key = DateTime(dt.year, dt.month, dt.day);
    counts[key] = (counts[key] ?? 0) + 1;
  }
  final keys = counts.keys.toList()..sort();
  final last = keys.length > 7 ? keys.sublist(keys.length - 7) : keys;
  String two(int n) => n.toString().padLeft(2, '0');
  return (
    last.map((d) => '${two(d.day)}/${two(d.month)}').toList(),
    last.map((d) => counts[d]!.toDouble()).toList(),
  );
}

List<MapEntry<String, int>> _countBy(
  List<Map<String, dynamic>> rows,
  String key,
  int limit,
) {
  final m = <String, int>{};
  for (final r in rows) {
    final v = '${r[key] ?? ''}'.trim();
    if (v.isEmpty || v == 'null') continue;
    m[v] = (m[v] ?? 0) + 1;
  }
  final list = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return list.take(limit).toList();
}

/// Repeating 0→1→0 eased value for gentle "breathing" motion.
class _Breathe extends StatefulWidget {
  const _Breathe({
    required this.builder,
    this.duration = const Duration(milliseconds: 2400),
  });
  final Widget Function(BuildContext context, double t) builder;
  final Duration duration;
  @override
  State<_Breathe> createState() => _BreatheState();
}

class _BreatheState extends State<_Breathe>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) =>
        widget.builder(context, Curves.easeInOut.transform(_c.value)),
  );
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.title, this.trailing, this.icon});
  final String title;
  final Widget? trailing;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (icon != null) ...[
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: _primary.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: _primary),
        ),
        const SizedBox(width: 10),
      ],
      Expanded(
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      if (trailing != null) trailing!,
    ],
  );
}

/// DetailTag: coloured text on a 10% tint of the same colour.
class _Tag extends StatelessWidget {
  const _Tag(
    this.text, {
    required this.color,
    this.small = false,
    this.dot = false,
  });
  final String text;
  final Color color;
  final bool small;
  final bool dot;
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(
      horizontal: small ? 8 : 12,
      vertical: small ? 3 : 4,
    ),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dot) ...[
          _Breathe(
            duration: const Duration(milliseconds: 1200),
            builder: (context, t) => Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: .6 * t),
                    blurRadius: 6 * t,
                    spreadRadius: 1.5 * t,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
        Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: small ? 12 : 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

/// dashboard-icon-badge: gradient primary square, white icon, soft pulsing glow.
class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, this.size = 34});
  final IconData icon;
  final double size;
  @override
  Widget build(BuildContext context) => _Breathe(
    builder: (context, t) => Transform.scale(
      scale: 1 + .035 * t,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * .26),
          border: Border.all(color: _primary),
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Color.lerp(_primary, Colors.black, .2)!, _primary],
          ),
          boxShadow: [
            BoxShadow(
              color: _primary.withValues(alpha: .10 + .22 * t),
              blurRadius: 8 + 8 * t,
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: size * .55),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────
// Cards (fixed height → uniform, aligned grid)
// ─────────────────────────────────────────────────────────────
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.data, required this.total});
  final _SummaryData data;
  final int total;
  @override
  Widget build(BuildContext context) {
    final share = total == 0 ? 0.0 : data.value / total;
    final clear = data.value == 0;
    return SizedBox(
      height: 126,
      child: _Panel(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                _IconBadge(icon: data.icon, size: 30),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    data.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: _muted),
                  ),
                ),
              ],
            ),
            _AnimatedNumber(
              value: data.value,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
            Row(
              children: [
                Icon(
                  clear ? Icons.check_rounded : Icons.arrow_upward_rounded,
                  size: 12,
                  color: clear ? _green : data.color,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    clear ? 'All clear' : data.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: clear ? _green : _muted,
                    ),
                  ),
                ),
              ],
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: share),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => LinearProgressIndicator(
                  value: v,
                  minHeight: 5,
                  backgroundColor: Colors.white.withValues(alpha: .07),
                  valueColor: AlwaysStoppedAnimation(data.color),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final dynamic value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    height: 64,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(
      color: const Color(0xFF16161A),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _border),
    ),
    child: Row(
      children: [
        _IconBadge(icon: icon, size: 30),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, color: _muted),
              ),
              const SizedBox(height: 3),
              _AnimatedNumber(
                value: value ?? 0,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final int value;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 84,
    child: _Panel(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          _IconBadge(icon: icon, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: _muted),
                ),
                const SizedBox(height: 4),
                _AnimatedNumber(
                  value: value,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────
// Charts (pure Flutter, no extra packages)
// ─────────────────────────────────────────────────────────────
class _BarItem {
  const _BarItem(this.label, this.value, this.color);
  final String label;
  final double value;
  final Color color;
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: .06)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Vertical animated bar chart with grid, value labels and category labels.
class _BarChart extends StatelessWidget {
  const _BarChart({
    required this.labels,
    required this.values,
    required this.colors,
    this.height = 180,
  });
  final List<String> labels;
  final List<double> values;
  final List<Color> colors;
  final double height;

  @override
  Widget build(BuildContext context) {
    final maxV = values.fold<double>(0, math.max);
    final top = maxV <= 0 ? 1.0 : maxV;
    final barMax = height - 46;
    return SizedBox(
      height: height,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (context, t, _) => Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 18,
              bottom: 24,
              child: CustomPaint(painter: _GridPainter()),
            ),
            Positioned.fill(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < values.length; i++)
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Opacity(
                            opacity: t.clamp(0.0, 1.0).toDouble(),
                            child: Text(
                              values[i] == values[i].roundToDouble()
                                  ? '${values[i].round()}'
                                  : values[i].toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            width: 22,
                            height: math.max(4.0, barMax * values[i] / top * t),
                            decoration: BoxDecoration(
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(6),
                              ),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  colors[i],
                                  colors[i].withValues(alpha: .45),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 16,
                            child: Text(
                              labels[i],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 10,
                                color: _muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal ranked bars with animated fill.
class _HBars extends StatelessWidget {
  const _HBars({required this.items});
  final List<_BarItem> items;
  @override
  Widget build(BuildContext context) {
    final maxV = items.fold<double>(0, (a, b) => math.max(a, b.value));
    final top = maxV <= 0 ? 1.0 : maxV;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => Column(
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  Row(
                    children: [
                      _Marker(color: item.color),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xCCFFFFFF),
                          ),
                        ),
                      ),
                      Text(
                        item.value == item.value.roundToDouble()
                            ? '${(item.value * t).round()}'
                            : (item.value * t).toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 8,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: ColoredBox(
                              color: Colors.white.withValues(alpha: .06),
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: math.max(
                                0.02,
                                (item.value / top * t).clamp(0.0, 1.0).toDouble(),
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      item.color.withValues(alpha: .6),
                                      item.color,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Single stacked share bar (like Capitalio's allocation bar).
class _StackedBar extends StatelessWidget {
  const _StackedBar({required this.slices});
  final List<_Slice> slices;
  @override
  Widget build(BuildContext context) {
    final total = slices.fold<int>(0, (a, b) => a + b.value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Queue share', style: TextStyle(color: _muted, fontSize: 12)),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 12,
            child: total == 0
                ? ColoredBox(color: Colors.white.withValues(alpha: .06))
                : TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 1000),
                    curve: Curves.easeOutCubic,
                    builder: (context, t, _) => Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: t,
                        child: Row(
                          children: [
                            for (final s in slices.where((e) => e.value > 0))
                              Expanded(
                                flex: s.value,
                                child: Container(
                                  margin: const EdgeInsets.only(right: 2),
                                  color: s.color,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Placeholder for empty charts: breathing ghost bars + message.
class _GhostChart extends StatelessWidget {
  const _GhostChart({required this.message, this.height = 130});
  final String message;
  final double height;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Align(
          alignment: Alignment.bottomCenter,
          child: _Breathe(
            builder: (context, t) => Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final f in const [.4, .7, .5, .9, .6, .8, .45])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Container(
                        height: (height - 24) * f * (.85 + .15 * t),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .04 + .04 * t),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _card.withValues(alpha: .9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_graph_rounded, size: 16, color: _muted),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  message,
                  style: const TextStyle(color: _muted, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}


// ─────────────────────────────────────────────────────────────
// Reusable pieces
// ─────────────────────────────────────────────────────────────
Color _priorityColor(String p) {
  switch (p.toLowerCase()) {
    case 'high':
    case 'urgent':
      return _red;
    case 'medium':
    case 'normal':
      return _amber;
    default:
      return _blue;
  }
}

IconData _metricIcon(String key) {
  final k = key.toLowerCase();
  if (k.contains('user') || k.contains('student') || k.contains('lecturer')) {
    return Icons.people_alt_outlined;
  }
  if (k.contains('course')) return Icons.menu_book_outlined;
  if (k.contains('ticket') || k.contains('support')) {
    return Icons.support_agent_outlined;
  }
  if (k.contains('review') || k.contains('report')) {
    return Icons.rate_review_outlined;
  }
  return Icons.insights_outlined;
}

class _SummaryData {
  const _SummaryData(this.title, this.icon, this.value, this.caption, this.color);
  final String title, caption;
  final IconData icon;
  final int value;
  final Color color;
}

class _Slice {
  const _Slice(this.label, this.value, this.color);
  final String label;
  final int value;
  final Color color;
}

class _Insight {
  const _Insight(this.icon, this.title, this.description, this.action, this.tab);
  final IconData icon;
  final String title, description, action;
  final int tab;
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

/// Staggered fade + slide-up entrance (index controls the delay feel).
class _Reveal extends StatelessWidget {
  const _Reveal({required this.child, this.index = 0});
  final Widget child;
  final int index;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: Duration(milliseconds: 380 + math.min(index, 8) * 90),
    curve: Curves.easeOutCubic,
    builder: (context, v, child) => Opacity(
      opacity: v.clamp(0.0, 1.0).toDouble(),
      child: Transform.translate(offset: Offset(0, 18 * (1 - v)), child: child),
    ),
    child: child,
  );
}

/// Count-up number; falls back to plain text for non-numeric values.
class _AnimatedNumber extends StatelessWidget {
  const _AnimatedNumber({required this.value, required this.style});
  final dynamic value;
  final TextStyle style;
  @override
  Widget build(BuildContext context) {
    final n = value is num ? value as num : num.tryParse('$value');
    if (n == null) return Text('$value', style: style);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: n.toDouble()),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(
        n is int || n == n.roundToDouble()
            ? '${v.round()}'
            : v.toStringAsFixed(1),
        style: style,
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: _card,
      borderRadius: BorderRadius.circular(_radius),
      border: Border.all(color: _border),
      boxShadow: const [
        BoxShadow(color: Color(0x40000000), blurRadius: 18, offset: Offset(0, 6)),
      ],
    ),
    child: child,
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.count});
  final String title;
  final int? count;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12, top: 4),
    child: Row(
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        ),
        if (count != null) ...[
          const SizedBox(width: 10),
          _Tag('$count', color: count == 0 ? _muted : _primary, small: true),
        ],
      ],
    ),
  );
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.inbox_outlined, color: _muted, size: 20),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: const TextStyle(color: _muted))),
    ],
  );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: _Panel(child: _EmptyRow(text)),
  );
}

class _Marker extends StatelessWidget {
  const _Marker({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: 14,
    height: 14,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(3),
    ),
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.square = false});
  final String name;
  final bool square;
  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 40,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0xFF1B1B20),
      borderRadius: BorderRadius.circular(square ? 10 : 20),
      border: Border.all(color: _border),
    ),
    child: Text(
      name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
      style: const TextStyle(color: _primary, fontWeight: FontWeight.w700),
    ),
  );
}

class _TopAction extends StatelessWidget {
  const _TopAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.primary = false,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool primary;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onPressed,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: primary ? _primary : _card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: primary ? _primary : _border),
        ),
        child: Icon(icon, size: 19, color: Colors.white),
      ),
    ),
  );
}

/// Secondary button: translucent foreground fill, rounded-lg.
class _GhostButton extends StatelessWidget {
  const _GhostButton({
    required this.label,
    required this.onPressed,
    this.leadingIcon,
    this.trailingIcon,
    this.color,
    this.expand = false,
  });
  final String label;
  final VoidCallback onPressed;
  final IconData? leadingIcon, trailingIcon;
  final Color? color;
  final bool expand;
  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.white;
    return Material(
      color: c.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (leadingIcon != null) ...[
                Icon(leadingIcon, size: 16, color: c),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (trailingIcon != null) ...[
                const SizedBox(width: 6),
                Icon(trailingIcon, size: 16, color: c),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Material(
    color: _primary,
    borderRadius: BorderRadius.circular(10),
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.values, this.colors, this.progress);
  final List<double> values;
  final List<Color> colors;
  final double progress; // 0..1 sweep-in animation

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 22.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = Colors.white.withValues(alpha: .06),
    );

    final total = values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return;
    final nonZero = values.where((v) => v > 0).length;
    final gap = nonZero > 1 ? 0.12 : 0.0;
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      if (values[i] <= 0) continue;
      final sweep = (values[i] / total) * math.pi * 2 * progress;
      final drawn = math.max(sweep - gap, 0.0);
      if (drawn > 0.001) {
        canvas.drawArc(
          rect,
          start + gap / 2,
          drawn,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = stroke
            ..color = colors[i],
        );
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.progress != progress ||
      old.values != values ||
      old.colors != colors;
}

class _Failure extends StatelessWidget {
  const _Failure({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: _Panel(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 44, color: _muted),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            _PrimaryButton(label: 'Retry', icon: Icons.refresh, onPressed: retry),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => context.go('/'),
              child: const Text('Home'),
            ),
          ],
        ),
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