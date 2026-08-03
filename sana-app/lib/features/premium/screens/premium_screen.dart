import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../ml_dictionary/widgets/common_widgets.dart';

/// Premium özelliklerini anlatan bilgilendirme ekranı.
///
/// Bu ilk sürüm satın alma tamamlanmış gibi davranmaz: gerçek mağaza
/// bağlantısı kurulana kadar satın alma düğmesi pasiftir ve hiçbir yerde
/// premium yetkisi verilmez.
class PremiumScreen extends StatelessWidget {
  const PremiumScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Premium')),
      body: ResponsiveCenter(
        child: ListView(
          padding: AppSpacing.pagePadding(
            MediaQuery.sizeOf(context).width,
          ).copyWith(bottom: 32),
          children: [
            Text(
              'Premium ile açılan özellikler',
              style: AppTextStyles.sectionTitle(context),
            ),
            const SizedBox(height: AppSpacing.sm),
            const _FeatureSurface(
              children: [
                _FeatureRow(
                  icon: Icons.history_outlined,
                  title: 'Tüm rapor geçmişi',
                  subtitle: 'Cihazında saklanan raporların tamamını görürsün.',
                ),
                Divider(height: 1),
                _FeatureRow(
                  icon: Icons.checklist_rounded,
                  title: 'İstediğin raporları seçerek karşılaştırma',
                  subtitle: 'Kıyaslamak istediğin raporları kendin seçersin.',
                ),
                Divider(height: 1),
                _FeatureRow(
                  icon: Icons.show_chart_rounded,
                  title: 'Zaman içindeki ölçüm grafikleri',
                  subtitle: 'Aynı tahlilin raporlar arasındaki seyrini görürsün.',
                ),
                Divider(height: 1),
                _FeatureRow(
                  icon: Icons.ios_share_outlined,
                  title: 'Rapor dışa aktarma',
                  subtitle: 'Bu özellik henüz hazır değil; sonraki sürümde.',
                  upcoming: true,
                ),
              ],
            ),
            const SizedBox(height: 28),
            Text(
              'Ücretsiz sürümde kalanlar',
              style: AppTextStyles.sectionTitle(context),
            ),
            const SizedBox(height: AppSpacing.sm),
            const _FeatureSurface(
              children: [
                _FeatureRow(
                  icon: Icons.health_and_safety_outlined,
                  title: 'Güvenlik uyarıları ve kaynaklar',
                  subtitle:
                      'Sağlıkla ilgili uyarılar hiçbir zaman ücretli olmaz.',
                ),
                Divider(height: 1),
                _FeatureRow(
                  icon: Icons.description_outlined,
                  title: 'En güncel raporunun açıklaması',
                  subtitle: 'Tek raporun okunması ve açıklanması ücretsizdir.',
                ),
              ],
            ),
            const SizedBox(height: 28),
            const _StoreStatusNotice(),
            const SizedBox(height: AppSpacing.lg),
            const SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: null,
                child: Text('Mağaza bağlantısı hazırlanıyor'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoreStatusNotice extends StatelessWidget {
  const _StoreStatusNotice();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: scheme.onSurfaceVariant, size: 19),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Abonelik henüz satışta değil. Mağaza bağlantısı kurulana kadar '
              'buradan satın alma yapılamaz ve hesabına premium tanımlanmaz. '
              'Önceki raporların cihazında korunur.',
              style: AppTextStyles.caption(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureSurface extends StatelessWidget {
  const _FeatureSurface({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(children: children),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.upcoming = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool upcoming;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: scheme.primary),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: upcoming
          ? Chip(
              label: const Text('Yakında'),
              visualDensity: VisualDensity.compact,
              side: BorderSide(color: scheme.outlineVariant),
            )
          : null,
    );
  }
}
