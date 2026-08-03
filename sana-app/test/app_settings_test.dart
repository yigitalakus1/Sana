import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sana_app/core/settings/app_settings_controller.dart';
import 'package:sana_app/core/theme/app_theme.dart';
import 'package:sana_app/features/ml_dictionary/screens/main_shell_screen.dart';
import 'package:sana_app/features/ml_dictionary/screens/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('appearance settings persist dark mode and large text', () async {
    final settings = AppSettingsController();
    await settings.load();

    await settings.setDarkMode(true);
    await settings.setLargeText(true);

    expect(settings.themeMode, ThemeMode.dark);
    expect(settings.additionalTextScale, greaterThan(1));

    final restored = AppSettingsController();
    await restored.load();
    expect(restored.darkMode, isTrue);
    expect(restored.largeText, isTrue);
  });

  testWidgets('settings screen toggles appearance controls', (tester) async {
    final settings = AppSettingsController();
    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(controller: settings)),
    );

    expect(find.text('Koyu tema'), findsOneWidget);
    expect(find.text('Büyük yazı'), findsOneWidget);

    final switches = find.byType(Switch);
    expect(switches, findsNWidgets(2));
    await tester.tap(switches.first);
    await tester.pump();

    expect(settings.darkMode, isTrue);
  });

  testWidgets('wide navigation exposes settings in dark theme', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        home: const MainShellScreen(),
      ),
    );
    await tester.pump();

    expect(
      Theme.of(tester.element(find.byType(MainShellScreen))).brightness,
      Brightness.dark,
    );
    expect(find.text('Ayarlar'), findsOneWidget);
  });
}
