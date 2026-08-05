import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/network/sana_api_client.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../models/explain_response.dart';
import '../models/report_parse_models.dart';
import '../services/ml_dictionary_service.dart';
import '../services/report_history_service.dart';
import '../widgets/common_widgets.dart';
import '../widgets/status_chip.dart';
import 'explain_screen.dart';
import 'report_history_screen.dart';

const String _sampleReport = 'CRP: 13.5 mg/L\nGlukoz 92 mg/dL\nB12 350 pg/mL';
const int _maxPdfBytes = 10 * 1024 * 1024;

enum _ReportInputMode { pdf, text }

class ReportParseScreen extends StatefulWidget {
  const ReportParseScreen({
    super.key,
    this.onExplainRequested,
    this.onAskAssistant,
    this.service,
    this.historyService,
  });

  final void Function(String question, String? labTest)? onExplainRequested;
  final ValueChanged<String>? onAskAssistant;
  final MlDictionaryService? service;
  final ReportHistoryService? historyService;

  @override
  State<ReportParseScreen> createState() => _ReportParseScreenState();
}

class _ReportParseScreenState extends State<ReportParseScreen> {
  late final MlDictionaryService _service =
      widget.service ?? MlDictionaryService();
  late final ReportHistoryService _historyService =
      widget.historyService ?? ReportHistoryService();
  late final TextEditingController _textCtrl = TextEditingController(
    text: _sampleReport,
  );

  _ReportInputMode _mode = _ReportInputMode.pdf;
  Uint8List? _pdfBytes;
  String? _pdfName;
  bool _loading = false;
  bool _manualCorrectionSuggested = false;
  String? _error;
  ReportParseResponse? _result;

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  void _setMode(_ReportInputMode mode) {
    setState(() {
      _mode = mode;
      _error = null;
      _manualCorrectionSuggested = false;
      _result = null;
    });
  }

  Future<void> _pickPdf() async {
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        withData: true,
        allowMultiple: false,
      );
      if (!mounted || picked == null) return;

