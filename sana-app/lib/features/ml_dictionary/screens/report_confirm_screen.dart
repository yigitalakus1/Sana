// Ayrıştırılan değerlerin kullanıcı tarafından düzeltilip onaylandığı ekran.
//
// Buradaki kural tek cümle: **kullanıcı onaylamadan hiçbir şey rapor geçmişine
// yazılmaz.** Ayrıştırma bir öneridir; hangi değerin doğru olduğuna kullanıcı
// karar verir. Yanlış tanınan satır silinebilir, eksik kalan alan
// düzeltilebilir, tanınmayan bir tahlil sözlükten seçilebilir.
//
// Sınıflandırma (normal/yüksek/düşük) yalnız raporun kendi referans aralığı
// varsa hesaplanır ve kullanıcı aralığı değiştirdiğinde yeniden hesaplanır;
// aralık yoksa boş kalır — uydurulmaz.

import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../models/report_parse_models.dart';
import '../models/term_models.dart';
import '../services/local_report_parser.dart';
import '../services/ml_dictionary_service.dart';
import '../widgets/common_widgets.dart';
import '../widgets/status_chip.dart';

class ReportConfirmScreen extends StatefulWidget {
  const ReportConfirmScreen({
    super.key,
    required this.results,
    required this.sourceName,
    this.reportDate,
    this.disclaimer,
    this.service,
    this.unmatchedLines = const [],
  });

  final List<ParsedLabResult> results;

  /// Ölçüm gibi görünüp eşleşmeyen satırlar; sessizce yutulmaz.
  final List<String> unmatchedLines;
  final String sourceName;
  final DateTime? reportDate;
  final String? disclaimer;
  final MlDictionaryService? service;

  @override
  State<ReportConfirmScreen> createState() => _ReportConfirmScreenState();
}

class _ReportConfirmScreenState extends State<ReportConfirmScreen> {
  late final MlDictionaryService _service =
      widget.service ?? MlDictionaryService();
  late final List<ParsedLabResult> _rows = List<ParsedLabResult>.of(
    widget.results,
  );

  /// Aynı tahlilden birden çok ölçüm varsa kullanıcıya açıkça belirtilir;
  /// hiçbiri sessizce elenmez.
  Set<String> get _duplicatedLabs {
    final counts = <String, int>{};
    for (final row in _rows) {
      counts[row.labTest] = (counts[row.labTest] ?? 0) + 1;
    }
    return counts.entries
        .where((entry) => entry.value > 1)
        .map((entry) => entry.key)
        .toSet();
  }

