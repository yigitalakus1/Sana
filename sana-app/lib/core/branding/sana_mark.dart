import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Sana marka işareti: nabız halkası.
///
/// Tasarımdan birebir alınan geometri (96×96 kutu):
///   halka  `M48 13 A 35 35 0 1 1 27 20`  kalınlık 6, %55 saydam
///   nabız  `M27 48 H38 L44.5 34 L53 62 L58.5 48 H69`  kalınlık 9.5
///
/// "Kontrastlı" varyant seçildi: ince halka taşıyıcı zemin, kalın nabız ana
/// kahraman — küçük boyutta okunurluğu bunun için daha iyi.
///
/// Renk varsayılan olarak temanın birincil renginden gelir; böylece işaret
/// açık/koyu temada ve uygulama paletiyle kendiliğinden uyumlu kalır.
class SanaMark extends StatelessWidget {
  const SanaMark({super.key, this.size = 32, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final markColor = color ?? Theme.of(context).colorScheme.primary;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _SanaMarkPainter(markColor),
        isComplex: false,
      ),
    );
  }
}

class _SanaMarkPainter extends CustomPainter {
  const _SanaMarkPainter(this.color);

  final Color color;

  /// Tasarımın çizim kutusu.
  static const double _box = 96;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / _box;
    canvas.save();
    canvas.scale(scale);

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color.withValues(alpha: color.a * 0.55);

    // Merkez (48,48), yarıçap 35. Yay tepe noktasından (−90°) saat yönünde
    // 323.13° döner; SVG'deki large-arc + sweep bayraklarının karşılığı.
    const center = Offset(48, 48);
    const radius = 35.0;
    const startAngle = -math.pi / 2;
    const sweepAngle = 5.6398; // ≈ 323.13°
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      ring,
    );

    final pulse = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    final path = Path()
      ..moveTo(27, 48)
      ..lineTo(38, 48)
      ..lineTo(44.5, 34)
      ..lineTo(53, 62)
      ..lineTo(58.5, 48)
      ..lineTo(69, 48);
    canvas.drawPath(path, pulse);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SanaMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// İşaret + kelime markası. Kelime markası küçük harf "sana", ağırlık 500.
class SanaLogo extends StatelessWidget {
  const SanaLogo({
    super.key,
    this.markSize = 32,
    this.fontSize = 22,
    this.color,
  });

  final double markSize;
  final double fontSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final markColor = color ?? theme.colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SanaMark(size: markSize, color: markColor),
        SizedBox(width: markSize * 0.25),
        Text(
          'sana',
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.01 * fontSize,
            color: color ?? theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

/// Uygulama içi kutulanmış marka rozeti (yumuşak zemin + işaret).
///
/// Ana ekran ve kabuk başlığındaki marka alanında kullanılır.
class SanaMarkBadge extends StatelessWidget {
  const SanaMarkBadge({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
      ),
      child: SanaMark(
        size: size * 0.72,
        color: scheme.onPrimaryContainer,
      ),
    );
  }
}