      final file = picked.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        setState(() => _error = 'PDF dosyası okunamadı.');
        return;
      }
      if (bytes.length > _maxPdfBytes) {
        setState(() => _error = 'PDF dosyası en fazla 10 MB olabilir.');
        return;
      }
      setState(() {
        _pdfBytes = bytes;
        _pdfName = file.name;
        _error = null;
        _result = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'PDF dosyası seçilemedi.');
    }
  }

  Future<void> _parsePdf() async {
    final bytes = _pdfBytes;
    final name = _pdfName;
    if (bytes == null || name == null) {
      setState(() => _error = 'Önce bir PDF raporu seçin.');
      return;
    }
    await _runParse(
      () => _service.parsePdfReport(fileName: name, bytes: bytes),
    );
  }

  Future<void> _parseText() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Lütfen rapor metni girin.');
      return;
    }
    await _runParse(() => _service.parseReport(text));
  }

  Future<void> _runParse(Future<ReportParseResponse> Function() action) async {
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await action();
      if (result.results.isNotEmpty) {
        try {
          await _historyService.save(
            sourceName: _mode == _ReportInputMode.pdf
                ? (_pdfName ?? 'PDF raporu')
                : 'Yapıştırılan rapor',
            results: result.results,
            reportDate: result.reportDate,
          );
        } catch (_) {
          // Ayrıştırma sonucu, yerel geçmiş yazılamasa da gösterilir.
        }
      }
      if (mounted) setState(() => _result = result);
    } on SanaApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _manualCorrectionSuggested =
              _mode == _ReportInputMode.pdf && error.statusCode == 422;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Beklenmeyen bir hata oluştu.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReportHistoryScreen(service: _historyService),
      ),
    );
  }

  void _askAssistant(ReportParseResponse response) {
    final values = response.results
        .map(
          (result) => [
            result.labTest,
            result.rawValue,
            result.unit,
          ].whereType<String>().where((value) => value.isNotEmpty).join(' '),
        )
        .join(', ');
    final question =
        'Bu laboratuvar raporundaki değerleri yalnızca bilgilendirme amacıyla, kaynaklara dayanarak açıkla: $values';
    final callback = widget.onAskAssistant;
    if (callback != null) callback(question);
  }

  void _explainResult(ParsedLabResult result) {
    final question = _resultExplanationQuestion(result);

    final callback = widget.onExplainRequested;
    if (callback != null) {
      callback(question, result.labTest);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ExplainScreen(
          initialQuestion: question,
          initialLabTest: result.labTest,
        ),
      ),
    );
  }

  Future<ExplainResponse> _loadResultExplanation(ParsedLabResult result) {
    final question = _resultExplanationQuestion(result);
    return _service.explainLab(question: question, labTest: result.labTest);
  }

  void _compareResult(ParsedLabResult result) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReportHistoryScreen(
          service: _historyService,
          initialLabTest: result.labTest,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rapor Tara'),
        actions: [
          IconButton(
            tooltip: 'Rapor geçmişi',
            onPressed: _openHistory,
            icon: const Icon(Icons.history),
          ),
        ],
      ),
      body: ResponsiveCenter(
        child: ListView(
          padding: AppSpacing.pagePadding(
            MediaQuery.sizeOf(context).width,
          ).copyWith(bottom: 32),
          children: [
            Text(
              'Laboratuvar raporunu ekle',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'PDF yükle veya rapor metnini yapıştır. Bulunan tahliller aşağıda ayrı ayrı listelenir.',
              style: AppTextStyles.caption(context),
            ),
            const SizedBox(height: AppSpacing.lg),
            SegmentedButton<_ReportInputMode>(
              segments: const [
                ButtonSegment(
                  value: _ReportInputMode.pdf,
                  icon: Icon(Icons.picture_as_pdf_outlined),
                  label: Text('PDF yükle'),
                ),
                ButtonSegment(
                  value: _ReportInputMode.text,
                  icon: Icon(Icons.text_snippet_outlined),
                  label: Text('Metin yapıştır'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: _loading
                  ? null
                  : (selection) => _setMode(selection.first),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_mode == _ReportInputMode.pdf)
              _PdfInput(
                fileName: _pdfName,
                fileSize: _pdfBytes?.length,
                loading: _loading,
                onPick: _pickPdf,
                onParse: _parsePdf,
              )
            else
              _TextInput(
                controller: _textCtrl,
                loading: _loading,
                onLoadSample: () =>
                    setState(() => _textCtrl.text = _sampleReport),
                onParse: _parseText,
              ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.lg),
              ErrorBox(message: _error!),
              if (_manualCorrectionSuggested) ...[
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed: () {
                    _textCtrl.clear();
                    _setMode(_ReportInputMode.text);
                  },
                  icon: const Icon(Icons.edit_note_outlined),
                  label: const Text('Metni elle ekle ve düzelt'),
                ),
              ],
            ],
            if (_result != null) ...[
              const SizedBox(height: 32),
              ..._buildResults(_result!),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildResults(ReportParseResponse response) {
    if (response.results.isEmpty) {
      return [
        const _EmptyResults(),
        const SizedBox(height: AppSpacing.lg),
        DisclaimerBox(text: response.disclaimer),
      ];
    }
    final categories = <String>{
      for (final result in response.results) _categoryFor(result.labTest),
    };
    return [
      Row(
        children: [
          Expanded(
            child: Text(
              'Bulunan tahliller',
              style: AppTextStyles.sectionTitle(context),
            ),
          ),
          Text(
            '${response.results.length} sonuç',
            style: AppTextStyles.caption(context),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.md),
      Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (final category in categories)
            Chip(
              avatar: const Icon(Icons.category_outlined, size: 17),
              label: Text(category),
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.md),
      for (final result in response.results) ...[
        _ExpandableResult(
          result: result,
          onLoadExplanation: () => _loadResultExplanation(result),
          onExplain: () => _explainResult(result),
          onCompare: () => _compareResult(result),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
      if (widget.onAskAssistant != null) ...[
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          onPressed: () => _askAssistant(response),
          icon: const Icon(Icons.forum_outlined),
          label: const Text('Bu raporu Asistana sor'),
        ),
      ],
      const SizedBox(height: AppSpacing.md),
      DisclaimerBox(text: response.disclaimer),
    ];
  }
}

String _categoryFor(String labTest) {
  final value = labTest.toLowerCase();
  if (RegExp(
    r'hemoglobin|hematokrit|eritrosit|lökosit|trombosit|mcv|mch|rdw',
  ).hasMatch(value)) {
    return 'Hemogram';
  }
  if (RegExp(r'alt|ast|bilirubin|ggt|alp|albumin').hasMatch(value)) {
    return 'Karaciğer';
  }
  if (RegExp(r'kreatinin|üre|egfr|ürik asit').hasMatch(value)) {
    return 'Böbrek';
  }
  if (RegExp(r'tsh|t3|t4|kortizol|insülin|hormon').hasMatch(value)) {
    return 'Hormon';
  }
  if (RegExp(r'crp|sedim|prokalsitonin').hasMatch(value)) {
    return 'Enflamasyon';
  }
  if (RegExp(r'ferritin|demir|b12|folat|d vitamini').hasMatch(value)) {
    return 'Vitamin ve mineraller';
  }
  if (RegExp(r'glukoz|hba1c|kolesterol|trigliserid|hdl|ldl').hasMatch(value)) {
    return 'Metabolizma';
  }
  return 'Diğer';
}

class _PdfInput extends StatelessWidget {
  const _PdfInput({
    required this.fileName,
    required this.fileSize,
    required this.loading,
    required this.onPick,
    required this.onParse,
  });

  final String? fileName;
  final int? fileSize;
  final bool loading;
  final VoidCallback onPick;
  final VoidCallback onParse;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = fileName != null;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            selected ? Icons.task_outlined : Icons.upload_file_outlined,
            size: 34,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            selected ? fileName! : 'PDF laboratuvar raporu seç',
            textAlign: TextAlign.center,
            style: AppTextStyles.sectionTitle(context),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            selected
                ? '${(fileSize! / 1024).toStringAsFixed(1)} KB'
                : 'En fazla 10 MB. Metin içeren PDF dosyaları desteklenir.',
            textAlign: TextAlign.center,
            style: AppTextStyles.caption(context),
          ),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton.icon(
            onPressed: loading ? null : onPick,
            icon: const Icon(Icons.folder_open_outlined),
            label: Text(selected ? 'Başka PDF seç' : 'PDF seç'),
          ),
          if (selected) ...[
            const SizedBox(height: AppSpacing.md),
            SanaPrimaryButton(
              label: 'PDF raporunu tara',
              icon: Icons.manage_search_outlined,
              loading: loading,
              onPressed: onParse,
            ),
          ],
        ],
      ),
    );
  }
}

class _TextInput extends StatelessWidget {
  const _TextInput({
    required this.controller,
    required this.loading,
    required this.onLoadSample,
    required this.onParse,
  });

  final TextEditingController controller;
  final bool loading;
  final VoidCallback onLoadSample;
  final VoidCallback onParse;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          minLines: 6,
          maxLines: 12,
          decoration: const InputDecoration(
            labelText: 'Rapor metni',
            hintText: 'Her satıra bir test: "CRP: 13.5 mg/L"',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: loading ? null : onLoadSample,
            icon: const Icon(Icons.notes_outlined, size: 18),
            label: const Text('Örnek metin ekle'),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SanaPrimaryButton(
          label: 'Metni tara',
          icon: Icons.manage_search_outlined,
          loading: loading,
          onPressed: onParse,
        ),
      ],
    );
  }
}

