import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/course_model.dart';
import '../../services/course_service.dart';
import '../../services/storage_service.dart';
import 'explore_catalog_widgets.dart';
import '../profile/screens/profile_screen.dart';
import '../../core/theme/app_theme.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.supabaseConfigured,
    this.initialTab = 0,
  });

  final bool supabaseConfigured;
  final int initialTab;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _selectedIndex = widget.initialTab;
  late final CourseService _courseService = CourseService(
    client: widget.supabaseConfigured ? Supabase.instance.client : null,
  );
  late final StorageService? _storageService = widget.supabaseConfigured
      ? StorageService(Supabase.instance.client)
      : null;

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      setState(() => _selectedIndex = widget.initialTab);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      SkillBridgeHome(
        loadCourses: () => _courseService.getCourses(),
        onOpenCourse: (course) => context.push('/courses/${course.id}'),
        onExplore: () => setState(() => _selectedIndex = 1),
        supabaseConfigured: widget.supabaseConfigured,
        storageService: _storageService,
      ),
      _CoursesPage(
        courseService: _courseService,
        supabaseConfigured: widget.supabaseConfigured,
        storageService: _storageService,
      ),
      _LearningPage(
        courseService: _courseService,
        supabaseConfigured: widget.supabaseConfigured,
        storageService: _storageService,
      ),
      widget.supabaseConfigured
          ? const ProfileScreen()
          : const _SimplePage(
              title: 'Your profile',
              icon: Icons.person_outline,
              message: 'Connect Supabase to create an account and sync your learning.',
            ),
      LecturerDirectoryPage(supabaseConfigured: widget.supabaseConfigured),
    ];

    return Theme(
      data: AppTheme.dark,
      child: Scaffold(
        body: IndexedStack(
          index: _selectedIndex,
          children: [
            for (var index = 0; index < pages.length; index++)
              TickerMode(enabled: index == _selectedIndex, child: pages[index]),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) =>
              setState(() => _selectedIndex = index),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.explore_outlined),
              label: 'Explore',
            ),
            NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              label: 'My learning',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              label: 'Profile',
            ),
            NavigationDestination(
              icon: Icon(Icons.verified_outlined),
              label: 'Lecturers',
            ),
          ],
        ),
      ),
    );
  }
}

class _CoursesPage extends StatefulWidget {
  const _CoursesPage({
    required this.courseService,
    required this.supabaseConfigured,
    required this.storageService,
  });

  final CourseService courseService;
  final bool supabaseConfigured;
  final StorageService? storageService;

  @override
  State<_CoursesPage> createState() => _CoursesPageState();
}

class _CoursesPageState extends State<_CoursesPage> {
  late Future<List<Course>> _courses;
  final _searchController = TextEditingController();
  final _categoryController = TextEditingController();
  String? _level;
  double _minimumRating = 0;
  bool _hasMore = true;
  Set<String> _enrolledCourseIds = {};

  @override
  void initState() {
    super.initState();
    _courses = _loadCourses();
  }

  Future<List<Course>> _loadCourses({int offset = 0}) async {
    final courses = await widget.courseService.getCourses(
      search: _searchController.text.trim(),
      category: _categoryController.text.trim(),
      level: _level,
      minimumRating: _minimumRating == 0 ? null : _minimumRating,
      offset: offset,
    );
    if (mounted && offset == 0) setState(() => _hasMore = courses.length == 24);
    final enrolledIds = await widget.courseService.getEnrolledCourseIds();
    if (mounted) setState(() => _enrolledCourseIds = enrolledIds.toSet());
    return courses;
  }

  void _reload() => setState(() {
    _hasMore = true;
    _courses = _loadCourses();
  });

