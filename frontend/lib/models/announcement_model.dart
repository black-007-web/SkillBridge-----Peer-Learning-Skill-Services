class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.audience,
    required this.publishedAt,
    this.expiresAt,
  });

  final String id;
  final String title;
  final String body;
  final String audience;
  final DateTime publishedAt;
  final DateTime? expiresAt;

  factory Announcement.fromJson(Map<String, dynamic> json) => Announcement(
    id: json['id'] as String,
    title: json['title'] as String,
    body: json['body'] as String,
    audience: json['audience'] as String,
    publishedAt: DateTime.parse(json['published_at'] as String),
    expiresAt: json['expires_at'] == null
        ? null
        : DateTime.parse(json['expires_at'] as String),
  );
}
