import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../services/ml_dictionary_service.dart';
import '../widgets/common_widgets.dart';
import '../widgets/status_chip.dart';
import 'assistant_screen.dart';
import 'explain_screen.dart';
import 'profile_screen.dart';
import 'report_parse_screen.dart';
import 'report_history_screen.dart';
import 'terms_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.onOpenExplain,
    this.onOpenTerms,
    this.onOpenReport,
    this.onOpenAssistant,
    this.onOpenSettings,
  });

  final VoidCallback? onOpenExplain;
  final VoidCallback? onOpenTerms;
  final VoidCallback? onOpenReport;
  final VoidCallback? onOpenAssistant;
  final VoidCallback? onOpenSettings;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final MlDictionaryService _service = MlDictionaryService();
  bool _checking = false;
  bool? _healthy;

  @override
  void initState() {
    super.initState();
    _checkHealth();
  }

  Future<void> _checkHealth() async {
    setState(() => _checking = true);
    final ok = await _service.healthCheck();
    if (!mounted) return;
    setState(() {
      _healthy = ok;
      _checking = false;
    });
  }

  void _open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  void _openExplain() {
    final callback = widget.onOpenExplain;
    callback != null ? callback() : _open(const ExplainScreen());
  }

  void _openTerms() {
    final callback = widget.onOpenTerms;
    callback != null ? callback() : _open(const TermsScreen());
  }

  void _openReport() {
    final callback = widget.onOpenReport;
    callback != null ? callback() : _open(const ReportParseScreen());
  }

  void _openAssistant() {
    final callback = widget.onOpenAssistant;
    callback != null ? callback() : _open(const AssistantScreen());
  }

  void _openHistory() => _open(const ReportHistoryScreen());

  void _openProfile() => _open(const ProfileScreen());

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      body: SafeArea(
        child: ResponsiveCenter(
          child: ListView(
            padding: AppSpacing.pagePadding(width).copyWith(bottom: 32),
            children: [
              _PageHeader(
                checking: _checking,
                healthy: _healthy,
                onRetry: _checkHealth,
                onSettings: widget.onOpenSettings,
              ),
              const SizedBox(height: 32),
              const _SectionLabel(
                title: 'Ne yapmak istiyorsun?',
                subtitle: 'Devam etmek için bir işlem seç.',
              ),
              const SizedBox(height: AppSpacing.md),
              _ActionGrid(
                actions: [
                  _ActionData(
                    icon: Icons.auto_awesome_outlined,
                    title: 'Sonuç Açıkla',
                    subtitle: 'Tek bir tahlil sonucunu kaynaklarıyla açıkla.',
                    color: AppColors.primary,
                    softColor: AppColors.primarySoft,
                    onTap: _openExplain,
                  ),
                  _ActionData(
                    icon: Icons.menu_book_outlined,
                    title: 'Tahlil Sözlüğü',
                    subtitle: 'Desteklenen testleri ve kaynaklarını incele.',
                    color: AppColors.accentBlueDeep,
                    softColor: AppColors.accentBlueSoft,
                    onTap: _openTerms,
                  ),
                  _ActionData(
                    icon: Icons.description_outlined,
                    title: 'Rapor Metni Tara',
                    subtitle: 'Birden fazla sonucu düzenli bir listeye ayır.',
                    color: AppColors.accentLavenderDeep,
                    softColor: AppColors.accentLavender,
                    onTap: _openReport,
                  ),
                  _ActionData(
                    icon: Icons.forum_outlined,
                    title: 'Sana Asistan',
                    subtitle:
                        'Tahlil sonuçların hakkında kaynaklı sorular sor.',
                    color: AppColors.primaryDeep,
                    softColor: AppColors.primarySoft,
                    onTap: _openAssistant,
                  ),
                  _ActionData(
                    icon: Icons.history,
                    title: 'Rapor Geçmişi',
                    subtitle:
                        'Kaydedilen raporları ve değişim grafiklerini aç.',
                    color: AppColors.warningText,
                    softColor: AppColors.warningSoft,
                    onTap: _openHistory,
                  ),
                  _ActionData(
                    icon: Icons.person_outline,
                    title: 'Sağlık Profili',
                    subtitle: 'İsteğe bağlı kişisel bağlamını bu cihazda tut.',
                    color: AppColors.accentBlueDeep,
                    softColor: AppColors.accentBlueSoft,
                    onTap: _openProfile,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.checking,
    required this.healthy,
    required this.onRetry,
    this.onSettings,
  });

  final bool checking;
  final bool? healthy;
  final VoidCallback onRetry;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 1024;
    return Row(
      children: [
        if (compact) ...[
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.favorite_rounded,
              color: Colors.white,
              size: 19,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                compact ? 'Sana' : 'Genel Bakış',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (!compact)
                Text(
                  'Laboratuvar sonuçlarını sade ve güvenli biçimde incele.',
                  style: AppTextStyles.caption(context),
                ),
            ],
          ),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: checking ? null : onRetry,
          child: StatusChip(
            label: checking
                ? 'Kontrol ediliyor'
                : healthy == true
                ? 'Yerel servis hazır'
                : 'Bağlantı yok',
            kind: healthy == true ? StatusKind.success : StatusKind.neutral,
            icon: checking
                ? Icons.sync
                : healthy == true
                ? Icons.check_circle_outline
                : Icons.refresh,
          ),
        ),
        if (onSettings != null) ...[
          const SizedBox(width: AppSpacing.sm),
          IconButton(
            tooltip: 'Ayarlar',
            onPressed: onSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTextStyles.sectionTitle(context)),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(subtitle!, style: AppTextStyles.caption(context)),
        ],
      ],
    );
  }
}

class _ActionData {
  const _ActionData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.softColor,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Color softColor;
  final VoidCallback onTap;
}

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({required this.actions});

  final List<_ActionData> actions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 620 ? 2 : 1;
        final width =
            (constraints.maxWidth - (columns - 1) * AppSpacing.md) / columns;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final action in actions)
              SizedBox(
                width: width,
                child: _ActionTile(data: action),
              ),
          ],
        );
      },
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.data});

  final _ActionData data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: data.softColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(data.icon, color: data.color, size: 22),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.title,
                      style: AppTextStyles.sectionTitle(context),
                    ),
                    const SizedBox(height: 2),
                    Text(data.subtitle, style: AppTextStyles.caption(context)),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(
                Icons.arrow_forward_rounded,
                size: 19,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
