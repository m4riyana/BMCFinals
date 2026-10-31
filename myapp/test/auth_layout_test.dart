import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho_stationery/main.dart';

void main() {
  testWidgets('Signup fits wide windows at different heights', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(1877, 862);
    await tester.pumpWidget(
      MaterialApp(theme: ibashoTheme(), home: const AuthPage()),
    );
    await tester.ensureVisible(find.text('New to the studio? Create an account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New to the studio? Create an account'));
    await tester.pumpAndSettle();
    expect(find.text('CREATE ACCOUNT'), findsOneWidget);
    expect(tester.takeException(), isNull);
    for (final size in [const Size(390, 844), const Size(1877, 862)]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    tester.view.physicalSize = const Size(1000, 600);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
