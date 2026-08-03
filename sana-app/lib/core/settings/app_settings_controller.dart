import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettingsController extends ChangeNotifier {
  AppSettingsController();

  static final AppSettingsController instance = AppSettingsController();
  static const _darkModeKey = 'sana_dark_mode_v1';
  static const _largeTextKey = 'sana_large_text_v1';

  bool _darkMode = false;
  bool _largeText = false;

  bool get darkMode => _darkMode;
  bool get largeText => _largeText;
  ThemeMode get themeMode => _darkMode ? ThemeMode.dark : ThemeMode.light;
  double get additionalTextScale => _largeText ? 1.18 : 1.0;

  Future<void> load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      _darkMode = preferences.getBool(_darkModeKey) ?? false;
      _largeText = preferences.getBool(_largeTextKey) ?? false;
      notifyListeners();
    } catch (_) {
      // Varsayılan erişilebilir ayarlar kullanılmaya devam eder.
    }
  }

  Future<void> setDarkMode(bool value) async {
    _darkMode = value;
    notifyListeners();
    await _persist(_darkModeKey, value);
  }

  Future<void> setLargeText(bool value) async {
    _largeText = value;
    notifyListeners();
    await _persist(_largeTextKey, value);
  }

  Future<void> _persist(String key, bool value) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(key, value);
    } catch (_) {
      // Ayar bu oturumda etkin kalır.
    }
  }
}
