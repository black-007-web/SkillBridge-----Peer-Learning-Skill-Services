import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/supabase_config.dart';
import 'providers/auth_provider.dart';
import 'services/secure_auth_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const config = SupabaseConfig.fromEnvironment();
  if (config.isConfigured) {
    await Supabase.initialize(
      url: config.url.trim(),
      publishableKey: config.publishableKey.trim(),
      authOptions: FlutterAuthClientOptions(
        localStorage: SecureSupabaseSessionStorage(config.url.trim()),
        pkceAsyncStorage: const SecurePkceStorage(),
      ),
    );
  }

  runApp(
    ProviderScope(
      overrides: [
        supabaseClientProvider.overrideWithValue(
          config.isConfigured ? Supabase.instance.client : null,
        ),
      ],
      child: SkillBridgeApp(supabaseConfigured: config.isConfigured),
    ),
  );
}
