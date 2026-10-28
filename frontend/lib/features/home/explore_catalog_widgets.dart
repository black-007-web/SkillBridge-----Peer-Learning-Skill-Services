import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../models/course_model.dart';
import '../../models/user_profile.dart';
import '../../services/course_service.dart';
import '../../services/profile_service.dart';
import '../../services/storage_service.dart';

class ExploreBanner extends StatelessWidget {
  const ExploreBanner({super.key, required this.onLecturers});

  final VoidCallback onLecturers;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF202C50), Color(0xFF123A3D), Color(0xFF10182B)],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Build your next skill',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  'Explore expert-led learning, one course at a time.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: onLecturers,
                  icon: const Icon(Icons.verified_outlined, size: 18),
                  label: const Text('Meet our lecturers'),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.auto_awesome,
            size: 46,
            color: colors.secondary.withValues(alpha: 0.9),
          ),
        ],
      ),
    );
  }
}

class ExploreCourseCard extends StatelessWidget {
  const ExploreCourseCard({
    super.key,
    required this.course,
    required this.isEnrolled,
    required this.isPreview,
    required this.onEnroll,
    required this.onReview,
    required this.onOpen,
    this.storageService,
  });

  final Course course;
  final bool isEnrolled;
  final bool isPreview;
  final VoidCallback onEnroll;
  final VoidCallback onReview;
  final VoidCallback onOpen;
  final StorageService? storageService;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 128,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CourseArtwork(course: course, storageService: storageService),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.08),
                        Colors.black.withValues(alpha: 0.66),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Row(
                    children: [
                      Flexible(child: _CoverLabel(label: course.category)),
                      const Spacer(),
                      _CoverLabel(label: course.level),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    course.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    course.description.trim().isEmpty
                        ? 'A practical course designed to help you build real-world skills.'
                        : course.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(height: 1.3),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.person_outline,
                        size: 16,
                        color: colors.secondary,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          course.instructor,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          course.level,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: isEnrolled ? onOpen : onEnroll,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 40),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                          child: Text(
                            isEnrolled
                                ? 'Continue'
                                : isPreview
                                ? 'Preview'
                                : 'Enroll',
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: isEnrolled ? onReview : onOpen,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 40),
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                          child: Text(isEnrolled ? 'Review' : 'Details'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CourseArtwork extends StatefulWidget {
  const CourseArtwork({super.key, required this.course, this.storageService});

  final Course course;
  final StorageService? storageService;

  @override
  State<CourseArtwork> createState() => _CourseArtworkState();
}

class _CourseArtworkState extends State<CourseArtwork> {
  Future<String>? _signedCover;

  @override
  void initState() {
    super.initState();
    _loadCover();
  }

  @override
  void didUpdateWidget(covariant CourseArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.course.coverImagePath != widget.course.coverImagePath ||
        oldWidget.storageService != widget.storageService) {
      _loadCover();
    }
  }

  void _loadCover() {
    final path = widget.course.coverImagePath?.trim();
    final storage = widget.storageService;
    _signedCover = path != null &&
            path.contains('/course_covers/') &&
            storage != null
        ? storage.signedCourseCoverUrl(path)
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.course.coverImagePath?.trim();
    final uri = path == null ? null : Uri.tryParse(path);
    if (uri != null && uri.scheme == 'https' && uri.host.isNotEmpty) {
      return Image.network(
        uri.toString(),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            _CourseArtworkFallback(course: widget.course),
      );
    }
    if (_signedCover != null) {
      return FutureBuilder<String>(
        future: _signedCover,
        builder: (context, snapshot) {
          if (snapshot.hasError || !snapshot.hasData) {
            return _CourseArtworkFallback(course: widget.course);
          }
          return Image.network(
            snapshot.data!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                _CourseArtworkFallback(course: widget.course),
          );
        },
      );
    }
    return _CourseArtworkFallback(course: widget.course);
  }
}

class _CourseArtworkFallback extends StatelessWidget {
  const _CourseArtworkFallback({required this.course});

  final Course course;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _artworkColors(course.category),
            ),
          ),
        ),
        Positioned(
          right: -24,
          top: -50,
          child: Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
          ),
        ),
        Positioned(
          right: 18,
          bottom: 14,
          child: Icon(
            _categoryIcon(course.category),
            size: 68,
            color: Colors.white.withValues(alpha: 0.2),
          ),
        ),
        const Positioned(
          left: 18,
          top: 18,
          child: Icon(Icons.auto_awesome, color: Colors.white70, size: 20),
        ),
      ],
    );
  }
}

