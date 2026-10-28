import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../services/announcement_service.dart';
import '../services/profile_service.dart';
import '../services/storage_service.dart';
import '../services/notification_service.dart';
import '../services/resource_service.dart';

final supabaseClientProvider = Provider<SupabaseClient?>((ref) => null);

final authServiceProvider = Provider<AuthService?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : AuthService(client);
});

final profileServiceProvider = Provider<ProfileService?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : ProfileService(client);
});

final announcementServiceProvider = Provider<AnnouncementService?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : AnnouncementService(client);
});

final storageServiceProvider = Provider<StorageService?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : StorageService(client);
});

final notificationServiceProvider = Provider<NotificationService?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : NotificationService(client);
});

final resourceServiceProvider = Provider<ResourceService?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : ResourceService(client);
});

final authStateProvider = StreamProvider<AuthState>((ref) {
  final auth = ref.watch(authServiceProvider);
  return auth?.authChanges ?? const Stream<AuthState>.empty();
});
