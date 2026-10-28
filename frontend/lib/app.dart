import 'package:flutter/material.dart';

import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';

class SkillBridgeApp extends StatefulWidget {
  const SkillBridgeApp({super.key, required this.supabaseConfigured});

  final bool supabaseConfigured;

  @override
  State<SkillBridgeApp> createState() => _SkillBridgeAppState();
}

class _SkillBridgeAppState extends State<SkillBridgeApp> {
  late final AppRouter _appRouter = AppRouter(
    supabaseConfigured: widget.supabaseConfigured,
  );

  @override
  void dispose() {
    _appRouter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'SkillBridge',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.dark,
    darkTheme: AppTheme.dark,
    themeMode: ThemeMode.dark,
    routerConfig: _appRouter.router,
    builder: (context, child) =>
        AppBackdrop(child: child ?? const SizedBox.shrink()),
  );
}
