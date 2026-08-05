import 'package:flutter/material.dart';

import 'app_spacing.dart';

class AppColors {
  AppColors._();

  static const Color background = Color(0xFFF6F7F9);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color primary = Color(0xFF0B8F83);
  static const Color primarySoft = Color(0xFFE7F4F2);
  static const Color primaryDeep = Color(0xFF08665F);
  static const Color accentBlue = Color(0xFF2F6FED);
  static const Color accentBlueSoft = Color(0xFFEAF0FF);
  static const Color accentBlueDeep = Color(0xFF1D4ED8);
  static const Color accentLavender = Color(0xFFF2F4F7);
  static const Color accentLavenderDeep = Color(0xFF475467);
  static const Color warningSoft = Color(0xFFFFF4E5);
  static const Color warningText = Color(0xFF8A4B08);
  static const Color textPrimary = Color(0xFF182230);
  static const Color textSecondary = Color(0xFF667085);

  /// Gövde metni — birincil metinden bir tık yumuşak, uzun paragraflar için.
  static const Color textBody = Color(0xFF344054);

  /// Sessiz ikonlar (chevron, dekoratif).
  static const Color iconMuted = Color(0xFF98A2B3);

  static const Color border = Color(0xFFD9DEE7);

  /// Kart içi ince ayraç — kenarlıktan daha sessiz.
  static const Color borderSubtle = Color(0xFFEAECF0);
  static const Color surfaceMuted = Color(0xFFF2F4F7);
}

/// Tahlil sonucunun referans aralığına göre durumu.
///
/// Kırmızı bilinçli olarak yoktur: yüksek kehribar, düşük mavidir. Sağlık
/// kaygısını büyütmeden bilgi vermek için.
enum SanaStatus { inRange, above, below, unknown }

/// Tek bir durumun üç rengi: zemin, metin/ikon ve vurgu.
@immutable
class SanaStatusStyle {
  const SanaStatusStyle({
    required this.background,
    required this.foreground,
    required this.accent,
  });

  final Color background;
  final Color foreground;
  final Color accent;

  static SanaStatusStyle lerp(SanaStatusStyle a, SanaStatusStyle b, double t) =>
      SanaStatusStyle(
        background: Color.lerp(a.background, b.background, t)!,
        foreground: Color.lerp(a.foreground, b.foreground, t)!,
        accent: Color.lerp(a.accent, b.accent, t)!,
      );
}

/// Durum renklerini temaya bağlar; açık/koyu geçişinde widget'lar
/// koşul yazmadan doğru rengi alır.
@immutable
class SanaStatusColors extends ThemeExtension<SanaStatusColors> {
  const SanaStatusColors({
    required this.inRange,
    required this.above,
    required this.below,
    required this.unknown,
  });

  final SanaStatusStyle inRange;
  final SanaStatusStyle above;
  final SanaStatusStyle below;
  final SanaStatusStyle unknown;

  SanaStatusStyle of(SanaStatus status) => switch (status) {
    SanaStatus.inRange => inRange,
    SanaStatus.above => above,
    SanaStatus.below => below,
    SanaStatus.unknown => unknown,
  };

  static const light = SanaStatusColors(
    inRange: SanaStatusStyle(
      background: Color(0xFFECFDF3),
      foreground: Color(0xFF027A48),
      accent: Color(0xFF12B76A),
    ),
    above: SanaStatusStyle(
      background: Color(0xFFFFF4E5),
      foreground: Color(0xFF8A4B08),
      accent: Color(0xFFF79009),
    ),
    below: SanaStatusStyle(
      background: Color(0xFFEAF0FF),
      foreground: Color(0xFF1849A9),
      accent: Color(0xFF2E90FA),
    ),
    unknown: SanaStatusStyle(
      background: Color(0xFFF2F4F7),
      foreground: Color(0xFF667085),
      accent: Color(0xFF98A2B3),
    ),
  );

