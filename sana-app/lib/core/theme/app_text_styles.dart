import 'package:flutter/material.dart';

/// Hiyerarşik metin stilleri için ince yardımcılar (Material 3 textTheme üstüne).
class AppTextStyles {
  AppTextStyles._();

  static TextStyle? heroTitle(BuildContext context) => Theme.of(
    context,
  ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700);

  static TextStyle? screenTitle(BuildContext context) => Theme.of(
    context,
  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700);

  static TextStyle? sectionTitle(BuildContext context) => Theme.of(
    context,
  ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600);

  static TextStyle? muted(BuildContext context) => Theme.of(context)
      .textTheme
      .bodyMedium
      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);

  static TextStyle? caption(BuildContext context) => Theme.of(context)
      .textTheme
      .bodySmall
      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
}
