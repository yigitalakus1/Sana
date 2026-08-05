import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

enum StatusKind { neutral, success, warning, error }

/// Tam yuvarlak, renk-kodlu küçük durum/etiket rozeti.
///
/// Tasarım: 6/12 iç boşluk, 13/600 metin, 16px ikon, kenarlık yok — renk
/// zeminden gelir. Tahlil sonucu göstergesi için [SanaStatusChip] kullanılır.
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
    final status = context.statusColors;
    final (Color bg, Color fg) = switch (kind) {
      StatusKind.success => (
        status.inRange.background,
        status.inRange.foreground,
      ),
      StatusKind.warning => (status.above.background, status.above.foreground),
      StatusKind.error => (scheme.errorContainer, scheme.onErrorContainer),
      StatusKind.neutral => (
        status.unknown.background,
        status.unknown.foreground,
      ),
    };

    return _ChipShell(background: bg, foreground: fg, icon: icon, label: label);
  }
}

/// Tahlil sonucunun raporun kendi aralığına göre durumu.
///
/// Dört hâl: aralıkta · aralığın üstünde · aralığın altında · aralık
/// verilmemiş. Kırmızı kullanılmaz; yüksek kehribar, düşük mavidir.
class SanaStatusChip extends StatelessWidget {
  const SanaStatusChip({super.key, required this.status, this.label});

  final SanaStatus status;

  /// Varsayılan metni değiştirmek için.
  final String? label;

  static const _labels = <SanaStatus, String>{
    SanaStatus.inRange: 'Aralıkta',
    SanaStatus.above: 'Aralığın üstünde',
    SanaStatus.below: 'Aralığın altında',
    SanaStatus.unknown: 'Aralık verilmemiş',
  };

  static const _icons = <SanaStatus, IconData?>{
    SanaStatus.inRange: Icons.check_rounded,
    SanaStatus.above: Icons.north_rounded,
    SanaStatus.below: Icons.south_rounded,
    SanaStatus.unknown: null,
  };

  @override
  Widget build(BuildContext context) {
    final style = context.statusStyle(status);
    return _ChipShell(
      background: style.background,
      foreground: style.foreground,
      icon: _icons[status],
      label: label ?? _labels[status]!,
    );
  }
}

/// "Cihazda çalışır" güven rozeti — verinin cihazdan çıkmadığını anlatır.
class DeviceOnlyBadge extends StatelessWidget {
  const DeviceOnlyBadge({super.key, this.label = 'Cihazda çalışır'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: theme.textTheme.bodyMedium?.color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipShell extends StatelessWidget {
  const _ChipShell({
    required this.background,
    required this.foreground,
    required this.label,
    this.icon,
  });

  final Color background;
  final Color foreground;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(icon == null ? 12 : 8, 6, 12, 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: foreground),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
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
