import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/theme/app_theme.dart';
import 'core/settings/app_settings_controller.dart';
import 'features/medication/services/medication_reminder_service.dart';
import 'features/ml_dictionary/screens/main_shell_screen.dart';
import 'features/ml_dictionary/screens/safety_consent_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SanaApp());

  // Cihaz yeniden başladığında zamanlanmış bildirimler silinir; kayıtlı
  // hatırlatıcılar açılışta sessizce yeniden kurulur. Arayüzü bekletmemesi
  // için await edilmez ve hata uygulamayı etkilemez.
  MedicationReminderService().rescheduleAll().catchError((_) {});
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
        locale: const Locale('tr'),
        supportedLocales: const [Locale('tr'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) {
          final media = MediaQuery.of(context);
          final systemScale = media.textScaler.scale(16) / 16;
          return MediaQuery(
            data: media.copyWith(
              textScaler: TextScaler.linear(
                systemScale * _settings.additionalTextScale,
              ),
              // Saat her yerde 24 saatlik gösterilir. İlaç saatinde 08:00 ile
              // 20:00'ın karışması gerçek bir risk; AM/PM bilinçli olarak
              // kapatıldı (sistem 12 saatlik olsa bile).
              alwaysUse24HourFormat: true,
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