List<Color> _artworkColors(String category) {
  final value = category.toLowerCase();
  if (value.contains('design') || value.contains('art')) {
    return const [Color(0xFF752E7D), Color(0xFF352C72)];
  }
  if (value.contains('business') || value.contains('market')) {
    return const [Color(0xFF9A512E), Color(0xFF4F345E)];
  }
  if (value.contains('data') || value.contains('science')) {
    return const [Color(0xFF176B79), Color(0xFF263B77)];
  }
  return const [Color(0xFF3752A4), Color(0xFF14786F)];
}

IconData _categoryIcon(String category) {
  final value = category.toLowerCase();
  if (value.contains('design') || value.contains('art')) {
    return Icons.palette_outlined;
  }
  if (value.contains('business') || value.contains('market')) {
    return Icons.insights_outlined;
  }
  if (value.contains('data') || value.contains('science')) {
    return Icons.query_stats_outlined;
  }
  if (value.contains('code') || value.contains('tech')) {
    return Icons.code_rounded;
  }
  return Icons.school_outlined;
}

class _CoverLabel extends StatelessWidget {
  const _CoverLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.34),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

class LecturerDirectoryPage extends StatefulWidget {
  const LecturerDirectoryPage({super.key, required this.supabaseConfigured});

  final bool supabaseConfigured;

  @override
  State<LecturerDirectoryPage> createState() => _LecturerDirectoryPageState();
}

class _LecturerDirectoryPageState extends State<LecturerDirectoryPage> {
  final _searchController = TextEditingController();
  late Future<List<UserProfile>> _lecturers;
  ProfileService? _profileService;
  StorageService? _storageService;

  @override
  void initState() {
    super.initState();
    if (widget.supabaseConfigured) {
      final client = Supabase.instance.client;
      _profileService = ProfileService(client);
      _storageService = StorageService(client);
    }
    _lecturers = _loadLecturers();
  }

  Future<List<UserProfile>> _loadLecturers() async {
    final service = _profileService;
    if (service == null) return const [];
    return service.getPublicLecturers();
  }

  void _reload() => setState(() => _lecturers = _loadLecturers());

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: FutureBuilder<List<UserProfile>>(
      future: _lecturers,
      builder: (context, snapshot) {
        final allLecturers = snapshot.data ?? const <UserProfile>[];
        final query = _searchController.text.trim().toLowerCase();
        final lecturers = allLecturers
            .where((profile) {
              if (query.isEmpty) return true;
              return [
                profile.fullName,
                profile.position,
                profile.bio,
                ...profile.skills,
              ].any((value) => value.toLowerCase().contains(query));
            })
            .toList(growable: false);

        return CustomScrollView(
          slivers: [
            SliverAppBar(
              title: const Text('Verified lecturers'),
              floating: true,
              actions: [
                IconButton(
                  tooltip: 'Refresh lecturer directory',
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
                child: _LecturersBanner(count: allLecturers.length),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Search lecturers, skills, or roles',
                    prefixIcon: Icon(Icons.search),
                  ),
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
                        const Text('The lecturer directory could not load.'),
                        const SizedBox(height: 8),
                        Text(
                          '${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
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
            else if (lecturers.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      query.isEmpty
                          ? 'No verified lecturers are available yet.'
                          : 'No lecturers match that search.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              )
            else
              SliverLayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.crossAxisExtent >= 1000
                      ? 3
                      : constraints.crossAxisExtent >= 620
                      ? 2
                      : 1;
                  return SliverPadding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 26),
                    sliver: SliverGrid.builder(
                      itemCount: lecturers.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisExtent: 470,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                      ),
                      itemBuilder: (context, index) => _LecturerCard(
                        profile: lecturers[index],
                        storageService: _storageService,
                      ),
                    ),
                  );
                },
              ),
          ],
        );
      },
    ),
  );
}

