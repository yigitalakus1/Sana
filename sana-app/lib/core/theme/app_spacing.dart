import 'package:flutter/widgets.dart';

/// Tutarlı boşluk / yarıçap / içerik genişliği sabitleri.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  // Yarıçap — tasarım kararı: eski tekdüze 8 yerine amaca göre ayrışıyor.
  // Kartlar yumuşak (16), kontroller orta (12), çipler tam yuvarlak, alt
  // sayfalar üstten 24.
  /// Kart, panel, uyarı kutusu.
  static const double radiusLg = 16;

  /// Buton, giriş alanı, ikon kutusu — dokunulan her şey.
  static const double radius = 12;

  /// Küçük iç öğeler.
  static const double radiusSm = 8;

  /// Çip ve rozetler (tam yuvarlak).
  static const double radiusPill = 100;

  /// Alt sayfa (bottom sheet) üst köşeleri.
  static const double radiusSheet = 24;

  /// Büyük ekranlarda içeriğin aşırı yayılmaması için.
  static const double maxContentWidth = 960;

  /// Ekran genişliğine göre yatay/dikey sayfa kenar boşluğu.
  static EdgeInsets pagePadding(double width) {
    final h = width < 480 ? 16.0 : 20.0;
    return EdgeInsets.symmetric(horizontal: h, vertical: 16);
  }
}
