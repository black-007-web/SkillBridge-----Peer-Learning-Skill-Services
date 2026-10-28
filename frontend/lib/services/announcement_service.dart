import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/announcement_model.dart';

class AnnouncementService {
  AnnouncementService(this.client);

  final SupabaseClient client;

  Future<List<Announcement>> published() async {
    final rows = await client
        .from('announcements')
        .select('id,title,body,audience,published_at,expires_at')
        .eq('status', 'published')
        .order('published_at', ascending: false);
    return rows
        .map((row) => Announcement.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }
}
