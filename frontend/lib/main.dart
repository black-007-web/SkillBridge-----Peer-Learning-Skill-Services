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

  Object? startupError;

  try {
    if (config.isConfigured) {
      await Supabase.initialize(
        url: config.url.trim(),
        publishableKey: config.publishableKey.trim(),
        authOptions: FlutterAuthClientOptions(
          localStorage: SecureSupabaseSessionStorage(
            config.url.trim(),
          ),
          pkceAsyncStorage: const SecurePkceStorage(),
        ),
      );
    }
  } catch (error, stackTrace) {
    startupError = error;
    debugPrint('SUPABASE STARTUP ERROR: $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  runApp(
    ProviderScope(
      overrides: [
        supabaseClientProvider.overrideWithValue(
          startupError == null && config.isConfigured
              ? Supabase.instance.client
              : null,
        ),
      ],
      child: startupError == null
          ? SkillBridgeApp(
              supabaseConfigured: config.isConfigured,
            )
          : StartupErrorApp(error: startupError),
    ),
  );
}

class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({
    super.key,
    required this.error,
  });

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SelectableText(
                'SkillBridge could not initialize Supabase.\n\n'
                '$error',
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
