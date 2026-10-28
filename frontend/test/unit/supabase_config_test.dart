import 'package:flutter_test/flutter_test.dart';
import 'package:skillbridge_mobile/core/supabase_config.dart';

void main() {
  group('SupabaseConfig', () {
    test('requires an HTTP URL with a host and a non-empty key', () {
      expect(
        const SupabaseConfig(
          url: 'https://example.supabase.co',
          publishableKey: 'public-key',
        ).isConfigured,
        isTrue,
      );
      expect(
        const SupabaseConfig(url: '', publishableKey: '').isConfigured,
        isFalse,
      );
      expect(
        const SupabaseConfig(
          url: 'file:///tmp/project',
          publishableKey: 'public-key',
        ).isConfigured,
        isFalse,
      );
      expect(
        const SupabaseConfig(
          url: 'http://api.example.com',
          publishableKey: 'public-key',
        ).isConfigured,
        isFalse,
      );
      expect(
        const SupabaseConfig(
          url: 'http://localhost:54321',
          publishableKey: 'public-key',
        ).isConfigured,
        isTrue,
      );
    });

    test('matches the institution domain without a leading at sign', () {
      const config = SupabaseConfig(
        url: 'https://example.supabase.co',
        publishableKey: 'public-key',
        eduEmailDomain: 'eastdelta.edu.bd',
      );

      expect(config.isAllowedEduEmail('student@eastdelta.edu.bd'), isTrue);
      expect(config.isAllowedEduEmail('student@other.edu.bd'), isFalse);
      expect(
        const SupabaseConfig(
          url: 'https://example.supabase.co',
          publishableKey: 'public-key',
          eduEmailDomain: '@eastdelta.edu.bd',
        ).isAllowedEduEmail('student@eastdelta.edu.bd'),
        isFalse,
      );
    });
  });
}
