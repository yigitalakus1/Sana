import 'package:flutter/material.dart';

enum StatusKind { neutral, success, warning, error }

/// Yuvarlak, renk-kodlu küçük durum/etiket rozeti.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    this.kind = StatusKind.neutral,
    this.icon,
  });

  final String label;
  final StatusKind kind;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color bg;
    final Color fg;
    switch (kind) {
      case StatusKind.success:
        bg = scheme.secondaryContainer;
        fg = scheme.onSecondaryContainer;
        break;
      case StatusKind.warning:
        bg = scheme.tertiaryContainer;
        fg = scheme.onTertiaryContainer;
        break;
      case StatusKind.error:
        bg = scheme.errorContainer;
        fg = scheme.onErrorContainer;
        break;
      case StatusKind.neutral:
        bg = scheme.surfaceContainerHighest;
        fg = scheme.onSurfaceVariant;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Açıklamanın güven düzeyini (high/medium/low) gösteren chip.
/// NOT: Bu, açıklamanın güvenidir; tahlil değerinin medikal yorumu DEĞİLDİR.
class ConfidenceChip extends StatelessWidget {
  const ConfidenceChip({super.key, required this.confidenceLabel});

  final String confidenceLabel;

  String get _tr {
    switch (confidenceLabel) {
      case 'high':
        return 'yüksek';
      case 'medium':
        return 'orta';
      case 'low':
        return 'düşük';
      default:
        return confidenceLabel;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StatusChip(
      label: 'Güven düzeyi: $_tr',
      icon: Icons.verified_outlined,
    );
  }
}
