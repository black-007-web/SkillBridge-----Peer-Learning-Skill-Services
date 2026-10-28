class SupabaseConfig {
  const SupabaseConfig({
    required this.url,
    required this.publishableKey,
    this.eduEmailDomain = '',
  });

  const SupabaseConfig.fromEnvironment()
    : url = const String.fromEnvironment('SUPABASE_URL'),
      publishableKey = const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
      eduEmailDomain = const String.fromEnvironment('EDU_EMAIL_DOMAIN');

  final String url;
  final String publishableKey;
  final String eduEmailDomain;

  bool isAllowedEduEmail(String email) {
    final domain = eduEmailDomain.trim().toLowerCase();
    return domain.isNotEmpty &&
        email.trim().toLowerCase().endsWith('@$domain');
  }

  bool get isConfigured {
    final parsedUrl = Uri.tryParse(url.trim());
    final isHttps = parsedUrl?.scheme == 'https';
    final isLocalDevelopmentUrl =
        parsedUrl?.scheme == 'http' &&
        const {'localhost', '127.0.0.1', '::1'}.contains(parsedUrl?.host);
    return parsedUrl != null &&
        (isHttps || isLocalDevelopmentUrl) &&
        parsedUrl.host.isNotEmpty &&
        publishableKey.trim().isNotEmpty;
  }
}
