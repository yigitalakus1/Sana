import 'package:flutter/material.dart';

import '../../../core/network/sana_api_client.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../models/explain_response.dart';
import '../models/term_models.dart';
import '../services/ml_dictionary_service.dart';
import '../widgets/common_widgets.dart';
import '../widgets/sana_card.dart';
import '../widgets/section_header.dart';
import '../widgets/status_chip.dart';
import 'assistant_screen.dart';

class TermDetailScreen extends StatefulWidget {
  const TermDetailScreen({
    super.key,
    required this.labTest,
    this.onAskAssistant,
    this.service,
  });

  final String labTest;
  final void Function(String question, String labTest)? onAskAssistant;
  final MlDictionaryService? service;

  @override
  State<TermDetailScreen> createState() => _TermDetailScreenState();
}

class _TermDetailScreenState extends State<TermDetailScreen> {
  late final MlDictionaryService _service;
  late Future<TermDetail> _future;

  // Tek açık bölüm (accordion). Cevaplar cache'lenir.
  String? _expanded;
  final Map<String, ExplainResponse> _responses = {};
  final Map<String, bool> _loading = {};
  final Map<String, String> _errors = {};

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? MlDictionaryService();
    _future = _service.getTermDetail(widget.labTest);
  }

  String get _assistantQuestion => '${widget.labTest} nedir?';

  void _openAssistant() {
    final callback = widget.onAskAssistant;
    if (callback != null) {
      callback(_assistantQuestion, widget.labTest);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AssistantScreen(
          initialQuestion: _assistantQuestion,
          prefillRevision: 1,
        ),
      ),
    );
  }

  String _buildQuestion(String labTest, String section) {
    switch (section) {
      case 'Nedir?':
        return '$labTest nedir?';
      case 'Neden ölçülür?':
        return '$labTest neden ölçülür?';
      case 'Yüksek ne anlama gelebilir?':
        return '$labTest yüksekliği ne anlama gelebilir?';
      case 'Düşük ne anlama gelebilir?':
        return '$labTest düşüklüğü ne anlama gelebilir?';
      case 'Ne zaman doktora danışılmalı?':
        return '$labTest sonucunda ne zaman doktora danışılmalı?';
      case 'Doktora sorulabilecek sorular':
        return '$labTest sonucu için doktora hangi sorular sorulabilir?';
      default:
        return '$labTest $section';
    }
  }

  void _toggle(String labTest, String section) {
    if (_expanded == section) {
      setState(() => _expanded = null);
      return;
    }
    setState(() => _expanded = section);
    if (!_responses.containsKey(section) && !(_loading[section] ?? false)) {
      _fetch(labTest, section);
    }
  }

  Future<void> _fetch(String labTest, String section) async {
    setState(() {
      _loading[section] = true;
      _errors.remove(section);
    });
    try {
      // Açıklama backend /explain'den gelir; Flutter'da içerik tutulmaz.
      final res = await _service.explainLab(
        question: _buildQuestion(labTest, section),
        labTest: labTest,
        // Sözlük bölümleri zaten hazır ve onaylı içeriktir; modeli çalıştırıp
        // beklemek yerine kaynak metni doğrudan gösterilir.
        useSourceText: true,
      );
      if (!mounted) return;
      setState(() {
        _responses[section] = res;
        _loading[section] = false;
      });
    } on SanaApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errors[section] = e.message;
        _loading[section] = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errors[section] = 'Açıklama alınamadı.';
        _loading[section] = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.labTest),
        actions: [
          IconButton(
            onPressed: _openAssistant,
            tooltip: 'Asistana sor',
            icon: const Icon(Icons.smart_toy_outlined),
          ),
        ],
      ),
      body: ResponsiveCenter(
        child: FutureBuilder<TermDetail>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              final error = snapshot.error;
              final message = error is SanaApiException
                  ? error.message
                  : 'Detay yüklenemedi.';
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: ErrorBox(message: message),
                ),
              );
            }
            final detail = snapshot.data!;
            return ListView(
              padding: AppSpacing.pagePadding(MediaQuery.sizeOf(context).width),
              children: [
                _TermHeader(detail: detail),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: _openAssistant,
                    icon: const Icon(Icons.smart_toy_outlined),
                    label: const Text('Bu tahlili Asistana sor'),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                const SectionHeader('Bölümler'),
                for (final section in detail.sections)
                  _SectionCard(
                    section: section,
                    expanded: _expanded == section,
                    loading: _loading[section] ?? false,
                    error: _errors[section],
                    response: _responses[section],
                    onTap: () => _toggle(detail.labTest, section),
                  ),
                if (detail.sources.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  const SectionHeader('Kaynaklar'),
                  SanaCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (int i = 0; i < detail.sources.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.link),
                            title: Text(detail.sources[i].sourceTitle),
                            subtitle:
                                detail.sources[i].sourceUrl != null &&
                                    detail.sources[i].sourceUrl!.isNotEmpty
                                ? Text(
                                    detail.sources[i].sourceUrl!,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  )
                                : null,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TermHeader extends StatelessWidget {
  const _TermHeader({required this.detail});

  final TermDetail detail;

  @override
  Widget build(BuildContext context) {
    return SanaCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(AppSpacing.radius),
            ),
            child: Text(
              detail.labTest.isNotEmpty ? detail.labTest.substring(0, 1) : '?',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(detail.labTest, style: AppTextStyles.heroTitle(context)),
                if (detail.title != null) ...[
                  const SizedBox(height: 2),
                  Text(detail.title!, style: AppTextStyles.muted(context)),
                ],
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Bölümleri açarak kaynaklı açıklamaları görüntüleyebilirsin.',
                  style: AppTextStyles.caption(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.section,
    required this.expanded,
    required this.loading,
    required this.error,
    required this.response,
    required this.onTap,
  });

  final String section;
  final bool expanded;
  final bool loading;
  final String? error;
  final ExplainResponse? response;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Card(
        clipBehavior: Clip.antiAlias,
        // Açılmış bölüm: temadan gelen kap rengi. Sabit açık yeşil koyu temada
        // metni okunmaz hâle getiriyordu.
        color: expanded ? scheme.primaryContainer.withValues(alpha: 0.35) : null,
        shape: expanded
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                side: BorderSide(color: scheme.primary, width: 1.4),
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: Icon(
                expanded ? Icons.label : Icons.label_outline,
                color: expanded ? scheme.primary : null,
              ),
              title: Text(
                section,
                style: TextStyle(
                  fontWeight: expanded ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              trailing: Icon(expanded ? Icons.expand_less : Icons.expand_more),
              onTap: onTap,
            ),
            if (expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: _buildPanel(context),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanel(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: AppSpacing.md),
            Text('Açıklama hazırlanıyor...'),
          ],
        ),
      );
    }
    if (error != null) {
      return ErrorBox(message: error!);
    }
    final res = response;
    if (res == null) return const SizedBox.shrink();
    return _SectionExplanation(response: res);
  }
}

class _SectionExplanation extends StatelessWidget {
  const _SectionExplanation({required this.response});

  final ExplainResponse response;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final children = <Widget>[
      Text(
        response.answer,
        style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
      ),
      const SizedBox(height: AppSpacing.sm),
      Align(
        alignment: Alignment.centerLeft,
        child: ConfidenceChip(confidenceLabel: response.confidenceLabel),
      ),
    ];

    if (response.citations.isNotEmpty) {
      children.add(const SizedBox(height: AppSpacing.md));
      children.add(
        Text('Kaynaklar', style: AppTextStyles.sectionTitle(context)),
      );
      for (final c in response.citations) {
        children.add(
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.link, size: 20),
            title: Text(c.sourceTitle),
            subtitle: c.sourceUrl != null && c.sourceUrl!.isNotEmpty
                ? Text(c.sourceUrl!, style: theme.textTheme.bodySmall)
                : null,
          ),
        );
      }
    }

    if (response.doctorQuestions.isNotEmpty) {
      children.add(const SizedBox(height: AppSpacing.sm));
      children.add(
        Text(
          'Doktora sorulabilecek sorular',
          style: AppTextStyles.sectionTitle(context),
        ),
      );
      for (final q in response.doctorQuestions) {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.help_outline, size: 18, color: scheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(q, style: theme.textTheme.bodySmall)),
              ],
            ),
          ),
        );
      }
    }

    children.add(const SizedBox(height: AppSpacing.md));
    children.add(DisclaimerBox(text: response.disclaimer));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}
