import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_profile.dart';
import 'auth_provider.dart';

final currentProfileProvider = FutureProvider<UserProfile?>((ref) async {
  // The shell keeps its tabs alive. Recompute this provider when auth changes
  // so a pre-login `null` result cannot remain cached after registration.
  ref.watch(authStateProvider);
  final service = ref.watch(profileServiceProvider);
  if (service == null || service.client.auth.currentUser == null) return null;
  return service.getCurrentProfile();
});

final currentRolesProvider = FutureProvider<Set<String>>((ref) async {
  ref.watch(authStateProvider);
  final service = ref.watch(profileServiceProvider);
  if (service == null || service.client.auth.currentUser == null) {
    return const {};
  }
  return (await service.getRoles()).toSet();
});

final notificationPreferencesProvider = FutureProvider<Map<String, bool>?>((
  ref,
) async {
  final service = ref.watch(profileServiceProvider);
  if (service == null || service.client.auth.currentUser == null) return null;
  return service.getNotificationPreferences();
});
