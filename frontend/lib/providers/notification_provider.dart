import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/notification_model.dart';
import 'auth_provider.dart';

final notificationsProvider = FutureProvider<List<AppNotification>>((
  ref,
) async {
  final service = ref.watch(notificationServiceProvider);
  if (service == null) return const [];
  return service.listMine();
});
