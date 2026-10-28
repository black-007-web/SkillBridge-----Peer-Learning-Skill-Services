import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../providers/auth_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../services/storage_service.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider);
    final roles = ref.watch(currentRolesProvider);
    final user = ref.watch(authServiceProvider)?.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your profile'),
        actions: [
          IconButton(
            tooltip: 'Announcements',
            onPressed: () => context.push('/announcements'),
            icon: const Icon(Icons.campaign_outlined),
          ),
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => context.push('/notifications'),
            icon: const Icon(Icons.notifications_outlined),
          ),
          IconButton(
            tooltip: 'Account settings',
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: profile.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _ProfileFailure(
            onRetry: () => ref.invalidate(currentProfileProvider),
          ),
          data: (value) {
            if (value == null) {
              return const Center(child: Text('Sign in to view your profile.'));
            }
            final storage = ref.watch(storageServiceProvider);
            return ListView(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 30),
              children: [
                Center(
                  child: Column(
                    children: [
                      _ProfileAvatar(path: value.avatarPath, storage: storage),
                      const SizedBox(height: 16),
                      Text(
                        value.fullName.isEmpty
                            ? 'SkillBridge learner'
                            : value.fullName,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        user?.email ?? '',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 10),
                      _StatusPill(
                        verified:
                            user != null &&
                            (user.emailConfirmedAt != null ||
                                user.appMetadata['provider'] != 'email'),
                        verifiedLabel: 'Email verified',
                        unverifiedLabel: 'Email not verified',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        _InfoRow(
                          icon: Icons.phone_outlined,
                          label: 'Phone number',
                          value: _present(value.phoneNumber),
                        ),
                        if (value.position.trim().isNotEmpty)
                          _InfoRow(
                            icon: Icons.work_outline,
                            label: 'Position',
                            value: value.position,
                          ),
                        if (value.skills.isNotEmpty)
                          _InfoRow(
                            icon: Icons.code,
                            label: 'Skills / technologies',
                            value: value.skills.join(', '),
                          ),
                        _InfoRow(
                          icon: Icons.cake_outlined,
                          label: 'Date of birth',
                          value: _date(value.dateOfBirth),
                        ),
                        _InfoRow(
                          icon: Icons.flag_outlined,
                          label: 'Nationality',
                          value: _present(value.nationality),
                        ),
                        _InfoRow(
                          icon: Icons.wc_outlined,
                          label: 'Gender',
                          value: _present(value.gender),
                        ),
                        _InfoRow(
                          icon: Icons.home_outlined,
                          label: 'Address',
                          value: _present(value.address),
                        ),
                        _InfoRow(
                          icon: Icons.calendar_today_outlined,
                          label: 'Member since',
                          value: _date(value.createdAt),
                        ),
                        if (value.bio.trim().isNotEmpty) ...[
                          const Divider(height: 24),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'About',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(value.bio),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (value.socialLinks.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Card(
                    child: Column(
                      children: [
                        for (final entry in value.socialLinks.entries)
                          ListTile(
                            leading: Icon(_socialIcon(entry.key)),
                            title: Text(_socialLabel(entry.key)),
                            subtitle: Text(entry.value),
                            trailing: const Icon(Icons.open_in_new),
                            onTap: () => _openSocialLink(context, entry.value),
                          ),
                      ],
                    ),
                  ),
                ],
                roles.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(12),
                    child: LinearProgressIndicator(),
                  ),
                  error: (error, _) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.cloud_off_outlined),
                      title: const Text('Your workspaces are unavailable.'),
                      subtitle: Text('$error'),
                      trailing: IconButton(
                        tooltip: 'Retry',
                        onPressed: () => ref.invalidate(currentRolesProvider),
                        icon: const Icon(Icons.refresh),
                      ),
                    ),
                  ),
                  data: (value) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your workspaces',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (value.isEmpty)
                            const ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                'No roles are assigned to this account.',
                              ),
                              subtitle: Text(
                                'Contact an administrator if you expected a role workspace here.',
                              ),
                            ),
                          if (value.isEmpty)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () =>
                                    ref.invalidate(currentRolesProvider),
                                icon: const Icon(Icons.refresh),
                                label: const Text('Check roles again'),
                              ),
                            ),
                          if (value.contains('admin'))
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(
                                Icons.admin_panel_settings_outlined,
                              ),
                              title: const Text('Admin dashboard'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => context.push('/admin'),
                            ),
                          if (value.contains('lecturer'))
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(
                                Icons.cast_for_education_outlined,
                              ),
                              title: const Text('Lecturer workspace'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => context.push('/lecturer'),
                            ),
                          if (value.contains('student'))
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.school_outlined),
                              title: const Text('Browse courses'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => context.go('/?tab=explore'),
                            ),
                          if (value.contains('student'))
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.fact_check_outlined),
                              title: const Text('Student verification'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () =>
                                  context.push('/student/verification'),
                            ),
                          if (!value.contains('lecturer') &&
                              !value.contains('admin'))
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(
                                Icons.assignment_ind_outlined,
                              ),
                              title: const Text('Apply to teach'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => context.push('/lecturer/apply'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => context.push('/profile/edit'),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit profile'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => context.push('/settings'),
                  icon: const Icon(Icons.tune_rounded),
                  label: const Text('Account settings'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => context.push('/support'),
                  icon: const Icon(Icons.support_agent_outlined),
                  label: const Text('Help and support'),
                ),
                const SizedBox(height: 26),
                OutlinedButton.icon(
                  onPressed: () async {
                    await ref.read(authServiceProvider)?.signOut();
                    if (context.mounted) context.go('/welcome');
                  },
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Log out'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.path, required this.storage});
  final String? path;
  final StorageService? storage;

  @override
  Widget build(BuildContext context) {
    if (path == null || storage == null) {
      return const CircleAvatar(
        radius: 52,
        child: Icon(Icons.person_outline, size: 46),
      );
    }
    return FutureBuilder<String>(
      future: storage!.signedAvatarUrl(path!),
      builder: (context, snapshot) => CircleAvatar(
        radius: 52,
        backgroundImage: snapshot.hasData ? NetworkImage(snapshot.data!) : null,
        child: snapshot.hasData
            ? null
            : const Icon(Icons.person_outline, size: 46),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.verified,
    required this.verifiedLabel,
    required this.unverifiedLabel,
  });
  final bool verified;
  final String verifiedLabel;
  final String unverifiedLabel;

  @override
  Widget build(BuildContext context) {
    final color = verified
        ? Theme.of(context).colorScheme.secondary
        : Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            verified ? Icons.verified_outlined : Icons.error_outline,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            verified ? verifiedLabel : unverifiedLabel,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.secondary),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(color: Color(0xFFE6EAFA)),
          ),
        ),
      ],
    ),
  );
}

class _ProfileFailure extends StatelessWidget {
  const _ProfileFailure({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_off_outlined, size: 42),
        const SizedBox(height: 12),
        const Text('Profile could not be loaded.'),
        TextButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    ),
  );
}

String _present(String? value) =>
    value == null || value.isEmpty ? 'Not provided' : value;

IconData _socialIcon(String key) => switch (key) {
  'github' => Icons.code,
  'linkedin' => Icons.business_center_outlined,
  'website' => Icons.language,
  _ => Icons.link,
};

String _socialLabel(String key) => switch (key) {
  'github' => 'GitHub',
  'linkedin' => 'LinkedIn',
  'website' => 'Website',
  _ => 'Other profile',
};

Future<void> _openSocialLink(BuildContext context, String value) async {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open this profile link.')),
      );
    }
  }
}

String _date(DateTime? value) => value == null
    ? 'Not provided'
    : '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
