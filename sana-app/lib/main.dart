import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'core/settings/app_settings_controller.dart';
import 'features/ml_dictionary/screens/main_shell_screen.dart';
import 'features/ml_dictionary/screens/safety_consent_screen.dart';

void main() {
  runApp(const SanaApp());
}

class SanaApp extends StatefulWidget {
  const SanaApp({super.key});

  @override
  State<SanaApp> createState() => _SanaAppState();
}

class _SanaAppState extends State<SanaApp> {
  bool _safetyAccepted = false;
  final AppSettingsController _settings = AppSettingsController.instance;

  @override
  void initState() {
    super.initState();
    _settings.load();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _settings,
      builder: (context, _) => MaterialApp(
        title: 'Sana',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: _settings.themeMode,
        builder: (context, child) {
          final media = MediaQuery.of(context);
          final systemScale = media.textScaler.scale(16) / 16;
          return MediaQuery(
            data: media.copyWith(
              textScaler: TextScaler.linear(
                systemScale * _settings.additionalTextScale,
              ),
            ),
            child: child!,
          );
        },
        home: _safetyAccepted
            ? const MainShellScreen()
            : SafetyConsentScreen(
                onAccepted: () => setState(() => _safetyAccepted = true),
              ),
      ),
    );
  }
}
