import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';

/// Beyaz, ince kenarlıklı ortak içerik yüzeyi.
/// Opsiyonel dokunma (rounded ink splash).
class SanaCard extends StatelessWidget {
  const SanaCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(AppSpacing.radiusLg);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: radius,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