class _ExpandableResult extends StatefulWidget {
  const _ExpandableResult({
    required this.result,
    required this.onLoadExplanation,
    required this.onExplain,
    required this.onCompare,
  });

  final ParsedLabResult result;
  final Future<ExplainResponse> Function() onLoadExplanation;
  final VoidCallback onExplain;
  final VoidCallback onCompare;

  @override
  State<_ExpandableResult> createState() => _ExpandableResultState();
}

class _ExpandableResultState extends State<_ExpandableResult> {
  Future<ExplainResponse>? _explanation;

  void _loadExplanation() {
    final explanation = widget.onLoadExplanation();
    setState(() {
      _explanation = explanation;
    });
  }

  void _onExpansionChanged(bool expanded) {
    if (expanded && _explanation == null) _loadExplanation();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final result = widget.result;
    final value = [
      if (result.rawValue != null) result.rawValue!,
      if (result.unit != null) result.unit!,
    ].join(' ');
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: ValueKey('parsed-result-${result.labTest}'),
        onExpansionChanged: _onExpansionChanged,
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(AppSpacing.radius),
          ),
          child: Icon(
            Icons.water_drop_outlined,
            color: scheme.onPrimaryContainer,
            size: 21,
          ),
        ),
        title: Text(result.labTest, style: AppTextStyles.sectionTitle(context)),
        // Ölçülen değer tabular rakamlarla; birim daha sessiz. Durum çipi
        // kırmızı kullanmadan aralık ilişkisini gösterir.
        subtitle: value.isEmpty
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 20,
                        height: 1.1,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.02 * 20,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: scheme.onSurface,
                      ),
                    ),
                    SanaStatusChip(status: _statusOf(result.interpretation)),
                  ],
                ),
              ),
        children: [
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailRow(label: 'Tahlil', value: result.labTest),
                if (result.matchedTerm != null)
                  _DetailRow(
                    label: 'Eşleşen ifade',
                    value: result.matchedTerm!,
                  ),
                if (result.rawValue != null)
                  _DetailRow(label: 'Ölçülen değer', value: value),
                if (result.referenceRange != null)
                  _DetailRow(
                    label: 'Rapor referans aralığı',
                    value: result.referenceRange!,
                  ),
                if (result.interpretation != null)
                  _DetailRow(
                    label: 'Aralığa göre durum',
                    value: _interpretationLabel(result.interpretation!),
                  ),
                const SizedBox(height: AppSpacing.sm),
                FutureBuilder<ExplainResponse>(
                  future: _explanation,
                  builder: (context, snapshot) => _InlineExplanation(
                    snapshot: snapshot,
                    onRetry: _loadExplanation,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: widget.onExplain,
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Ayrıntılı açıklamayı aç'),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    key: ValueKey('compare-${result.labTest}'),
                    onPressed: result.value == null ? null : widget.onCompare,
                    icon: const Icon(Icons.show_chart_rounded),
                    label: const Text('Diğer raporlarla karşılaştır'),
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

/// Raporun değer/referans metninden gelen durum bayrakları.
///
/// Bunlar sorunun amacı değil, ham rapor verisidir. Backend bölüm tespitinde
/// "yüksek/düşük" kelimelerini kullandığı için soruya sızdıklarında tanım
/// sorusu yüksek/düşük yorumuna kayıyor ve terim hiç açıklanmıyordu.
final RegExp _statusFlagPattern = RegExp(
  r'\b(yüksek|yuksek|düşük|dusuk|high|low|normal)\b',
  caseSensitive: false,
);

String _withoutStatusFlags(String value) => value
    .replaceAll(_statusFlagPattern, ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String _resultExplanationQuestion(ParsedLabResult result) {
  final rawValue = result.rawValue == null
      ? null
      : _withoutStatusFlags(result.rawValue!);
  final reference = result.referenceRange == null
      ? null
      : _withoutStatusFlags(result.referenceRange!);

  return <String>[
    result.labTest,
    if (rawValue != null && rawValue.isNotEmpty) rawValue,
    if (result.unit != null) result.unit!,
    'çıktı.',
    if (reference != null && reference.isNotEmpty)
      'Rapor referans aralığı: $reference.',
    'Bu tahlil nedir, neyi ölçer ve neden ölçülür? '
        'Sonucu yalnızca genel bilgi olarak açıkla.',
  ].join(' ');
}

/// Backend'in `interpretation` alanını görsel duruma çevirir.
/// Değer yoksa "aralık verilmemiş" olur; uydurma sınıflandırma yapılmaz.
SanaStatus _statusOf(String? interpretation) => switch (interpretation) {
  'normal' => SanaStatus.inRange,
  'high' => SanaStatus.above,
  'low' => SanaStatus.below,
  _ => SanaStatus.unknown,
};

String _interpretationLabel(String interpretation) {
  return switch (interpretation) {
    'low' => 'Düşük',
    'normal' => 'Aralık içinde',
    'high' => 'Yüksek',
    _ => 'Belirsiz',
  };
}

class _InlineExplanation extends StatelessWidget {
  const _InlineExplanation({required this.snapshot, required this.onRetry});

  final AsyncSnapshot<ExplainResponse> snapshot;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: AppSpacing.md),
            Expanded(child: Text('Açıklama hazırlanıyor...')),
          ],
        ),
      );
    }
    if (snapshot.hasError) {
      final error = snapshot.error;
      final message = error is SanaApiException
          ? error.message
          : 'Açıklama yüklenemedi.';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ErrorBox(message: message),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Yeniden dene'),
          ),
        ],
      );
    }
    final response = snapshot.data;
    if (response == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Açıklama', style: AppTextStyles.sectionTitle(context)),
        const SizedBox(height: AppSpacing.sm),
        Text(
          response.answer,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
        ),
        if (response.citations.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final citation in response.citations)
                Chip(
                  avatar: const Icon(Icons.link, size: 17),
                  label: Text(citation.sourceTitle),
                ),
            ],
          ),
        ],
        if (response.disclaimer.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          DisclaimerBox(text: response.disclaimer),
        ],
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(label, style: AppTextStyles.caption(context)),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: Theme.of(context).colorScheme.onPrimaryContainer),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Desteklenen tahlil sonucu bulunamadı. PDF metin içeriyorsa rapordaki test adlarını Tahlil Sözlüğü ile karşılaştırabilirsin.',
              style: AppTextStyles.caption(context),
            ),
          ),
        ],
      ),
    );
  }
}
