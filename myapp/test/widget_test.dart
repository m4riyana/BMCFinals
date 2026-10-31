import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho_stationery/main.dart';

void main() {
  testWidgets('Authentication adapts and opens recovery', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final entry in {
      'Lato': 'Lato-Regular.ttf',
      'Libre Baskerville': 'LibreBaskerville.ttf',
      'Caveat': 'Caveat.ttf'
    }.entries) {
      final loader = FontLoader(entry.key)
        ..addFont(rootBundle.load('assets/fonts/${entry.value}'));
      await loader.load();
    }
    final icons = FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    await tester
        .pumpWidget(MaterialApp(theme: ibashoTheme(), home: const AuthPage()));
    expect(find.text('STATIONERY'), findsOneWidget);
    await expectLater(
        find.byType(AuthPage), matchesGoldenFile('goldens/login-desktop.png'));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Forgot Password?'));
    await tester.pumpAndSettle();
    expect(find.text('SEND RESET LINK'), findsOneWidget);
    expect(find.text('Password'), findsNothing);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}


