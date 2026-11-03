import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skillbridge_mobile/app.dart';
import 'package:skillbridge_mobile/features/auth/screens/register_screen.dart';

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

  testWidgets('registration dropdowns fit long department and program labels', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(480, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: RegisterScreen())),
    );
    await tester.pumpAndSettle();

    final departmentField = find.byType(DropdownButtonFormField<String>).at(0);
    await tester.ensureVisible(departmentField);
    await tester.tap(departmentField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Computer Science & Engineering').last);
    await tester.pumpAndSettle();

    final programField = find.byType(DropdownButtonFormField<String>).at(1);
    await tester.ensureVisible(programField);
    await tester.tap(programField);
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .text(
            'BACHELOR OF SCIENCE IN COMPUTER SCIENCE & ENGINEERING (B.SC. IN CSE)',
          )
          .last,
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