  /// Koyu temada zemin %8 opaklığa iner, metin açılır.
  static const dark = SanaStatusColors(
    inRange: SanaStatusStyle(
      background: Color(0x1432D583),
      foreground: Color(0xFF6CE9A6),
      accent: Color(0xFF32D583),
    ),
    above: SanaStatusStyle(
      background: Color(0x14FDB022),
      foreground: Color(0xFFFEC84B),
      accent: Color(0xFFFDB022),
    ),
    below: SanaStatusStyle(
      background: Color(0x1453B1FD),
      foreground: Color(0xFF84CAFF),
      accent: Color(0xFF53B1FD),
    ),
    // Koyu temada nötr çipin metni açık kalmalı; #98A2B3 kendi zemini üstünde
    // sönük görünüyordu.
    unknown: SanaStatusStyle(
      background: Color(0x1FCDD5DF),
      foreground: Color(0xFFCDD5DF),
      accent: Color(0xFF98A2B3),
    ),
  );

  @override
  SanaStatusColors copyWith({
    SanaStatusStyle? inRange,
    SanaStatusStyle? above,
    SanaStatusStyle? below,
    SanaStatusStyle? unknown,
  }) => SanaStatusColors(
    inRange: inRange ?? this.inRange,
    above: above ?? this.above,
    below: below ?? this.below,
    unknown: unknown ?? this.unknown,
  );

  @override
  SanaStatusColors lerp(ThemeExtension<SanaStatusColors>? other, double t) {
    if (other is! SanaStatusColors) return this;
    return SanaStatusColors(
      inRange: SanaStatusStyle.lerp(inRange, other.inRange, t),
      above: SanaStatusStyle.lerp(above, other.above, t),
      below: SanaStatusStyle.lerp(below, other.below, t),
      unknown: SanaStatusStyle.lerp(unknown, other.unknown, t),
    );
  }
}

/// `context.statusColors` ve `context.statusStyle(...)` kısayolları.
extension SanaStatusColorsX on BuildContext {
  SanaStatusColors get statusColors =>
      Theme.of(this).extension<SanaStatusColors>() ?? SanaStatusColors.light;

  SanaStatusStyle statusStyle(SanaStatus status) => statusColors.of(status);
}

class AppTheme {
  AppTheme._();

