import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../providers/auth_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../services/profile_service.dart';

class AccountSettingsScreen extends ConsumerWidget {
  const AccountSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(notificationPreferencesProvider);
    final service = ref.watch(profileServiceProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Account settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Text('Notifications', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Card(
            child: preferences.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(22),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, _) => ListTile(
                title: const Text('Notification preferences unavailable'),
                trailing: IconButton(
                  onPressed: () =>
                      ref.invalidate(notificationPreferencesProvider),
                  icon: const Icon(Icons.refresh),
                ),
              ),
              data: (values) {
                if (values == null) {
                  return const ListTile(
                    title: Text('Sign in to manage preferences'),
                  );
                }
                return Column(
                  children: [
                    SwitchListTile(
                      title: const Text('Email updates'),
                      subtitle: const Text(
                        'Account and learning activity emails',
                      ),
                      value: values['email_notifications'] ?? true,
                      onChanged: service == null
                          ? null
                          : (value) => _update(
                              context,
                              ref,
                              service,
                              value,
                              values['in_app_notifications'] ?? true,
                            ),
                    ),
                    SwitchListTile(
                      title: const Text('In-app notifications'),
                      subtitle: const Text(
                        'Messages, enrollments, and announcements',
                      ),
                      value: values['in_app_notifications'] ?? true,
                      onChanged: service == null
                          ? null
                          : (value) => _update(
                              context,
                              ref,
                              service,
                              values['email_notifications'] ?? true,
                              value,
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          Text('Security', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.password_outlined),
                  title: const Text('Change password'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/settings/change-password'),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.devices_outlined),
                  title: const Text('Sign out all sessions'),
                  subtitle: const Text('Sign out on this and other devices'),
                  onTap: () => _signOutEverywhere(context, ref),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Account', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Profile details'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/profile'),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: Icon(
                    Icons.delete_outline,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    'Delete account',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/settings/delete-account'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _update(
    BuildContext context,
    WidgetRef ref,
    ProfileService service,
    bool email,
    bool inApp,
  ) async {
    try {
      await service.updateNotificationPreferences(
        emailNotifications: email,
        inAppNotifications: inApp,
      );
      ref.invalidate(notificationPreferencesProvider);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save notification preferences.'),
          ),
        );
      }
    }
  }

  Future<void> _signOutEverywhere(BuildContext context, WidgetRef ref) async {
    final auth = ref.read(authServiceProvider);
    try {
      await auth?.signOutAllSessions();
      if (context.mounted) context.go('/welcome');
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not sign out. Check your connection and try again.',
            ),
          ),
        );
      }
    }
  }
}