  void _delete(int index) {
    final removed = _rows[index];
    setState(() => _rows.removeAt(index));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${removed.labTest} çıkarıldı.'),
          action: SnackBarAction(
            label: 'Geri al',
            onPressed: () => setState(() => _rows.insert(index, removed)),
          ),
        ),
      );
  }

  Future<void> _edit(int index) async {
    final edited = await showDialog<ParsedLabResult>(
      context: context,
      builder: (_) => _EditValueDialog(result: _rows[index]),
    );
    if (edited != null && mounted) {
      setState(() => _rows[index] = edited);
    }
  }

  /// Tanınmayan bir tahlili sözlükten seçerek ekler.
  Future<void> _addFromDictionary() async {
    final List<TermSummary> terms;
    try {
      terms = await _service.getTerms();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Sözlük açılamadı.')));
      return;
    }
    if (!mounted) return;

    final picked = await showDialog<TermSummary>(
      context: context,
      builder: (_) => _LabPickerDialog(terms: terms),
    );
    if (picked == null || !mounted) return;

    final created = await showDialog<ParsedLabResult>(
      context: context,
      builder: (_) => _EditValueDialog(
        result: ParsedLabResult(labTest: picked.labTest),
        title: 'Değer ekle',
      ),
    );
    if (created != null && mounted) {
      setState(() => _rows.add(created));
    }
  }

  void _confirm() => Navigator.of(context).pop(List<ParsedLabResult>.of(_rows));

  /// Tanınmayan satırların uyarı metni. Uzun raporlarda kutu şişmesin diye
  /// en fazla sekiz satır gösterilir, kalanı sayıyla belirtilir.
  static String _unmatchedMessage(List<String> lines) {
    const shown = 8;
    final preview = lines.take(shown).join('\n');
    final rest = lines.length - shown;
    return 'Aşağıdaki satırlar ölçüm gibi görünüyor ama hiçbir tahlile '
        'bağlanamadı. Sessizce atlanmadılar; doğruysa "Değer ekle" ile '
        'sözlükten seçip elle girebilirsin.\n\n'
        '$preview'
        '${rest > 0 ? '\n… ve $rest satır daha' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final duplicates = _duplicatedLabs;

    return Scaffold(
      appBar: AppBar(title: const Text('Değerleri kontrol et')),
      body: ResponsiveCenter(
        child: ListView(
          padding: AppSpacing.pagePadding(
            MediaQuery.sizeOf(context).width,
          ).copyWith(bottom: 32),
          children: [
            const DisclaimerBox(
              title: 'Kaydetmeden önce kontrol et',
              text:
                  'Bu değerler rapordan otomatik okundu ve yanlış olabilir. '
                  'Düzeltip onayladığında geçmişe kaydedilir. Veriler bu '
                  'cihazda işlenir.',
            ),
            if (duplicates.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              DisclaimerBox.attention(
                title: 'Aynı tahlil birden çok kez var',
                text:
                    '${duplicates.join(', ')} raporda birden fazla ölçümle '
                    'geçiyor. Hiçbiri silinmedi; hangisini saklayacağına sen '
                    'karar ver.',
              ),
            ],
            if (widget.unmatchedLines.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              DisclaimerBox.attention(
                title: 'Bu satırlar tanınamadı',
                text: _unmatchedMessage(widget.unmatchedLines),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_rows.length} değer',
                    style: AppTextStyles.sectionTitle(context),
                  ),
                ),
                TextButton.icon(
                  onPressed: _addFromDictionary,
                  icon: const Icon(Icons.add),
                  label: const Text('Değer ekle'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_rows.isEmpty)
              const SanaStateCard(
                icon: Icons.playlist_remove_outlined,
                title: 'Kaydedilecek değer kalmadı',
                message:
                    'Tüm satırları çıkardın. Sözlükten değer ekleyebilir veya '
                    'vazgeçip geri dönebilirsin.',
              )
            else
              for (var index = 0; index < _rows.length; index++) ...[
                _EditableResultCard(
                  result: _rows[index],
                  duplicated: duplicates.contains(_rows[index].labTest),
                  onEdit: () => _edit(index),
                  onDelete: () => _delete(index),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: _rows.isEmpty ? null : _confirm,
              icon: const Icon(Icons.check),
              label: const Text('Onayla ve geçmişe kaydet'),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Vazgeç, kaydetme'),
            ),
            if (widget.disclaimer != null) ...[
              const SizedBox(height: AppSpacing.lg),
              DisclaimerBox(text: widget.disclaimer!),
            ],
          ],
        ),
      ),
    );
  }
}

class _EditableResultCard extends StatelessWidget {
  const _EditableResultCard({
    required this.result,
    required this.duplicated,
    required this.onEdit,
    required this.onDelete,
  });

  final ParsedLabResult result;
  final bool duplicated;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final measured = [
      if (result.rawValue != null) result.rawValue!,
      if (result.unit != null) result.unit!,
    ].join(' ');

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: scheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.labTest,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (result.matchedTerm != null &&
                        result.matchedTerm!.isNotEmpty)
                      Text(
                        'Raporda: ${result.matchedTerm}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              SanaStatusChip(status: _statusOf(result.interpretation)),
            ],
          ),
          if (duplicated) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Bu tahlil raporda birden çok kez geçiyor.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.tertiary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          _Field(label: 'Ölçülen değer', value: measured.isEmpty ? '—' : measured),
          _Field(
            label: 'Referans aralığı',
            value: result.referenceRange ?? 'Raporda yok',
          ),
          _Field(
            label: 'Aralığa göre durum',
            value: _interpretationLabel(result.interpretation),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Düzelt'),
              ),
              const SizedBox(width: AppSpacing.sm),
              TextButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Çıkar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// Tek bir değeri düzenler.
///
/// Denetleyiciler diyaloğun kendi state'inde tutulur: dışarıda tutulup
/// `await showDialog` sonrası dispose edilirse kapanma animasyonu sürerken
/// kullanılmış olur ve uygulama çöker.
class _EditValueDialog extends StatefulWidget {
  const _EditValueDialog({required this.result, this.title});