class _LecturersBanner extends StatelessWidget {
  const _LecturersBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.secondary.withValues(alpha: 0.24)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF143D43), Color(0xFF1F2D50), Color(0xFF11182B)],
        ),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Learn from people who do it.',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 6),
                Text(
                  'Meet our approved educators and discover their expertise.',
                  style: TextStyle(color: Colors.white70, height: 1.35),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            children: [
              Icon(Icons.verified, color: colors.secondary, size: 30),
              const SizedBox(height: 4),
              Text('$count', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ],
      ),
    );
  }
}

class _LecturerCard extends StatelessWidget {
  const _LecturerCard({required this.profile, required this.storageService});

  final UserProfile profile;
  final StorageService? storageService;

  @override
  Widget build(BuildContext context) {
    final path = profile.avatarPath;
    final storage = storageService;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 184,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _LecturerCover(
                  path: profile.coverImagePath,
                  storageService: storage,
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x16000000), Color(0x68000000)],
                    ),
                  ),
                ),
                const Positioned(
                  top: 13,
                  right: 13,
                  child: _CoverLabel(label: 'VERIFIED'),
                ),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppTheme.panel,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: AppTheme.teal.withValues(alpha: 0.9),
                        width: 2,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x66000000),
                          blurRadius: 18,
                          offset: Offset(0, 7),
                        ),
                      ],
                    ),
                    child: _LecturerAvatar(
                      profile: profile,
                      path: path,
                      storageService: storage,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 11, 14, 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.fullName.isEmpty
                        ? 'SkillBridge lecturer'
                        : profile.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    profile.position.trim().isEmpty
                        ? 'Verified lecturer'
                        : profile.position,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                  if (profile.bio.trim().isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Text(
                      profile.bio,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (profile.skills.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: profile.skills
                          .take(3)
                          .map((skill) {
                            return ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 130),
                              child: _CoverLabel(label: skill),
                            );
                          })
                          .toList(growable: false),
                    ),
                  ],
                  const Spacer(),
                  if (profile.socialLinks.isNotEmpty)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: profile.socialLinks.entries
                            .take(3)
                            .map((entry) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: _SocialLinkChip(
                                  label: entry.key,
                                  url: entry.value,
                                ),
                              );
                            })
                            .toList(growable: false),
                      ),
                    )
                  else
                    Text(
                      'Sharing expertise on SkillBridge',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () =>
                          context.push('/lecturers/${profile.id}/courses'),
                      icon: const Icon(Icons.menu_book_outlined, size: 18),
                      label: const Text('View courses'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LecturerAvatar extends StatefulWidget {
  const _LecturerAvatar({
    required this.profile,
    required this.path,
    required this.storageService,
  });

  final UserProfile profile;
  final String? path;
  final StorageService? storageService;

  @override
  State<_LecturerAvatar> createState() => _LecturerAvatarState();
}

class _LecturerAvatarState extends State<_LecturerAvatar> {
  Future<String>? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _loadAvatarUrl();
  }

  @override
  void didUpdateWidget(covariant _LecturerAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.storageService != widget.storageService) {
      _loadAvatarUrl();
    }
  }

  void _loadAvatarUrl() {
    final path = widget.path;
    final storage = widget.storageService;
    _avatarUrl = path == null || storage == null
        ? null
        : storage.signedAvatarUrl(path);
  }

  @override
  Widget build(BuildContext context) {
    final avatarUrl = _avatarUrl;
    if (avatarUrl == null) {
      return _placeholder();
    }
    return FutureBuilder<String>(
      future: avatarUrl,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.hasError) return _placeholder();
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.network(
            snapshot.data!,
            width: 140,
            height: 140,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _placeholder(),
          ),
        );
      },
    );
  }

  Widget _placeholder() => Container(
    width: 140,
    height: 140,
    decoration: BoxDecoration(
      color: AppTheme.panelRaised,
      borderRadius: BorderRadius.circular(16),
    ),
    alignment: Alignment.center,
    child: Text(
      _initials(widget.profile.fullName),
      style: const TextStyle(
        color: AppTheme.textPrimary,
        fontSize: 30,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _LecturerCover extends StatefulWidget {
  const _LecturerCover({required this.path, required this.storageService});

  final String? path;
  final StorageService? storageService;

  @override
  State<_LecturerCover> createState() => _LecturerCoverState();
}

class _LecturerCoverState extends State<_LecturerCover> {
  Future<String>? _coverUrl;

  @override
  void initState() {
    super.initState();
    _loadCover();
  }

  @override
  void didUpdateWidget(covariant _LecturerCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.storageService != widget.storageService) {
      _loadCover();
    }
  }

  void _loadCover() {
    final path = widget.path;
    final storage = widget.storageService;
    _coverUrl = path == null || storage == null
        ? null
        : storage.signedAvatarUrl(path);
  }

  @override
  Widget build(BuildContext context) {
    final coverUrl = _coverUrl;
    if (coverUrl == null) return const _LecturerArtworkFallback();
    return FutureBuilder<String>(
      future: coverUrl,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.hasError) {
          return const _LecturerArtworkFallback();
        }
        return Image.network(
          snapshot.data!,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const _LecturerArtworkFallback(),
        );
      },
    );
  }
}

