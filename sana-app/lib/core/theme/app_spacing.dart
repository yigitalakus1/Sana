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

  static const double radius = 8;
  static const double radiusLg = 8;
  static const double radiusSm = 6;

  /// Büyük ekranlarda içeriğin aşırı yayılmaması için.
  static const double maxContentWidth = 960;

  /// Ekran genişliğine göre yatay/dikey sayfa kenar boşluğu.
  static EdgeInsets pagePadding(double width) {
    final h = width < 480 ? 16.0 : 20.0;
    return EdgeInsets.symmetric(horizontal: h, vertical: 16);
  }
}
