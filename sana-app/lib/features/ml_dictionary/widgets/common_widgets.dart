import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';

/// İçeriği büyük ekranlarda ortalar ve maksimum genişlikle sınırlar.
class ResponsiveCenter extends StatelessWidget {
  const ResponsiveCenter({
    super.key,
    required this.child,
    this.maxWidth = AppSpacing.maxContentWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Tam genişlik birincil buton; opsiyonel ikon + loading durumu.
class SanaPrimaryButton extends StatelessWidget {
  const SanaPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: loading ? null : onPressed,
        icon: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon ?? Icons.arrow_forward),
        label: Text(loading ? 'Lütfen bekleyin...' : label),
      ),
    );
  }
}

/// Uyarı kutusunun iki seviyesi.
///
/// [neutral] her ekranda görünen sessiz uyarıdır; [attention] yalnız raporun
/// kendi aralığının dışındaki değerlerde kullanılır ve doktora yönlendirir.
/// Böylece zorunlu uyarı tekrar ede ede körelmez.
enum DisclaimerLevel { neutral, attention }

/// Her açıklama/sonuç ekranında gösterilen yasal/medikal uyarı kutusu.
class DisclaimerBox extends StatelessWidget {
  const DisclaimerBox({
    super.key,
    required this.text,
    this.title,
    this.level = DisclaimerLevel.neutral,
  });

  final String text;

  /// Kalın üst satır. Verilmezse seviyeye göre varsayılan başlık kullanılır.
  final String? title;
  final DisclaimerLevel level;

  /// Aralık dışı bir değer için doktora yönlendiren kehribar uyarı.
  const DisclaimerBox.attention({
    super.key,
    required this.text,
    this.title,
  }) : level = DisclaimerLevel.attention;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final attention = level == DisclaimerLevel.attention;

    final Color background = attention
        ? scheme.tertiaryContainer
        : scheme.surface;
    final Color foreground = attention
        ? scheme.onTertiaryContainer
        : scheme.onSurface;
    final Color bodyColor = attention
        ? scheme.onTertiaryContainer.withValues(alpha: 0.85)
        : scheme.onSurfaceVariant;
    final String heading =
        title ?? (attention ? 'Bu değeri doktorunuza sorun' : 'Bu bir teşhis değildir');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: attention ? null : Border.all(color: scheme.outline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            attention ? Icons.medical_services_outlined : Icons.info_outline,
            size: 20,
            color: attention ? foreground : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  heading,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: foreground,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.5,
                    color: bodyColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Boş / yükleniyor / hata durumları için ortak kart.
///
/// Tasarım: ortalanmış, 32px ikon, 13.5/600 başlık, 12/400 açıklama.
class SanaStateCard extends StatelessWidget {
  const SanaStateCard({
    super.key,
    required this.title,
    required this.message,
    this.icon,
    this.loading = false,
    this.action,
  });

  /// Yükleniyor hâli: ikon yerine ilerleme göstergesi.
  const SanaStateCard.loading({
    super.key,
    required this.title,
    required this.message,
  }) : icon = null,
       loading = true,
       action = null;

  final String title;
  final String message;
  final IconData? icon;
  final bool loading;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          if (loading)
            SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: scheme.primary,
                backgroundColor: scheme.primaryContainer,
              ),
            )
          else
            Icon(icon, size: 32, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: AppSpacing.md),
            action!,
          ],
        ],
      ),
    );
  }
}

/// Kullanıcı dostu hata kutusu (crash yerine).
class ErrorBox extends StatelessWidget {
  const ErrorBox({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
