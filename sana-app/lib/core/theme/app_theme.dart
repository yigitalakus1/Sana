import 'package:flutter/material.dart';

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
  static const Color border = Color(0xFFD9DEE7);
  static const Color surfaceMuted = Color(0xFFF2F4F7);
}

class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final background = dark ? const Color(0xFF101418) : AppColors.background;
    final surface = dark ? const Color(0xFF181D23) : AppColors.surface;
    final surfaceMuted = dark
        ? const Color(0xFF242B33)
        : AppColors.surfaceMuted;
    final border = dark ? const Color(0xFF39424D) : AppColors.border;
    final textPrimary = dark ? const Color(0xFFF1F5F7) : AppColors.textPrimary;
    final textSecondary = dark
        ? const Color(0xFFB6C0CA)
        : AppColors.textSecondary;
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
          outlineVariant: border,
        );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final rounded = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    );

    return base.copyWith(
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        foregroundColor: textPrimary,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: rounded.copyWith(side: BorderSide(color: border)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        hintStyle: TextStyle(color: textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: primary, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: rounded,
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          foregroundColor: onPrimaryContainer,
          side: BorderSide(color: border),
          shape: rounded,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: onPrimaryContainer),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: surface,
        side: BorderSide(color: border),
        shape: rounded,
        labelStyle: TextStyle(color: textPrimary, fontWeight: FontWeight.w500),
      ),
      dividerTheme: DividerThemeData(color: border, space: 1, thickness: 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: primaryContainer,
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
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? onPrimaryContainer : textSecondary,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        indicatorColor: primaryContainer,
        selectedIconTheme: IconThemeData(color: onPrimaryContainer),
        unselectedIconTheme: IconThemeData(color: textSecondary),
        selectedLabelTextStyle: TextStyle(
          color: onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: textSecondary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