  /// Uygulamayla paketlenen marka yazı tipi (çalışma anında indirilmez).
  static const String fontFamily = 'HankenGrotesk';

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final background = dark ? const Color(0xFF101418) : AppColors.background;
    final surface = dark ? const Color(0xFF181D23) : AppColors.surface;
    final surfaceMuted = dark
        ? const Color(0xFF242B33)
        : AppColors.surfaceMuted;
    final border = dark ? const Color(0xFF262D35) : AppColors.border;
    final borderSubtle = dark
        ? const Color(0xFF222932)
        : AppColors.borderSubtle;
    final textPrimary = dark ? const Color(0xFFF1F5F7) : AppColors.textPrimary;
    final textSecondary = dark
        ? const Color(0xFF98A2B3)
        : AppColors.textSecondary;
    final textBody = dark ? const Color(0xFFD6DDE5) : AppColors.textBody;
    final primary = dark ? const Color(0xFF58C9BC) : AppColors.primary;
    final primaryContainer = dark
        ? const Color(0xFF153E3A)
        : AppColors.primarySoft;
    final onPrimaryContainer = dark
        ? const Color(0xFFB8F2EB)
        : AppColors.primaryDeep;

    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: brightness,
        ).copyWith(
          primary: primary,
          onPrimary: dark ? const Color(0xFF062E2A) : Colors.white,
          primaryContainer: primaryContainer,
          onPrimaryContainer: onPrimaryContainer,
          secondary: dark ? const Color(0xFF8EAEFF) : AppColors.accentBlue,
          secondaryContainer: primaryContainer,
          onSecondaryContainer: onPrimaryContainer,
          tertiaryContainer: dark
              ? const Color(0xFF4D3519)
              : AppColors.warningSoft,
          onTertiaryContainer: dark
              ? const Color(0xFFFFD9A1)
              : AppColors.warningText,
          surface: surface,
          onSurface: textPrimary,
          onSurfaceVariant: textSecondary,
          surfaceContainerHighest: surfaceMuted,
          outline: border,
          outlineVariant: borderSubtle,
        );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontFamily,
    );

    // Yarıçap: kart yumuşak, kontrol orta, çip tam yuvarlak.
    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
    );
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSpacing.radius),
    );

    return base.copyWith(
      scaffoldBackgroundColor: background,
      extensions: [dark ? SanaStatusColors.dark : SanaStatusColors.light],
      textTheme: _textTheme(base.textTheme, textPrimary, textBody, textSecondary),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        foregroundColor: textPrimary,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.012 * 20,
          color: textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: cardShape.copyWith(side: BorderSide(color: borderSubtle)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSpacing.radiusSheet),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: cardShape,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        // Tasarım: giriş yüksekliği 52.
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 16,
        ),
        hintStyle: TextStyle(color: textSecondary, fontSize: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // Birincil eylem koyu tealdir; teal zeminde beyaz metin kontrastı
          // AA'yı geçer.
          backgroundColor: dark ? primary : AppColors.primaryDeep,
          foregroundColor: dark ? const Color(0xFF062E2A) : Colors.white,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          shape: controlShape,
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          foregroundColor: textBody,
          backgroundColor: surface,
          side: BorderSide(color: border),
          shape: controlShape,
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: onPrimaryContainer,
          minimumSize: const Size(0, 48),
          shape: controlShape,
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: surface,
        side: BorderSide(color: border),
        shape: const StadiumBorder(),
        labelStyle: TextStyle(
          fontFamily: fontFamily,
          color: textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
      dividerTheme: DividerThemeData(color: borderSubtle, space: 1, thickness: 1),
      listTileTheme: ListTileThemeData(
        shape: cardShape,
        iconColor: AppColors.iconMuted,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 15.5,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        subtitleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 13.5,
          color: textSecondary,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: primaryContainer,
        indicatorShape: const StadiumBorder(),
        elevation: 0,
        height: 66,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? onPrimaryContainer
                : textSecondary,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: fontFamily,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? onPrimaryContainer : textSecondary,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        indicatorColor: primaryContainer,
        indicatorShape: const StadiumBorder(),
        selectedIconTheme: IconThemeData(color: onPrimaryContainer),
        unselectedIconTheme: IconThemeData(color: textSecondary),
        selectedLabelTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: textSecondary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// Tasarımdaki tipografi skalası.
  ///
  /// Display 28/600 · Başlık 22/600 · Gövde 16/400 (satır 1.55) ·
  /// Veri 26/600 tabular · Etiket 13/600 büyük harf.
  static TextTheme _textTheme(
    TextTheme base,
    Color primary,
    Color body,
    Color secondary,
  ) {
    return base
        .copyWith(
          displaySmall: TextStyle(
            fontSize: 28,
            height: 1.2,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.018 * 28,
            color: primary,
          ),
          headlineSmall: TextStyle(
            fontSize: 22,
            height: 1.25,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.012 * 22,
            color: primary,
          ),
          titleLarge: TextStyle(
            fontSize: 18,
            height: 1.3,
            fontWeight: FontWeight.w600,
            color: primary,
          ),
          titleMedium: TextStyle(
            fontSize: 15.5,
            height: 1.3,
            fontWeight: FontWeight.w600,
            color: primary,
          ),
          bodyLarge: TextStyle(fontSize: 16, height: 1.55, color: body),
          bodyMedium: TextStyle(fontSize: 14.5, height: 1.5, color: body),
          // İÇERİK metnidir (kaynak satırı, doktor soruları): en soluk tonu
          // kullanmaz. Yalnız etiketler `labelSmall`/`onSurfaceVariant` ile
          // sessizleşir. Aksi hâlde koyu temada okunmuyordu.
          bodySmall: TextStyle(fontSize: 13.5, height: 1.45, color: body),
          labelLarge: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: primary,
          ),
          labelSmall: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.09 * 13,
            color: secondary,
          ),
        )
        .apply(fontFamily: fontFamily);
  }
}