  Future<void> _loadMore(List<Course> current) async {
    if (!_hasMore) return;
    setState(() => _hasMore = false);
    try {
      final next = await _loadCourses(offset: current.length);
      if (!mounted) return;
      setState(() {
        _courses = Future.value([...current, ...next]);
        _hasMore = next.length == 24;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _hasMore = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load more courses: $error')),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  Future<void> _enroll(Course course) async {
    if (!widget.supabaseConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connect Supabase to save enrollments.')),
      );
      return;
    }

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      await context.push<void>('/login');
      if (mounted) _reload();
      return;
    }
    if (user.emailConfirmedAt == null &&
        user.appMetadata['provider'] == 'email') {
      context.push<void>(
        '/check-email?email=${Uri.encodeQueryComponent(user.email ?? '')}',
      );
      return;
    }

    try {
      await widget.courseService.enroll(course.id);
      if (!mounted) return;
      setState(() => _enrolledCourseIds.add(course.id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You are enrolled in this course.')),
      );
    } on PostgrestException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _review(Course course) async {
    final comment = TextEditingController();
    var rating = 5;
    final submit = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text('Review ${course.title}'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Rating: $rating / 5'),
                Slider(
                  value: rating.toDouble(),
                  min: 1,
                  max: 5,
                  divisions: 4,
                  label: '$rating',
                  onChanged: (value) => update(() => rating = value.round()),
                ),
                TextField(
                  controller: comment,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: 'Your review'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save review'),
            ),
          ],
        ),
      ),
    );
    if (submit == true) {
      try {
        await widget.courseService.saveReview(
          courseId: course.id,
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
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<List<Course>>(
        future: _courses,
        builder: (context, snapshot) {
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                title: const Text('Explore courses'),
                floating: true,
                actions: [
                  IconButton(
                    onPressed: _reload,
                    tooltip: 'Refresh courses',
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
                  child: TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _reload(),
                    decoration: InputDecoration(
                      labelText: 'Search courses',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        onPressed: _reload,
                        icon: const Icon(Icons.arrow_forward),
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 220,
                        child: TextField(
                          controller: _categoryController,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _reload(),
                          decoration: InputDecoration(
                            labelText: 'Category',
                            suffixIcon: IconButton(
                              tooltip: 'Apply category',
                              onPressed: _reload,
                              icon: const Icon(Icons.filter_alt_outlined),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 220,
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: _level ?? 'All levels',
                          decoration: const InputDecoration(
                            labelText: 'Difficulty',
                          ),
                          items:
                              const [
                                    'All levels',
                                    'Beginner',
                                    'Intermediate',
                                    'Advanced',
                                  ]
                                  .map(
                                    (level) => DropdownMenuItem(
                                      value: level,
                                      child: Text(level),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (value) {
                            setState(
                              () =>
                                  _level = value == 'All levels' ? null : value,
                            );
                            _reload();
                          },
                        ),
                      ),
                      SizedBox(
                        width: 220,
                        child: DropdownButtonFormField<double>(
                          isExpanded: true,
                          initialValue: _minimumRating,
                          decoration: const InputDecoration(
                            labelText: 'Minimum rating',
                          ),
                          items: const [0.0, 3.0, 4.0, 4.5]
                              .map(
                                (rating) => DropdownMenuItem(
                                  value: rating,
                                  child: Text(
                                    rating == 0
                                        ? 'Any rating'
                                        : '$rating stars and up',
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (rating) {
                            setState(() => _minimumRating = rating ?? 0);
                            _reload();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (snapshot.hasError)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_off_outlined, size: 40),
                          const SizedBox(height: 12),
                          const Text('Courses could not be loaded.'),
                          if (snapshot.error != null) ...[
                            const SizedBox(height: 8),
                            SelectableText(
                              'Technical details: ${snapshot.error}',
                              textAlign: TextAlign.center,
                            ),
                          ],
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: _reload,
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (snapshot.connectionState != ConnectionState.done)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (snapshot.data!.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: Text('No published courses yet.')),
                )
              else
                SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.crossAxisExtent >= 1200
                        ? 4
                        : constraints.crossAxisExtent >= 900
                        ? 3
                        : constraints.crossAxisExtent >= 560
                        ? 2
                        : 1;
                    return SliverPadding(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                      sliver: SliverGrid.builder(
                        itemCount: snapshot.data!.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisExtent: 360,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                        ),
                        itemBuilder: (context, index) {
                          final course = snapshot.data![index];
                          return _CourseCard(
                            course: course,
                            storageService: widget.storageService,
                            isEnrolled: _enrolledCourseIds.contains(course.id),
                            isPreview: !widget.supabaseConfigured,
                            onEnroll: () => _enroll(course),
                            onReview: () => _review(course),
                            onOpen: () => context.push('/courses/${course.id}'),
                          );
                        },
                      ),
                    );
                  },
                ),
              if (snapshot.connectionState == ConnectionState.done &&
                  snapshot.data?.isNotEmpty == true &&
                  _hasMore)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                    child: OutlinedButton.icon(
                      onPressed: () => _loadMore(snapshot.data!),
                      icon: const Icon(Icons.expand_more),
                      label: const Text('Load more courses'),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({
    required this.course,
    required this.storageService,
    required this.isEnrolled,
    required this.isPreview,
    required this.onEnroll,
    required this.onReview,
    required this.onOpen,
  });

  final Course course;
  final StorageService? storageService;
  final bool isEnrolled;
  final bool isPreview;
  final VoidCallback onEnroll;
  final VoidCallback onReview;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 360,
      child: ExploreCourseCard(
        course: course,
        storageService: storageService,
        isEnrolled: isEnrolled,
        isPreview: isPreview,
        onEnroll: onEnroll,
        onReview: onReview,
        onOpen: onOpen,
      ),
    );
  }
}

class _LearningPage extends StatelessWidget {
  const _LearningPage({
    required this.courseService,
    required this.supabaseConfigured,
    required this.storageService,
  });

  final CourseService courseService;
  final bool supabaseConfigured;
  final StorageService? storageService;

  @override
  Widget build(BuildContext context) {
    if (!supabaseConfigured) {
      return const _SimplePage(
        title: 'My learning',
        icon: Icons.menu_book_outlined,
        message:
            'Connect a Supabase project and sign in to save your enrollments.',
      );
    }

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return _SimplePage(
        title: 'My learning',
        icon: Icons.menu_book_outlined,
        message: 'Sign in to keep track of the courses you join.',
        action: FilledButton(
          onPressed: () => context.push<void>('/login'),
          child: const Text('Sign in'),
        ),
      );
    }
    if (user.emailConfirmedAt == null &&
        user.appMetadata['provider'] == 'email') {
      return _SimplePage(
        title: 'Verify your email',
        icon: Icons.mark_email_unread_outlined,
        message:
            'Verify your email before opening protected learning features.',
        action: FilledButton(
          onPressed: () => context.push<void>(
            '/check-email?email=${Uri.encodeQueryComponent(user.email ?? '')}',
          ),
          child: const Text('Check email'),
        ),
      );
    }

    return FutureBuilder<List<Course>>(
      future: courseService.getEnrolledCourses(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _SimplePage(
            title: 'My learning',
            icon: Icons.menu_book_outlined,
            message: 'Your enrollments could not be loaded. Try again later.',
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.isEmpty) {
          return const _SimplePage(
            title: 'My learning',
            icon: Icons.menu_book_outlined,
            message: 'You have not enrolled in any courses yet.',
          );
        }

        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
            children: [
              Text(
                'My learning',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              for (final course in snapshot.data!) ...[
                _CourseCard(
                  course: course,
                  storageService: storageService,
                  isEnrolled: true,
                  isPreview: false,
                  onEnroll: () {},
                  onReview: () => context.push('/courses/${course.id}'),
                  onOpen: () => context.push('/courses/${course.id}'),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SimplePage extends StatelessWidget {
  const _SimplePage({
    required this.title,
    required this.icon,
    required this.message,
    this.action,
  });

  final String title;
  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          ),
        ),
      ),
    );
  }
}

const _ink = AppTheme.textPrimary;
const _muted = AppTheme.textMuted;
const _paper = AppTheme.midnight;
const _lime = AppTheme.teal;
const _line = Color(0xFF2D3853);
const _purple = Color(0xFF26345D);

/// Supply your own HTTPS profile URLs here or through [SkillBridgeHome.socialLinks].
/// Missing URLs render as disabled, clearly labelled social buttons.
const skillBridgeSocialLinks = <String, String>{
  // 'Facebook': 'https://www.facebook.com/YOUR_PAGE',
  // 'LinkedIn': 'https://www.linkedin.com/company/YOUR_PAGE',
  // 'Instagram': 'https://www.instagram.com/YOUR_PAGE',
  // 'X': 'https://x.com/YOUR_HANDLE',
};

class SkillBridgeHome extends StatefulWidget {
  const SkillBridgeHome({
    super.key,
    required this.onExplore,
    required this.onOpenCourse,
    required this.loadCourses,
    required this.supabaseConfigured,
    this.storageService,
    this.socialLinks = skillBridgeSocialLinks,
  });

  final VoidCallback onExplore;
  final ValueChanged<Course> onOpenCourse;
  final Future<List<Course>> Function() loadCourses;
  final bool supabaseConfigured;
  final StorageService? storageService;
  final Map<String, String> socialLinks;

  @override
  State<SkillBridgeHome> createState() => _SkillBridgeHomeState();
}

class _SkillBridgeHomeState extends State<SkillBridgeHome>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  late Future<List<Course>> _courses = widget.loadCourses();
  final _howItWorksKey = GlobalKey();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _entrance.value = 1;
    } else if (_entrance.status == AnimationStatus.dismissed) {
      _entrance.forward();
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  void _showHowItWorks() {
    final target = _howItWorksKey.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 550),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final inheritedText = Theme.of(context).textTheme;
    return Theme(
      data: AppTheme.dark.copyWith(
        textTheme: inheritedText.apply(
          bodyColor: AppTheme.textPrimary,
          displayColor: AppTheme.textPrimary,
        ),
      ),
      child: ColoredBox(
        color: _paper,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 850;
              final inset = constraints.maxWidth < 500 ? 20.0 : 40.0;
              return SingleChildScrollView(
                key: const PageStorageKey('skillbridge-home'),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1280),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(inset, 24, inset, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _header(wide),
                          const SizedBox(height: 36),
                          _Reveal(animation: _entrance, child: _hero(wide)),
                          const SizedBox(height: 24),
                          _principles(),
                          const SizedBox(height: 56),
                          _featured(),
                          const SizedBox(height: 56),
                          _howItWorks(),
                          const SizedBox(height: 36),
                          _invitation(),
                          const SizedBox(height: 56),
                          _footer(),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header(bool wide) => Row(
    children: [
      const Expanded(
        child: Align(alignment: Alignment.centerLeft, child: _Brand()),
      ),
      if (wide)
        TextButton(
          onPressed: _showHowItWorks,
          child: const Text('How it works'),
        ),
      const SizedBox(width: 8),
      IconButton.filledTonal(
        tooltip: 'Explore courses',
        onPressed: widget.onExplore,
        style: IconButton.styleFrom(
          backgroundColor: _lime,
          foregroundColor: AppTheme.midnight,
        ),
        icon: const Icon(Icons.north_east_rounded),
      ),
    ],
  );

  Widget _hero(bool wide) {
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Eyebrow(
          'SKILLBRIDGE · PEER LEARNING PLATFORM',
          icon: Icons.hub_outlined,
        ),
        const SizedBox(height: 24),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Your next chapter.\n'),
              TextSpan(
                text: 'Better together.',
                style: TextStyle(
                  color: AppTheme.teal,
                  backgroundColor: _lime.withValues(alpha: .14),
                ),
              ),
            ],
          ),
          style: TextStyle(
            fontSize: wide ? 57 : 40,
            height: 1.1,
            letterSpacing: -1.9,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'A skill you can share. A future you can build.\n'
          'Discover practical courses, exchange ideas, and turn curiosity '
          'into confidence with SkillBridge.',
          style: TextStyle(fontSize: 17, height: 1.7, color: _muted),
        ),
        const SizedBox(height: 28),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: widget.onExplore,
              label: const Text('Find your next skill'),
              icon: const Icon(Icons.arrow_forward_rounded, size: 20),
              iconAlignment: IconAlignment.end,
            ),
            TextButton.icon(
              onPressed: _showHowItWorks,
              icon: const Icon(Icons.play_circle_outline_rounded),
              label: const Text('See how it works'),
            ),
          ],
        ),
        const SizedBox(height: 28),
        const Wrap(
          spacing: 20,
          runSpacing: 10,
          children: [
            _SmallFact(Icons.people_alt_outlined, 'Learn from peers'),
            _SmallFact(Icons.bolt_outlined, 'Build real skills'),
          ],
        ),
      ],
    );
    return Container(
      padding: EdgeInsets.all(wide ? 36 : 22),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(32),
      ),
      child: wide
          ? Row(
              children: [
                Expanded(flex: 6, child: copy),
                const SizedBox(width: 24),
                const Expanded(flex: 5, child: _NetworkArt()),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                copy,
                const SizedBox(height: 32),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: const _NetworkArt(),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _principles() => const Wrap(
    spacing: 28,
    runSpacing: 14,
    children: [
      _SmallFact(Icons.all_inclusive_rounded, 'Curiosity has no limits'),
      _SmallFact(Icons.handshake_outlined, 'Knowledge goes both ways'),
      _SmallFact(Icons.trending_up_rounded, 'Small steps. Lasting growth.'),
    ],
  );

  Widget _featured() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _Eyebrow('THE NEXT STEP IS YOURS'),
      const SizedBox(height: 10),
      Wrap(
        spacing: 24,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text(
            'Find your spark.',
            style: TextStyle(
              fontSize: 32,
              letterSpacing: -1,
              fontWeight: FontWeight.w800,
            ),
          ),
          TextButton.icon(
            onPressed: widget.onExplore,
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            iconAlignment: IconAlignment.end,
            label: const Text('Explore all courses'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        widget.supabaseConfigured
            ? 'A few courses to start a new possibility.'
            : 'A taste of what you can learn. These are sample courses.',
        style: const TextStyle(color: _muted, height: 1.5),
      ),
      const SizedBox(height: 24),
      FutureBuilder<List<Course>>(
        future: _courses,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _StatusPanel(
              icon: Icons.cloud_off_outlined,
              title: 'A little pause in the connection.',
              message: 'We couldn’t load courses. Try again when you’re ready.',
              action: OutlinedButton.icon(
                onPressed: () => setState(() {
                  _courses = widget.loadCourses();
                }),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            );
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const _StatusPanel(
              icon: Icons.auto_stories_outlined,
              title: 'Finding your next possibility…',
              message: 'Loading courses',
              action: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          final courses = (snapshot.data ?? <Course>[]).take(3).toList();
          if (courses.isEmpty) {
            return _StatusPanel(
              icon: Icons.spa_outlined,
              title: 'Something good is growing.',
              message: 'New courses will appear here once they’re published.',
              action: TextButton(
                onPressed: widget.onExplore,
                child: const Text('Open course explorer'),
              ),
            );
          }
          return LayoutBuilder(
            builder: (context, box) {
              final columns = box.maxWidth >= 920
                  ? 3
                  : box.maxWidth >= 600
                  ? 2
                  : 1;
              final width = (box.maxWidth - (columns - 1) * 18) / columns;
              return Wrap(
                spacing: 18,
                runSpacing: 18,
                children: [
                  for (var i = 0; i < courses.length; i++)
                    SizedBox(
                      width: width,
                      child: _FeaturedCourse(
                        course: courses[i],
                        storageService: widget.storageService,
                        preview: !widget.supabaseConfigured,
                        onTap: () => widget.onOpenCourse(courses[i]),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    ],
  );

  Widget _howItWorks() => Column(
    key: _howItWorksKey,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _Eyebrow('A LITTLE CURIOSITY. A LOT OF POSSIBILITY.'),
      const SizedBox(height: 12),
      const Text(
        'Good things happen when we share.',
        style: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w800,
          letterSpacing: -.8,
        ),
      ),
      const SizedBox(height: 24),
      LayoutBuilder(
        builder: (context, box) {
          final width = box.maxWidth >= 800
              ? (box.maxWidth - 36) / 3
              : box.maxWidth;
          return Wrap(
            spacing: 18,
            runSpacing: 18,
            children: [
              for (final item in const [
                (
                  Icons.explore_outlined,
                  '01',
                  'Follow your curiosity',
                  'Explore a subject you’ve always wanted to understand.',
                ),
                (
                  Icons.forum_outlined,
                  '02',
                  'Bring your perspective',
                  'Learn from another point of view and share what you know.',
                ),
                (
                  Icons.rocket_launch_outlined,
                  '03',
                  'Make it your own',
                  'Put new ideas into practice, one meaningful step at a time.',
                ),
              ])
                SizedBox(
                  width: width,
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      border: Border.all(color: _line),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(item.$1, size: 28),
                            const Spacer(),
                            Text(
                              item.$2,
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Text(
                          item.$3,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          item.$4,
                          style: const TextStyle(color: _muted, height: 1.6),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );

  Widget _invitation() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      color: AppTheme.panelRaised,
      borderRadius: BorderRadius.circular(26),
    ),
    child: Wrap(
      spacing: 28,
      runSpacing: 22,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Icon(Icons.auto_awesome_rounded, size: 36),
        const Text(
          'You know something.\nSomeone needs to learn it.',
          style: TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w800,
            height: 1.25,
            letterSpacing: -.6,
          ),
        ),
        FilledButton.icon(
          onPressed: widget.onExplore,
          icon: const Icon(Icons.north_east_rounded),
          label: const Text('Start exploring'),
        ),
      ],
    ),
  );

  Widget _footer() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Divider(color: _line),
      const SizedBox(height: 28),
      const _Brand(),
      const SizedBox(height: 16),
      const Text(
        'A bridge between what you know\nand what you could become.',
        style: TextStyle(color: _muted, height: 1.7, fontSize: 15),
      ),
      const SizedBox(height: 24),
      const Text(
        'STAY IN THE LOOP',
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 1.8,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final social in const [
            ('Facebook', FontAwesomeIcons.facebookF),
            ('LinkedIn', FontAwesomeIcons.linkedinIn),
            ('Instagram', FontAwesomeIcons.instagram),
            ('X', FontAwesomeIcons.xTwitter),
          ])
            _SocialLink(
              label: social.$1,
              icon: social.$2,
              url: widget.socialLinks[social.$1],
            ),
        ],
      ),
      const SizedBox(height: 32),
      const Divider(color: _line),
      const SizedBox(height: 12),
      Text(
        '© ${DateTime.now().year} SkillBridge. Keep growing, together.',
        style: const TextStyle(fontSize: 12, color: _muted, height: 1.6),
      ),
    ],
  );
}

class _Brand extends StatelessWidget {
  const _Brand();
  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppTheme.panelRaised,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.hub_rounded, color: _lime, size: 23),
        ),
        const SizedBox(width: 9),
        const Text(
          'SkillBridge',
          style: TextStyle(
            color: _ink,
            fontSize: 23,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
          ),
        ),
      ],
    ),
  );
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text, {this.icon});
  final String text;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 6,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      if (icon != null) Icon(icon, size: 17, color: _ink),
      Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          letterSpacing: 1.6,
          fontWeight: FontWeight.w700,
          height: 1.5,
        ),
      ),
    ],
  );
}

class _SmallFact extends StatelessWidget {
  const _SmallFact(this.icon, this.label);
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 17, color: _muted),
      const SizedBox(width: 7),
      Flexible(
        child: Text(label, style: const TextStyle(fontSize: 12, color: _muted)),
      ),
    ],
  );
}

class _Reveal extends StatelessWidget {
  const _Reveal({required this.animation, required this.child});
  final Animation<double> animation;
  final Widget child;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (context, child) {
      final t = Curves.easeOutCubic.transform(animation.value);
      return Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 22 * (1 - t)),
          child: child,
        ),
      );
    },
  );
}

/// Code-drawn artwork: no image downloads or asset setup required.
class _NetworkArt extends StatelessWidget {
  const _NetworkArt();
  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: 'A network of connected skills: design, code, and ideas.',
    child: ExcludeSemantics(
      child: MediaQuery.withNoTextScaling(
        child: AspectRatio(
          aspectRatio: 1.08,
          child: LayoutBuilder(
            builder: (context, box) {
              final scale = box.maxWidth / 420;
              return FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: 420,
                  height: 389,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const Positioned.fill(
                        child: CustomPaint(painter: _OrbitPainter()),
                      ),
                      Transform.rotate(
                        angle: -.12,
                        child: Container(
                          width: 164,
                          height: 164,
                          decoration: BoxDecoration(
                            color: AppTheme.panelRaised,
                            borderRadius: BorderRadius.circular(46),
                            boxShadow: [
                              BoxShadow(
                                color: _ink.withValues(alpha: .15),
                                blurRadius: 35,
                                offset: const Offset(0, 20),
                              ),
                            ],
                          ),
                          child: Transform.rotate(
                            angle: .12,
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.hub_rounded, color: _lime, size: 65),
                                SizedBox(height: 10),
                                Text(
                                  'GROW TOGETHER',
                                  style: TextStyle(
                                    color: _lime,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const Positioned(
                        left: 12,
                        top: 35,
                        child: _ArtTile(
                          icon: Icons.draw_outlined,
                          label: 'Design',
                          color: _purple,
                          angle: -.1,
                        ),
                      ),
                      const Positioned(
                        right: 4,
                        top: 66,
                        child: _ArtTile(
                          icon: Icons.code_rounded,
                          label: 'Build',
                          color: _lime,
                          angle: .1,
                        ),
                      ),
                      const Positioned(
                        left: 25,
                        bottom: 28,
                        child: _ArtTile(
                          icon: Icons.lightbulb_outline_rounded,
                          label: 'Discover',
                          color: Color(0xFF624A3A),
                          angle: .06,
                        ),
                      ),
                      Positioned(
                        right: 5,
                        bottom: 40,
                        child: Container(
                          width: 162,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppTheme.panelRaised,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: _line),
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.north_east_rounded, size: 18),
                                  SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      'YOUR POTENTIAL',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 10),
                              Text(
                                'Limitless.',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              SizedBox(height: 8),
                              LinearProgressIndicator(
                                value: .72,
                                color: _ink,
                                backgroundColor: _lime,
                                minHeight: 5,
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        top: 12,
                        right: 140,
                        child: Icon(
                          Icons.auto_awesome,
                          color: _ink,
                          size: 24 * math.max(.8, scale),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _ArtTile extends StatelessWidget {
  const _ArtTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.angle,
  });
  final IconData icon;
  final String label;
  final Color color;
  final double angle;
  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: angle,
    child: Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _ink.withValues(alpha: .08)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ],
      ),
    ),
  );
}

class _OrbitPainter extends CustomPainter {
  const _OrbitPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = const Color(0xFF40506B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(center, size.width * .34, paint);
    canvas.drawCircle(center, size.width * .46, paint);
    for (var i = 0; i < 4; i++) {
      final angle = math.pi / 4 + i * math.pi / 2;
      final point =
          center + Offset(math.cos(angle), math.sin(angle)) * size.width * .46;
      canvas.drawLine(center, point, paint);
      canvas.drawCircle(point, 5, Paint()..color = _ink);
    }
  }

  @override
  bool shouldRepaint(_OrbitPainter oldDelegate) => false;
}

class _FeaturedCourse extends StatefulWidget {
  const _FeaturedCourse({
    required this.course,
    required this.storageService,
    required this.preview,
    required this.onTap,
  });
  final Course course;
  final StorageService? storageService;
  final bool preview;
  final VoidCallback onTap;
  @override
  State<_FeaturedCourse> createState() => _FeaturedCourseState();
}

class _FeaturedCourseState extends State<_FeaturedCourse> {
  bool _hovered = false;
  bool _focused = false;
  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      transform: Matrix4.translationValues(0, _hovered || _focused ? -5 : 0, 0),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _hovered || _focused ? _ink : _line),
        boxShadow: [
          if (_hovered || _focused)
            BoxShadow(
              color: _ink.withValues(alpha: .07),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          onHover: (value) => setState(() => _hovered = value),
          onFocusChange: (value) => setState(() => _focused = value),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  height: 150,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CourseArtwork(
                        course: widget.course,
                        storageService: widget.storageService,
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x12000000), Color(0x55000000)],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 12,
                        top: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.panelRaised.withValues(alpha: .94),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            widget.preview ? 'SAMPLE COURSE' : 'DISCOVER',
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  widget.course.category.toUpperCase(),
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.course.title,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.5,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.course.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _muted,
                    height: 1.6,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 18),
                const Divider(color: _line),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.person_outline_rounded,
                      size: 17,
                      color: _muted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.course.instructor,
                        style: const TextStyle(fontSize: 12, color: _muted),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.north_east_rounded, size: 20),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  widget.course.level,
                  style: const TextStyle(fontSize: 11, color: _muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
  });
  final IconData icon;
  final String title;
  final String message;
  final Widget action;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      border: Border.all(color: _line),
      borderRadius: BorderRadius.circular(24),
    ),
    child: Column(
      children: [
        Icon(icon, size: 32),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 19),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted, height: 1.6),
        ),
        const SizedBox(height: 18),
        action,
      ],
    ),
  );
}

class _SocialLink extends StatelessWidget {
  const _SocialLink({required this.label, required this.icon, this.url});
  final String label;
  final FaIconData icon;
  final String? url;

  Future<void> _open(BuildContext context, Uri uri) async {
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.platformDefault);
      if (!opened && context.mounted) _failed(context);
    } catch (_) {
      if (context.mounted) _failed(context);
    }
  }

  void _failed(BuildContext context) => ScaffoldMessenger.of(context)
      .showSnackBar(
        SnackBar(content: Text('Couldn’t open $label. Please try again.')),
      );

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(url ?? '');
    final enabled = uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
    return Tooltip(
      message: enabled
          ? 'Open SkillBridge on $label'
          : '$label profile coming soon',
      child: OutlinedButton.icon(
        onPressed: enabled ? () => _open(context, uri) : null,
        style: OutlinedButton.styleFrom(
          foregroundColor: _ink,
          side: const BorderSide(color: _line),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
        icon: FaIcon(icon, size: 16),
        label: Text(label),
      ),
    );
  }
}