class _LecturerArtworkFallback extends StatelessWidget {
  const _LecturerArtworkFallback();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF234A72), Color(0xFF274878), Color(0xFF236A66)],
      ),
    ),
    child: Stack(
      children: [
        Positioned(
          right: -20,
          top: -45,
          child: Icon(Icons.blur_on, size: 190, color: Color(0x24FFFFFF)),
        ),
        Positioned(
          left: 18,
          top: 22,
          child: Icon(Icons.auto_awesome, size: 22, color: Colors.white70),
        ),
      ],
    ),
  );
}

class LecturerCoursesPage extends StatefulWidget {
  const LecturerCoursesPage({
    super.key,
    required this.lecturerId,
    required this.supabaseConfigured,
  });

  final String lecturerId;
  final bool supabaseConfigured;

  @override
  State<LecturerCoursesPage> createState() => _LecturerCoursesPageState();
}

class _LecturerCoursesPageState extends State<LecturerCoursesPage> {
  late final ProfileService? _profileService;
  late final StorageService? _storageService;
  late final CourseService _courseService;
  late final Future<({UserProfile? lecturer, List<Course> courses})>
  _directoryData;
  Set<String> _enrolledCourseIds = {};

  @override
  void initState() {
    super.initState();
    final client = widget.supabaseConfigured ? Supabase.instance.client : null;
    _profileService = client == null ? null : ProfileService(client);
    _storageService = client == null ? null : StorageService(client);
    _courseService = CourseService(client: client);
    _directoryData = _loadDirectoryData();
    _loadEnrollments();
  }

  Future<({UserProfile? lecturer, List<Course> courses})>
  _loadDirectoryData() async {
    final service = _profileService;
    if (service == null) {
      return (lecturer: null, courses: const <Course>[]);
    }
    final lecturers = await service.getPublicLecturers();
    final lecturer = lecturers
        .where((profile) => profile.id == widget.lecturerId)
        .firstOrNull;
    if (lecturer == null) {
      return (lecturer: null, courses: const <Course>[]);
    }
    final courses = await _courseService.getLecturerCourses(lecturer.id);
    return (lecturer: lecturer, courses: courses);
  }

