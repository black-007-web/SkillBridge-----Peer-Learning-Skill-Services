import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skillbridge_mobile/app.dart';

void main() {
  testWidgets('preview shows an honest empty catalog without database data', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: SkillBridgeApp(supabaseConfigured: false)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Your next chapter.'), findsOneWidget);
    await tester.tap(find.text('Explore'));
    await tester.pumpAndSettle();

    expect(find.text('Category'), findsOneWidget);
    expect(find.text('Difficulty'), findsOneWidget);
    expect(find.text('Minimum rating'), findsOneWidget);
    expect(find.text('No published courses yet.'), findsOneWidget);
  });

  testWidgets('the app uses the dark SkillBridge theme', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: SkillBridgeApp(supabaseConfigured: false)),
    );
    await tester.pumpAndSettle();

    expect(
      Theme.of(tester.element(find.byType(Scaffold))).brightness,
      Brightness.dark,
    );
  });
}
