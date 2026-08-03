import 'package:flutter/material.dart';

import '../../../core/network/sana_api_client.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../models/explain_response.dart';
import '../services/ml_dictionary_service.dart';
import '../widgets/common_widgets.dart';
import '../widgets/sana_card.dart';
import '../widgets/section_header.dart';
import '../widgets/status_chip.dart';

class ExplainScreen extends StatefulWidget {
  const ExplainScreen({super.key, this.initialQuestion, this.initialLabTest});

  final String? initialQuestion;
  final String? initialLabTest;

  @override
  State<ExplainScreen> createState() => _ExplainScreenState();
}

class _ExplainScreenState extends State<ExplainScreen> {
  final MlDictionaryService _service = MlDictionaryService();
  late final TextEditingController _questionCtrl;
  late final TextEditingController _labTestCtrl;

  bool _loading = false;
  String? _error;
  ExplainResponse? _result;

  @override
  void initState() {
    super.initState();
    _questionCtrl = TextEditingController(
      text: widget.initialQuestion ?? 'CRP 13.5 çıktı',
    );
    _labTestCtrl = TextEditingController(text: widget.initialLabTest ?? '');
  }

  @override
  void dispose() {
    _questionCtrl.dispose();
    _labTestCtrl.dispose();
    super.dispose();
  }

  Future<void> _explain() async {
    final question = _questionCtrl.text.trim();
    if (question.isEmpty) {
      setState(() => _error = 'Lütfen bir soru girin.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final labTest = _labTestCtrl.text.trim();
      final res = await _service.explainLab(
        question: question,
        labTest: labTest.isEmpty ? null : labTest,
      );
      if (!mounted) return;
      setState(() => _result = res);
    } on SanaApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Beklenmeyen bir hata oluştu.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sonuç Açıkla')),
      body: ResponsiveCenter(
        child: ListView(
          padding: AppSpacing.pagePadding(MediaQuery.sizeOf(context).width),
          children: [
            Text(
              'Tahlil adını veya sonucunu yaz. Test adını boş bırakırsan Sana '
              'sorudan algılamaya çalışır.',
              style: AppTextStyles.muted(context),
            ),
            const SizedBox(height: AppSpacing.lg),
            SanaCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _questionCtrl,
                    minLines: 2,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      labelText: 'Sorunuz',
                      hintText: 'Örn: CRP 13.5 çıktı',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _labTestCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Test adı (isteğe bağlı)',
                      hintText: 'Örn: CRP',
                      helperText: 'Boş bırakırsan sorudan otomatik algılanır.',
                      prefixIcon: Icon(Icons.biotech_outlined),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SanaPrimaryButton(
                    label: 'Açıkla',
                    icon: Icons.auto_awesome,
                    loading: _loading,
                    onPressed: _explain,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_error != null) ErrorBox(message: _error!),
            if (_result != null) _ExplainResultView(result: _result!),
            if (_result == null && _error == null && !_loading)
              const _ExplainEmptyState(),
          ],
        ),
      ),
    );
  }
}

class _ExplainResultView extends StatelessWidget {
  const _ExplainResultView({required this.result});

  final ExplainResponse result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rc = result.resultContext;
    final children = <Widget>[];

    if (result.responseType != 'answer') {
      children.add(
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          margin: const EdgeInsets.only(bottom: AppSpacing.md),
          decoration: BoxDecoration(
            color: scheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Text(
            result.responseType == 'safety_block'
                ? 'Güvenlik gereği bu soru yanıtlanmadı.'
                : 'Yeterli kaynak eşleşmesi bulunamadı.',
            style: TextStyle(color: scheme.onTertiaryContainer),
          ),
        ),
      );
    }

    // Açıklama kartı
    children.add(
      SanaCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, size: 18, color: scheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Text('Açıklama', style: AppTextStyles.sectionTitle(context)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              result.answer,
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                ConfidenceChip(confidenceLabel: result.confidenceLabel),
                if (result.labTest != null && result.labTest!.isNotEmpty)
                  StatusChip(label: result.labTest!),
              ],
            ),
          ],
        ),
      ),
    );

    // Girilen değer (yorum yok, yalnız veri)
    if (rc != null && rc.rawValue != null) {
      children.add(const SizedBox(height: AppSpacing.md));
      children.add(
        SanaCard(
          child: Row(
            children: [
              Icon(Icons.straighten, color: scheme.primary),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Girilen değer: ${rc.rawValue}',
                      style: theme.textTheme.bodyLarge,
                    ),
                    if (rc.unit != null && rc.unit!.isNotEmpty)
                      Text(
                        'Birim: ${rc.unit}',
                        style: AppTextStyles.caption(context),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Kaynaklar
    if (result.citations.isNotEmpty) {
      children.add(const SizedBox(height: AppSpacing.lg));
      children.add(const SectionHeader('Kaynaklar'));
      children.add(
        SanaCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (int i = 0; i < result.citations.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.link),
                  title: Text(result.citations[i].sourceTitle),
                  subtitle: result.citations[i].sourceUrl != null
                      ? Text(
                          result.citations[i].sourceUrl!,
                          style: theme.textTheme.bodySmall,
                        )
                      : null,
                ),
              ],
            ],
          ),
        ),
      );
    }

    // Doktora sorulabilecek sorular
    if (result.doctorQuestions.isNotEmpty) {
      children.add(const SizedBox(height: AppSpacing.lg));
      children.add(const SectionHeader('Doktora sorulabilecek sorular'));
      children.add(
        SanaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int i = 0; i < result.doctorQuestions.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 11,
                        backgroundColor: scheme.primaryContainer,
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: Text(result.doctorQuestions[i])),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    }

    children.add(const SizedBox(height: AppSpacing.lg));
    children.add(DisclaimerBox(text: result.disclaimer));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _ExplainEmptyState extends StatelessWidget {
  const _ExplainEmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.auto_awesome_outlined,
              size: 28,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Açıklama burada görünecek',
            style: AppTextStyles.sectionTitle(context),
          ),
          const SizedBox(height: 4),
          Text('Örnek: CRP 13.5 çıktı', style: AppTextStyles.caption(context)),
        ],
      ),
    );
  }
}
