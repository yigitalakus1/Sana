import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';

/// Ücretsiz sürümde karşılaştırma panelinin yerini alan kısa premium bandı.
///
/// Premium katmanı ürün işleri tamamlandıktan sonra devreye alınacaktır; bu
/// widget o zamana kadar hazır bekler ve `ReportHistoryScreen` içine yeniden
/// bağlanır.
///
/// Kayıtları silmez, yalnız görünürlüğü sınırlayan ekranın yanında bilgi verir:
/// eski raporlar cihazda durur ve premium erişimde yeniden görünür.
class PremiumComparisonBand extends StatelessWidget {
  const PremiumComparisonBand({
    super.key,
    required this.preservedCount,
    required this.onExplore,
  });

  /// Ücretsiz sürümde gösterilmeyen ama cihazda korunan rapor sayısı.
  final int preservedCount;
  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_outline, color: scheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Rapor karşılaştırma premium özelliktir',
                  style: AppTextStyles.sectionTitle(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Ücretsiz sürümde en güncel raporunu görürsün. '
            'Önceki raporların cihazında korunur; premium ile tüm geçmiş ve '
            'karşılaştırma grafiği yeniden açılır.',
            style: AppTextStyles.muted(context),
          ),
          if (preservedCount > 0) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Şu an cihazında korunan diğer rapor sayısı: $preservedCount',
              style: AppTextStyles.caption(context),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: onExplore,
              icon: const Icon(Icons.workspace_premium_outlined),
              label: const Text('Premium özellikleri incele'),
            ),
          ),
        ],
      ),
    );
  }
}
