import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_profile.dart';

class ProfileService {
  ProfileService(this.client);

  final SupabaseClient client;

  Future<UserProfile> getCurrentProfile() async {
    final user = client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to view your profile.');
    }
    Map<String, dynamic>? row;
    try {
      row = await client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 12));
    } on PostgrestException catch (error) {
      // PGRST205 means the API cannot see public.profiles. This usually means
      // the project's migrations have not been applied or its schema cache is
      // stale. Keep the dashboard usable from Auth metadata in the meantime.
      if (!_profileTableUnavailable(error)) rethrow;
      return _profileFromAuthMetadata(user);
    } on TimeoutException {
      // Avoid leaving the profile tab in an endless loading state on a stalled
      // request. Registration metadata is available locally in the session.
      return _profileFromAuthMetadata(user);
    }
    // Auth metadata is written during registration. Use it as an immediate
    // display fallback if the profile trigger has not created its row yet.
    // The dashboard remains usable and can still be edited/synced later.
    if (row == null) {
      return _profileFromAuthMetadata(user);
    }
    return UserProfile.fromJson({
      ...(user.userMetadata ?? const <String, dynamic>{}),
      ...Map<String, dynamic>.from(row),
    });
  }

  UserProfile _profileFromAuthMetadata(User user) {
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    return UserProfile.fromJson({
      'id': user.id,
      'full_name': metadata['full_name'] ?? metadata['name'] ?? '',
      'phone_number': metadata['phone_number'],
      'date_of_birth': metadata['date_of_birth'],
      'gender': metadata['gender'],
      'nationality': metadata['nationality'],
      'address': metadata['address'],
      'bio': metadata['bio'],
      'social_links': metadata['social_links'],
      'position': metadata['position'],
      'skills': metadata['skills'],
      'cover_image_url': metadata['cover_image_url'],
      'created_at': user.createdAt,
    });
  }

  bool _profileTableUnavailable(PostgrestException error) =>
      error.code == 'PGRST205' ||
      error.code == '42P01' ||
      error.code == 'PGRST204' ||
      error.message.toLowerCase().contains('public.profiles');

  Future<bool> updateProfile({
    required String fullName,
    required String phoneNumber,
    DateTime? dateOfBirth,
    String? gender,
    String? nationality,
    String? address,
    required String bio,
    required Map<String, String> socialLinks,
    required String position,
    required List<String> skills,
    String? coverImagePath,
  }) async {
    final user = client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to update your profile.');
    }
    List<Map<String, dynamic>> updatedRows;
    var metadataFallback = false;
    try {
      updatedRows = await client
          .from('profiles')
          .update({
            'full_name': fullName.trim(),
            'phone_number': phoneNumber.trim().isEmpty
                ? null
                : phoneNumber.trim(),
            'date_of_birth': dateOfBirth?.toIso8601String().split('T').first,
            'gender': gender,
            'nationality': nationality?.trim(),
            'address': address?.trim(),
            'bio': bio.trim(),
            'social_links': socialLinks,
            'position': position.trim(),
            'skills': skills,
            'cover_image_url': coverImagePath,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', user.id)
          .select('id');
    } on PostgrestException catch (error) {
      if (!_profileColumnMissing(error)) rethrow;
      metadataFallback = true;
      updatedRows = await client
          .from('profiles')
          .update({
            'full_name': fullName.trim(),
            'date_of_birth': dateOfBirth?.toIso8601String().split('T').first,
            'gender': gender,
            'nationality': nationality?.trim(),
            'address': address?.trim(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', user.id)
          .select('id');
      await client.auth.updateUser(
        UserAttributes(
          data: _profileMetadata(
            fullName: fullName,
            phoneNumber: phoneNumber,
            dateOfBirth: dateOfBirth,
            gender: gender,
            nationality: nationality,
            address: address,
            bio: bio,
            socialLinks: socialLinks,
            position: position,
            skills: skills,
            coverImagePath: coverImagePath,
          ),
        ),
      );
    }
    if (updatedRows.isEmpty) {
      await _insertProfileFromCurrentUser(
        user,
        fullName: fullName.trim(),
        phoneNumber: phoneNumber.trim(),
        dateOfBirth: dateOfBirth,
        gender: gender,
        nationality: nationality?.trim(),
        address: address?.trim(),
        bio: bio.trim(),
        socialLinks: socialLinks,
        position: position.trim(),
        skills: skills,
        coverImagePath: coverImagePath,
        includeExtendedFields: !metadataFallback,
      );
    }
    // Keep Auth metadata in sync for fallback display, but the profiles row is
    // the source of truth. A metadata refresh failure must not undo a saved row.
    try {
      await client.auth.updateUser(
        UserAttributes(
          data: {
            'full_name': fullName.trim(),
            if (!metadataFallback)
              'phone_number': phoneNumber.trim().isEmpty
                  ? null
                  : phoneNumber.trim(),
            if (!metadataFallback) 'bio': bio.trim(),
            if (!metadataFallback) 'social_links': socialLinks,
            if (!metadataFallback) 'position': position.trim(),
            if (!metadataFallback) 'skills': skills,
            'cover_image_url': coverImagePath,
          },
        ),
      );
    } on AuthException {
      // The profile update already succeeded in the database.
    }
    return metadataFallback;
  }

  bool _profileColumnMissing(PostgrestException error) =>
      error.code == 'PGRST204' ||
      error.message.toLowerCase().contains('schema cache');

  Map<String, dynamic> _profileMetadata({
    required String fullName,
    required String phoneNumber,
    required DateTime? dateOfBirth,
    required String? gender,
    required String? nationality,
    required String? address,
    required String bio,
    required Map<String, String> socialLinks,
    required String position,
    required List<String> skills,
    String? coverImagePath,
  }) => {
    'full_name': fullName.trim(),
    'phone_number': phoneNumber.trim().isEmpty ? null : phoneNumber.trim(),
    'date_of_birth': dateOfBirth?.toIso8601String().split('T').first,
    'gender': gender,
    'nationality': nationality?.trim(),
    'address': address?.trim(),
    'bio': bio.trim(),
    'social_links': socialLinks,
    'position': position.trim(),
    'skills': skills,
    'cover_image_url': coverImagePath,
  };

  Future<void> updateAvatarPath(String? path) async {
    final user = client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to update your profile.');
    }
    final updatedRows = await client
        .from('profiles')
        .update({
          'avatar_url': path,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', user.id)
        .select('id');
    if (updatedRows.isEmpty) {
      await _insertProfileFromCurrentUser(user, avatarPath: path);
    }
  }

  Future<void> _insertProfileFromCurrentUser(
    User user, {
    String? fullName,
    String? phoneNumber,
    DateTime? dateOfBirth,
    String? gender,
    String? nationality,
    String? address,
    String? avatarPath,
    String? bio,
    Map<String, String>? socialLinks,
    String? position,
    List<String>? skills,
    String? coverImagePath,
    bool includeExtendedFields = true,
  }) async {
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    final insertedRows = await client
        .from('profiles')
        .insert({
          'id': user.id,
          'full_name': fullName ?? metadata['full_name'] ?? metadata['name'] ?? '',
          'date_of_birth':
              dateOfBirth?.toIso8601String().split('T').first ??
              metadata['date_of_birth'],
          'phone_number': phoneNumber == null
              ? metadata['phone_number']
              : phoneNumber.isEmpty
              ? null
              : phoneNumber,
          'gender': gender ?? metadata['gender'],
          'nationality': nationality ?? metadata['nationality'] ?? '',
          'address': address ?? metadata['address'] ?? '',
          'terms_accepted_at': metadata['terms_accepted_at'],
          'avatar_url': avatarPath,
          if (includeExtendedFields) ...{
            'bio': bio ?? metadata['bio'] ?? '',
            'social_links': socialLinks ?? metadata['social_links'] ?? {},
            'position': position ?? metadata['position'] ?? '',
            'skills': skills ?? metadata['skills'] ?? const <String>[],
            'cover_image_url':
                coverImagePath ?? metadata['cover_image_url'],
          },
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .select('id');
    if (insertedRows.isEmpty) {
      throw StateError('Supabase did not create the missing profile row.');
    }
  }

  Future<List<String>> getRoles() async {
    final user = client.auth.currentUser;
    if (user == null) return const [];
    final rows = await client
        .from('user_roles')
        .select('role')
        .eq('user_id', user.id);
    return rows.map((row) => row['role'] as String).toList(growable: false);
  }

  Future<List<UserProfile>> getPublicLecturers() async {
    final rows = await client.rpc('public_verified_lecturers') as List;
    return rows
        .map(
          (row) => UserProfile.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false);
  }

  Future<Map<String, bool>> getNotificationPreferences() async {
    final user = client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to manage notifications.');
    }
    final row = await client
        .from('notification_preferences')
        .select('email_notifications,in_app_notifications')
        .eq('user_id', user.id)
        .maybeSingle();
    return {
      'email_notifications': row?['email_notifications'] as bool? ?? true,
      'in_app_notifications': row?['in_app_notifications'] as bool? ?? true,
    };
  }

  Future<void> updateNotificationPreferences({
    required bool emailNotifications,
    required bool inAppNotifications,
  }) async {
    final user = client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to manage notifications.');
    }
    await client.from('notification_preferences').upsert({
      'user_id': user.id,
      'email_notifications': emailNotifications,
      'in_app_notifications': inAppNotifications,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
