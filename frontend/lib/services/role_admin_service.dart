import 'package:supabase_flutter/supabase_flutter.dart';

class RoleAdminService {
  RoleAdminService(this.client);
  final SupabaseClient client;

  Future<Map<String, dynamic>> metrics() async => Map<String, dynamic>.from(
    await client.rpc('admin_platform_metrics') as Map,
  );

  Future<List<Map<String, dynamic>>> users({String search = ''}) async {
    final rows = await client.rpc(
      'admin_list_users',
      params: {'p_search': search.trim(), 'p_limit': 50, 'p_offset': 0},
    );
    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> pending(String table) async {
    if (!{
      'student_verification_requests',
      'lecturer_applications',
    }.contains(table)) {
      throw ArgumentError.value(table, 'table');
    }
    final rows = await client
        .from(table)
        .select()
        .eq('status', 'pending')
        .order('created_at');
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<List<Map<String, dynamic>>> submittedCourses() async {
    final rows = await client
        .from('courses')
        .select('id,title,category,level,instructor,owner_id,created_at')
        .eq('status', 'submitted')
        .order('created_at');
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<List<Map<String, dynamic>>> openTickets() async {
    final rows = await client
        .from('support_tickets')
        .select(
          'id,reporter_id,category,subject,description,status,priority,created_at',
        )
        .inFilter('status', ['open', 'in_progress'])
        .order('created_at');
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<void> resolveTicket(String id, String resolution) async {
    await client
        .from('support_tickets')
        .update({'status': 'resolved', 'resolution': resolution.trim()})
        .eq('id', id);
  }

  Future<List<Map<String, dynamic>>> recentAudit() async {
    final rows = await client
        .from('audit_logs')
        .select('actor_id,action,target_type,target_id,metadata,created_at')
        .order('created_at', ascending: false)
        .limit(25);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<List<Map<String, dynamic>>> openReviewReports() async {
    final rows = await client
        .from('course_review_reports')
        .select(
          'id,review_id,reporter_id,reason,created_at,course_reviews(course_id,comment,rating)',
        )
        .eq('status', 'open')
        .order('created_at')
        .limit(100);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<void> resolveReviewReport(
    String id, {
    required bool hideReview,
    required String reason,
  }) async {
    await client.rpc(
      'admin_resolve_course_review_report',
      params: {
        'p_report_id': id,
        'p_hide_review': hideReview,
        'p_reason': reason,
      },
    );
  }

  Future<void> decide(
    String table,
    String id,
    String status, {
    String reason = '',
  }) async {
    if (!{
          'student_verification_requests',
          'lecturer_applications',
        }.contains(table) ||
        !{'approved', 'rejected'}.contains(status)) {
      throw ArgumentError('Invalid review decision.');
    }
    await client
        .from(table)
        .update({'status': status, 'decision_reason': reason.trim()})
        .eq('id', id);
  }

  Future<void> setCourseStatus(String id, String status) async {
    await client.from('courses').update({'status': status}).eq('id', id);
  }

  Future<void> setAccountStatus(
    String userId,
    String status, {
    String reason = '',
  }) async {
    await client.rpc(
      'admin_set_account_status',
      params: {'p_user_id': userId, 'p_status': status, 'p_reason': reason},
    );
  }

  Future<void> assignRole(
    String userId,
    String role,
    bool grant, {
    String reason = '',
  }) async {
    await client.rpc(
      'admin_assign_role',
      params: {
        'p_user_id': userId,
        'p_role': role,
        'p_grant': grant,
        'p_reason': reason,
      },
    );
  }

  Future<int> publishAnnouncement({
    required String title,
    required String body,
    required String audience,
  }) async {
    final authorId = client.auth.currentUser?.id;
    if (authorId == null) throw StateError('Sign in as an administrator.');
    final row = await client
        .from('announcements')
        .insert({
          'title': title.trim(),
          'body': body.trim(),
          'audience': audience,
          'author_id': authorId,
          'status': 'draft',
        })
        .select('id')
        .single();
    final result = await client.rpc(
      'publish_announcement',
      params: {'p_announcement_id': row['id']},
    );
    return (result as num).toInt();
  }
}
