class UserProfile {
  const UserProfile({
    required this.id,
    required this.fullName,
    required this.createdAt,
    this.dateOfBirth,
    this.avatarPath,
    this.coverImagePath,
    this.address,
    this.nationality,
    this.gender,
    this.phoneNumber,
    this.bio = '',
    this.socialLinks = const {},
    this.position = '',
    this.skills = const [],
  });

  final String id;
  final String fullName;
  final DateTime createdAt;
  final DateTime? dateOfBirth;
  final String? avatarPath;
  final String? coverImagePath;
  final String? address;
  final String? nationality;
  final String? gender;
  final String? phoneNumber;
  final String bio;
  final Map<String, String> socialLinks;
  final String position;
  final List<String> skills;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final links = json['social_links'];
    return UserProfile(
      id: json['id'] as String,
      fullName: json['full_name'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      dateOfBirth: DateTime.tryParse(json['date_of_birth'] as String? ?? ''),
      avatarPath: json['avatar_url'] as String?,
      coverImagePath: json['cover_image_url'] as String?,
      address: json['address'] as String?,
      nationality: json['nationality'] as String?,
      gender: json['gender'] as String?,
      phoneNumber: json['phone_number'] as String?,
      bio: json['bio'] as String? ?? '',
      socialLinks: links is Map
          ? {
              for (final entry in links.entries)
                if (entry.key is String && entry.value is String)
                  entry.key as String: entry.value as String,
            }
          : const {},
      position: json['position'] as String? ?? '',
      skills: (json['skills'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
    );
  }
}
