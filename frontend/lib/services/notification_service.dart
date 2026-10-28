import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/notification_model.dart';

class NotificationService {
  NotificationService(this.client);
  final SupabaseClient client;

  Future<List<AppNotification>> listMine() async {
    final rows = await client
        .from('notifications')
        .select('id,category,title,body,created_at,read_at')
        .order('created_at', ascending: false)
        .limit(100);
    return rows
        .map((row) => AppNotification.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<void> markRead(String id) async {
    await client
        .from('notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id);
  }

  Future<void> markAllRead() async {
    await client
        .from('notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .isFilter('read_at', null);
  }
}