  final ParsedLabResult result;
  final String? title;

  @override
  State<_EditValueDialog> createState() => _EditValueDialogState();
}

class _EditValueDialogState extends State<_EditValueDialog> {
  late final TextEditingController _value = TextEditingController(
    text: widget.result.rawValue ?? '',
  );
  late final TextEditingController _unit = TextEditingController(
    text: widget.result.unit ?? '',
  );
  late final TextEditingController _range = TextEditingController(
    text: widget.result.referenceRange ?? '',
  );
  String? _valueError;

  @override
  void dispose() {
    _value.dispose();
    _unit.dispose();
    _range.dispose();
    super.dispose();
  }

  void _submit() {
    final rawValue = _value.text.trim();
    final parsed = rawValue.isEmpty
        ? null
        : double.tryParse(rawValue.replaceAll(',', '.'));
    if (rawValue.isNotEmpty && parsed == null) {
      setState(() => _valueError = 'Sayı olarak yazın (örn. 13.5).');
      return;
    }

    final range = _range.text.trim();
    final unit = _unit.text.trim();

    Navigator.of(context).pop(
      ParsedLabResult(
        labTest: widget.result.labTest,
        matchedTerm: widget.result.matchedTerm,
        rawValue: rawValue.isEmpty ? null : rawValue,
        value: parsed,
        unit: unit.isEmpty ? null : unit,
        referenceRange: range.isEmpty ? null : range,
        // Aralık yoksa sınıflandırma yapılmaz; varsa parser ile aynı kural.
        interpretation: (parsed == null || range.isEmpty)
            ? null
            : LocalReportParser.classifyValue(parsed, range),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title ?? widget.result.labTest),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _value,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: InputDecoration(
                labelText: 'Ölçülen değer',
                errorText: _valueError,
              ),
              onChanged: (_) {
                if (_valueError != null) setState(() => _valueError = null);
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _unit,
              decoration: const InputDecoration(
                labelText: 'Birim',
                hintText: 'mg/L',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _range,
              decoration: const InputDecoration(
                labelText: 'Referans aralığı',
                hintText: '0 - 5',
                helperText: 'Boş bırakırsan durum hesaplanmaz.',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Kaydet')),
      ],
    );
  }
}

/// Sözlükten tahlil seçtirir; tanınmayan satırlar için.
class _LabPickerDialog extends StatefulWidget {
  const _LabPickerDialog({required this.terms});

  final List<TermSummary> terms;

  @override
  State<_LabPickerDialog> createState() => _LabPickerDialogState();
}

class _LabPickerDialogState extends State<_LabPickerDialog> {
  late final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Türkçe'de `I`/`İ` ayrımı standart `toLowerCase` ile bozulur.
  static String _fold(String value) =>
      value.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();

  @override
  Widget build(BuildContext context) {
    final needle = _fold(_query.trim());
    final matches = needle.isEmpty
        ? widget.terms
        : widget.terms
              .where(
                (term) =>
                    _fold(term.labTest).contains(needle) ||
                    _fold(term.title ?? '').contains(needle),
              )
              .toList();

    return AlertDialog(
      title: const Text('Tahlil seç'),
      contentPadding: const EdgeInsets.only(top: AppSpacing.sm),
      content: SizedBox(
        width: 360,
        height: 420,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: TextField(
                controller: _search,
                decoration: const InputDecoration(
                  labelText: 'Ara',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: matches.isEmpty
                  ? const Center(child: Text('Eşleşen tahlil bulunamadı.'))
                  : ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (context, index) {
                        final term = matches[index];
                        return ListTile(
                          title: Text(term.labTest),
                          subtitle: term.title == null || term.title!.isEmpty
                              ? null
                              : Text(term.title!),
                          onTap: () => Navigator.of(context).pop(term),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
      ],
    );
  }
}

SanaStatus _statusOf(String? interpretation) => switch (interpretation) {
  'normal' => SanaStatus.inRange,
  'high' => SanaStatus.above,
  'low' => SanaStatus.below,
  _ => SanaStatus.unknown,
};

String _interpretationLabel(String? interpretation) => switch (interpretation) {
  'low' => 'Düşük',
  'normal' => 'Aralık içinde',
  'high' => 'Yüksek',
  _ => 'Aralık verilmemiş',
};