  Future<void> _loadEnrollments() async {
    if (!widget.supabaseConfigured ||
        Supabase.instance.client.auth.currentUser == null) {
      return;
    }
    try {
      final ids = await _courseService.getEnrolledCourseIds();
      if (mounted) setState(() => _enrolledCourseIds = ids.toSet());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Enrollment status unavailable: $error')),
        );
      }
    }
  }

  Future<void> _enroll(Course course) async {
    if (!widget.supabaseConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connect Supabase to enroll.')),
      );
      return;
    }
    var user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      await context.push<void>('/login');
      if (!mounted) return;
      user = Supabase.instance.client.auth.currentUser;
    }
    if (user == null) return;
    if (user.emailConfirmedAt == null &&
        user.appMetadata['provider'] == 'email') {
      await context.push<void>(
        '/check-email?email=${Uri.encodeQueryComponent(user.email ?? '')}',
      );
      if (!mounted) return;
      user = Supabase.instance.client.auth.currentUser;
      if (user?.emailConfirmedAt == null) return;
    }
    try {
      await _courseService.enroll(course.id);
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Lecturer courses')),
    body: FutureBuilder<({UserProfile? lecturer, List<Course> courses})>(
      future: _directoryData,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 42),
                  const SizedBox(height: 12),
                  const Text('Could not load this lecturer’s courses.'),
                  const SizedBox(height: 8),
                  Text(
                    '${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        final lecturer = data.lecturer;
        if (lecturer == null) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('This verified lecturer profile is unavailable.'),
            ),
          );
        }
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 22),
                child: _LecturerProfileHeader(
                  profile: lecturer,
                  storageService: _storageService,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                child: Text(
                  'Published courses',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            ),
            if (data.courses.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text('This lecturer has no published courses yet.'),
                ),
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
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                    sliver: SliverGrid.builder(
                      itemCount: data.courses.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisExtent: 360,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                      ),
                      itemBuilder: (context, index) {
                        final course = data.courses[index];
                        return ExploreCourseCard(
                          course: course,
                          storageService: _storageService,
                          isEnrolled: _enrolledCourseIds.contains(course.id),
                          isPreview: !widget.supabaseConfigured,
                          onEnroll: () => _enroll(course),
                          onReview: () => context.push('/courses/${course.id}'),
                          onOpen: () => context.push('/courses/${course.id}'),
                        );
                      },
                    ),
                  );
                },
              ),
          ],
        );
      },
    ),
  );
}

class _LecturerProfileHeader extends StatelessWidget {
  const _LecturerProfileHeader({
    required this.profile,
    required this.storageService,
  });

  final UserProfile profile;
  final StorageService? storageService;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 184,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _LecturerCover(
                  path: profile.coverImagePath,
                  storageService: storageService,
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x16000000), Color(0x68000000)],
                    ),
                  ),
                ),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppTheme.panel,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: AppTheme.teal.withValues(alpha: 0.9),
                        width: 2,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x66000000),
                          blurRadius: 18,
                          offset: Offset(0, 7),
                        ),
                      ],
                    ),
                    child: _LecturerAvatar(
                      profile: profile,
                      path: profile.avatarPath,
                      storageService: storageService,
                    ),
                  ),
                ),
                const Positioned(
                  right: 12,
                  top: 12,
                  child: _CoverLabel(label: 'VERIFIED LECTURER'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        profile.fullName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    Icon(
                      Icons.verified,
                      color: Theme.of(context).colorScheme.secondary,
                      size: 21,
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  profile.position.isEmpty
                      ? 'Verified lecturer'
                      : profile.position,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (profile.bio.trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(profile.bio),
                ],
                if (profile.skills.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: profile.skills
                        .map((skill) {
                          return Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(skill),
                          );
                        })
                        .toList(growable: false),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SocialLinkChip extends StatelessWidget {
  const _SocialLinkChip({required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) => ActionChip(
    visualDensity: VisualDensity.compact,
    avatar: const Icon(Icons.open_in_new, size: 13),
    label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    onPressed: () async {
      final uri = Uri.tryParse(url);
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This profile link is not valid.')),
        );
        return;
      }
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
          context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this profile link.')),
        );
      }
    },
  );
}

String _initials(String name) {
  final words = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty);
  return words.take(2).map((word) => word[0].toUpperCase()).join();
}
