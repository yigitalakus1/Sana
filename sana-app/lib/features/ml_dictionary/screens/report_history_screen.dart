import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../models/report_parse_models.dart';
import '../services/report_history_service.dart';
import '../widgets/common_widgets.dart';

class ReportHistoryScreen extends StatefulWidget {
  const ReportHistoryScreen({super.key, this.service, this.initialLabTest});

  final ReportHistoryService? service;
  final String? initialLabTest;

  @override
  State<ReportHistoryScreen> createState() => _ReportHistoryScreenState();
}

class _ReportHistoryScreenState extends State<ReportHistoryScreen> {
  late final ReportHistoryService _service =
      widget.service ?? ReportHistoryService();
  List<ReportHistoryEntry> _entries = const [];
  final Set<String> _selectedIds = <String>{};
  bool _loading = true;
  String? _selectedLab;
  bool _initialLabApplied = false;

  List<ReportHistoryEntry> get _selectedEntries =>
      _entries.where((entry) => _selectedIds.contains(entry.id)).toList()..sort(
        (left, right) => _effectiveDate(left).compareTo(_effectiveDate(right)),
      );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    List<ReportHistoryEntry> entries;
    try {
      entries = await _service.load();
    } catch (_) {
      entries = <ReportHistoryEntry>[];
    }
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
      final availableIds = entries.map((entry) => entry.id).toSet();
      _selectedIds.removeWhere((id) => !availableIds.contains(id));
      final requestedLab = widget.initialLabTest?.trim();
      if (!_initialLabApplied &&
          requestedLab != null &&
          requestedLab.isNotEmpty) {
        _initialLabApplied = true;
        final matchingEntries = entries.where(
          (entry) => entry.results.any(
            (result) =>
                result.value != null &&
                result.labTest.toLowerCase() == requestedLab.toLowerCase(),
          ),
        );
        _selectedIds
          ..clear()
          ..addAll(matchingEntries.map((entry) => entry.id));
        _selectedLab = entries
            .expand((entry) => entry.results)
            .where(
              (result) =>
                  result.labTest.toLowerCase() == requestedLab.toLowerCase(),
            )
            .map((result) => result.labTest)
            .firstOrNull;
      } else if (_selectedIds.isEmpty) {
        _selectedIds.addAll(entries.take(2).map((entry) => entry.id));
      }
      _syncSelectedLab();
    });
  }

  List<String> _comparableLabs(List<ReportHistoryEntry> entries) {
    final counts = <String, int>{};
    for (final entry in entries) {
      final labsInReport = <String>{
        for (final result in entry.results)
          if (result.value != null) result.labTest,
      };
      for (final lab in labsInReport) {
        counts[lab] = (counts[lab] ?? 0) + 1;
      }
    }
    return counts.entries
        .where((entry) => entry.value >= 2)
        .map((entry) => entry.key)
        .toList()
      ..sort();
  }

  void _syncSelectedLab() {
    final labs = _comparableLabs(_selectedEntries);
    if (_selectedLab == null || !labs.contains(_selectedLab)) {
      _selectedLab = labs.isEmpty ? null : labs.first;
    }
  }

  void _toggleSelection(ReportHistoryEntry entry, bool selected) {
    setState(() {
      selected ? _selectedIds.add(entry.id) : _selectedIds.remove(entry.id);
      _syncSelectedLab();
    });
  }

  /// Rapora kullanıcının kendi adını/notunu verir. Boş bırakılırsa etiket
  /// kaldırılır ve rapor yeniden dosya adıyla görünür.
  Future<void> _editLabel(ReportHistoryEntry entry) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _LabelDialog(entry: entry),
    );
    if (result == null) return;
    await _service.updateLabel(entry.id, result);
    await _load();
  }

  Future<void> _delete(ReportHistoryEntry entry) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rapor silinsin mi?'),
        content: Text(
          '${entry.sourceName} bu cihazdaki rapor geçmişinden kalıcı olarak silinecek.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Sil'),
          ),
        ],
      ),
    );
    if (approved != true) return;
    _selectedIds.remove(entry.id);
    await _service.delete(entry.id);
    await _load();
  }

  Future<void> _clear() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rapor geçmişi silinsin mi?'),
        content: const Text(
          'Bu cihazda saklanan rapor geçmişi kalıcı olarak silinir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Geçmişi sil'),
          ),
        ],
      ),
    );
    if (approved != true) return;
    _selectedIds.clear();
    await _service.clear();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rapor Geçmişi'),
        actions: [
          if (_entries.isNotEmpty)
            IconButton(
              tooltip: 'Tüm geçmişi sil',
              onPressed: _clear,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
      ),
      body: ResponsiveCenter(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _entries.isEmpty
            ? const _EmptyHistory()
            : ListView(
                padding: AppSpacing.pagePadding(
                  MediaQuery.sizeOf(context).width,
                ).copyWith(bottom: 32),
                children: [
                  const _LocalDataNotice(),
                  const SizedBox(height: AppSpacing.lg),
                  _ComparisonPanel(
                    entries: _selectedEntries,
                    selectedLab: _selectedLab,
                    labs: _comparableLabs(_selectedEntries),
                    onLabChanged: (value) =>
                        setState(() => _selectedLab = value),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Kıyaslanacak raporları seç',
                          style: AppTextStyles.sectionTitle(context),
                        ),
                      ),
                      Text(
                        '${_selectedIds.length}/${_entries.length} seçili',
                        style: AppTextStyles.caption(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Raporu genişletmek için kartın gövdesine dokunabilirsin.',
                    style: AppTextStyles.caption(context),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  for (final entry in _entries) ...[
                    _HistoryCard(
                      entry: entry,
                      selected: _selectedIds.contains(entry.id),
                      onSelected: (value) => _toggleSelection(entry, value),
                      onEditLabel: () => _editLabel(entry),
                      onDelete: () => _delete(entry),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ],
              ),
      ),
    );
  }
}

class _ComparisonPanel extends StatelessWidget {
  const _ComparisonPanel({
    required this.entries,
    required this.selectedLab,
    required this.labs,
    required this.onLabChanged,
  });

  final List<ReportHistoryEntry> entries;
  final String? selectedLab;
  final List<String> labs;
  final ValueChanged<String> onLabChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final series = selectedLab == null
        ? const _TrendSeries.empty()
        : _seriesFor(entries, selectedLab!);
    final points = series.points;
    final unit = series.unit;

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
          _ComparisonHeader(
            selectedCount: entries.length,
            selectedLab: selectedLab,
            labs: labs,
            onLabChanged: onLabChanged,
          ),
          const SizedBox(height: AppSpacing.lg),
          if (entries.length < 2)
            const _ComparisonMessage(
              icon: Icons.checklist_rounded,
              message: 'Kıyaslama için aşağıdan en az iki rapor seç.',
            )
          else if (labs.isEmpty)
            const _ComparisonMessage(
              icon: Icons.info_outline,
              message:
                  'Seçilen raporlarda kıyaslanabilecek ortak bir tahlil bulunamadı.',
            )
          else if (points.length < 2)
            const _ComparisonMessage(
              icon: Icons.info_outline,
              message: 'Bu tahlil için aynı birimde en az iki ölçüm gerekir.',
            )
          else ...[
            _TrendSummary(points: points, unit: unit),
            const SizedBox(height: AppSpacing.md),
            // Grafik yalnız çizim olduğu için ekran okuyucuya görünmez;
            // ölçümleri sözlü olarak da veriyoruz.
            Semantics(
              label: _chartSemanticsLabel(selectedLab, points, unit),
              image: true,
              child: ExcludeSemantics(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final height = constraints.maxWidth < 600 ? 280.0 : 310.0;
                    return RepaintBoundary(
                      child: Container(
                        height: height,
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(
                            alpha: 0.28,
                          ),
                          border: Border.all(
                            color: scheme.outlineVariant.withValues(alpha: 0.7),
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: CustomPaint(
                          painter: _TrendPainter(
                            points: points,
                            unit: unit,
                            lineColor: scheme.primary,
                            accentColor: scheme.tertiary,
                            gridColor: scheme.outlineVariant,
                            labelColor: scheme.onSurfaceVariant,
                            surfaceColor: scheme.surface,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (var index = 0; index < points.length; index++)
                  Chip(
                    avatar: Icon(
                      index == points.length - 1
                          ? Icons.radio_button_checked
                          : Icons.circle_outlined,
                      size: 16,
                      color: index == points.length - 1
                          ? scheme.tertiary
                          : scheme.primary,
                    ),
                    label: Text(
                      '${_shortDate(points[index].date)} · ${_formatValue(points[index].value)}${unit == null ? '' : ' $unit'}',
                    ),
                  ),
              ],
            ),
          ],
          if (series.hasUnitMismatch) ...[
            const SizedBox(height: AppSpacing.md),
            _UnitMismatchNotice(
              chartUnit: unit,
              skippedUnits: series.skippedUnits,
            ),
          ],
        ],
      ),
    );
  }
}

class _ComparisonHeader extends StatelessWidget {
  const _ComparisonHeader({
    required this.selectedCount,
    required this.selectedLab,
    required this.labs,
    required this.onLabChanged,
  });

  final int selectedCount;
  final String? selectedLab;
  final List<String> labs;
  final ValueChanged<String> onLabChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = Row(
      children: [
        Icon(Icons.compare_arrows_rounded, color: scheme.primary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Rapor karşılaştırma',
                style: AppTextStyles.sectionTitle(context),
              ),
              Text(
                '$selectedCount rapor seçili',
                style: AppTextStyles.caption(context),
              ),
            ],
          ),
        ),
      ],
    );
    final selector = DropdownButton<String>(
      value: selectedLab,
      isExpanded: true,
      items: [
        for (final lab in labs)
          DropdownMenuItem(
            value: lab,
            child: Text(lab, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (value) {
        if (value != null) onLabChanged(value);
      },
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              if (labs.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                selector,
              ],
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: title),
            if (labs.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.lg),
              SizedBox(width: 260, child: selector),
            ],
          ],
        );
      },
    );
  }
}

class _TrendSummary extends StatelessWidget {
  const _TrendSummary({required this.points, required this.unit});

  final List<_TrendPoint> points;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final first = points.first.value;
    final latest = points.last.value;
    final delta = latest - first;
    final minimum = points.map((point) => point.value).reduce(math.min);
    final maximum = points.map((point) => point.value).reduce(math.max);
    final suffix = unit == null || unit!.trim().isEmpty ? '' : ' $unit';
    final deltaPrefix = delta > 0 ? '+' : '';
    final deltaIcon = delta > 0
        ? Icons.trending_up_rounded
        : delta < 0
        ? Icons.trending_down_rounded
        : Icons.trending_flat_rounded;

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720
            ? 3
            : constraints.maxWidth >= 420
            ? 2
            : 1;
        final itemWidth =
            (constraints.maxWidth - AppSpacing.sm * (columns - 1)) / columns;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            SizedBox(
              width: itemWidth,
              child: _TrendMetric(
                icon: Icons.schedule_rounded,
                label: 'Son ölçüm',
                value: '${_formatValue(latest)}$suffix',
                detail: _shortDate(points.last.date),
                color: scheme.tertiary,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _TrendMetric(
                icon: deltaIcon,
                label: 'Değişim',
                value: '$deltaPrefix${_formatValue(delta)}$suffix',
                detail: 'İlk ölçüme göre',
                color: scheme.primary,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _TrendMetric(
                icon: Icons.height_rounded,
                label: 'Aralık',
                value:
                    '${_formatValue(minimum)}–${_formatValue(maximum)}$suffix',
                detail: '${points.length} ölçüm',
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TrendMetric extends StatelessWidget {
  const _TrendMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTextStyles.caption(context)),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.sectionTitle(context),
                ),
                Text(detail, style: AppTextStyles.caption(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Farklı birimdeki ölçümlerin grafiğe alınmadığını açıkça söyler.
///
/// Tıbbi birim dönüşümü **tahmin edilmez**; yanlış bir dönüşüm yanlış bir
/// sağlık izlenimi yaratacağı için ölçümler sessizce birleştirilmez.
class _UnitMismatchNotice extends StatelessWidget {
  const _UnitMismatchNotice({
    required this.chartUnit,
    required this.skippedUnits,
  });

  final String? chartUnit;
  final Set<String> skippedUnits;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final skipped = skippedUnits.join(', ');
    final shown = (chartUnit == null || chartUnit!.trim().isEmpty)
        ? 'birimsiz'
        : chartUnit!;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.straighten_outlined,
            size: 19,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Bazı ölçümler farklı birimde ($skipped) olduğu için grafiğe '
              'alınmadı; grafik $shown birimindeki ölçümleri gösteriyor. '
              'Birim dönüşümü tahmin edilmez.',
              style: AppTextStyles.caption(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _ComparisonMessage extends StatelessWidget {
  const _ComparisonMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(message, style: AppTextStyles.muted(context))),
      ],
    );
  }
}

/// Grafiğin ekran okuyucu karşılığı: tahlil adı ve tüm ölçümler sözel olarak.
String _chartSemanticsLabel(
  String? labTest,
  List<_TrendPoint> points,
  String? unit,
) {
  final suffix = (unit == null || unit.trim().isEmpty) ? '' : ' $unit';
  final readings = points
      .map(
        (point) =>
            '${_shortDate(point.date)} ${_formatValue(point.value)}$suffix',
      )
      .join(', ');
  return '${labTest ?? 'Tahlil'} değişim grafiği. ${points.length} ölçüm: $readings.';
}

/// Bir tahlilin grafiğe girebilen ölçümleri ve birim uyuşmazlığı bilgisi.
class _TrendSeries {
  const _TrendSeries({required this.points, required this.skippedUnits});

  const _TrendSeries.empty() : points = const [], skippedUnits = const {};

  final List<_TrendPoint> points;

  /// Farklı birimde olduğu için grafiğe ALINMAYAN ölçümlerin birimleri.
  final Set<String> skippedUnits;

  bool get hasUnitMismatch => skippedUnits.isNotEmpty;
  String? get unit => points.isEmpty ? null : points.first.unit;
}

/// Seçili raporlardan tek bir tahlilin serisini kurar.
///
/// Yalnız ilk görülen birimle aynı olan ölçümler grafiğe girer. Farklı
/// birimdeki ölçümler **dönüştürülmez** (tıbbi birim dönüşümü tahmin
/// edilmez); atlandıkları kullanıcıya ayrıca bildirilir.
_TrendSeries _seriesFor(List<ReportHistoryEntry> entries, String labTest) {
  final points = <_TrendPoint>[];
  final skippedUnits = <String>{};
  String? unit;
  for (final entry in entries) {
    String? mismatched;
    var added = false;
    for (final result in entry.results) {
      if (result.labTest != labTest || result.value == null) continue;
      unit ??= result.unit;
      if (result.unit != unit) {
        mismatched ??= (result.unit == null || result.unit!.trim().isEmpty)
            ? 'birimsiz'
            : result.unit!;
        continue;
      }
      points.add(
        _TrendPoint(
          date: _effectiveDate(entry),
          value: result.value!,
          unit: result.unit,
        ),
      );
      added = true;
      break;
    }
    if (!added && mismatched != null) skippedUnits.add(mismatched);
  }
  points.sort((left, right) => left.date.compareTo(right.date));
  return _TrendSeries(points: points, skippedUnits: skippedUnits);
}

/// Grafik ve kart etiketlerinde kullanılan tarih.
///
/// Öncelik: rapor içeriğinden çıkarılan etiketli tarih → dosya adındaki
/// GG.AA.YYYY → kayıt zamanı.
DateTime _effectiveDate(ReportHistoryEntry entry) {
  final fromReport = entry.reportDate;
  if (fromReport != null) return fromReport;

  final dayFirst = RegExp(
    r'(\d{2})[._-](\d{2})[._-](\d{4})',
  ).firstMatch(entry.sourceName);
  if (dayFirst != null) {
    final day = int.parse(dayFirst.group(1)!);
    final month = int.parse(dayFirst.group(2)!);
    final year = int.parse(dayFirst.group(3)!);
    final parsed = DateTime.tryParse(
      '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
    );
    if (parsed != null) return parsed;
  }
  return entry.createdAt;
}

String _shortDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year.toString().substring(2)}';

String _formatValue(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

class _TrendPoint {
  const _TrendPoint({required this.date, required this.value, this.unit});

  final DateTime date;
  final double value;
  final String? unit;
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter({
    required this.points,
    required this.unit,
    required this.lineColor,
    required this.accentColor,
    required this.gridColor,
    required this.labelColor,
    required this.surfaceColor,
  });

  final List<_TrendPoint> points;
  final String? unit;
  final Color lineColor;
  final Color accentColor;
  final Color gridColor;
  final Color labelColor;
  final Color surfaceColor;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 58.0;
    const right = 24.0;
    const top = 42.0;
    const bottom = 48.0;
    final chart = Rect.fromLTRB(
      left,
      top,
      size.width - right,
      size.height - bottom,
    );
    if (chart.width <= 0 || chart.height <= 0) return;

    final values = points.map((point) => point.value);
    final rawMin = values.reduce(math.min);
    final rawMax = values.reduce(math.max);
    final rawRange = rawMax - rawMin;
    final padding = rawRange == 0
        ? math.max(rawMax.abs() * 0.1, 1.0)
        : rawRange * 0.18;
    final minimum = rawMin - padding;
    final maximum = rawMax + padding;
    final range = maximum - minimum;

    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.65)
      ..strokeWidth = 1;
    for (var index = 0; index <= 4; index++) {
      final ratio = index / 4;
      final y = chart.bottom - chart.height * ratio;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
      _paintText(
        canvas,
        _formatValue(minimum + range * ratio),
        Offset(0, y - 8),
        labelColor,
        width: left - 8,
        align: TextAlign.right,
      );
    }
    if (unit != null && unit!.trim().isNotEmpty) {
      _paintText(
        canvas,
        unit!,
        const Offset(4, 8),
        labelColor,
        width: left - 10,
        bold: true,
      );
    }

    final offsets = <Offset>[];
    for (var index = 0; index < points.length; index++) {
      final x =
          chart.left + chart.width * index / math.max(1, points.length - 1);
      final normalized = (points[index].value - minimum) / range;
      offsets.add(Offset(x, chart.bottom - normalized * chart.height));
    }

    final linePath = _smoothPath(offsets);
    final area = Path.from(linePath)
      ..lineTo(offsets.last.dx, chart.bottom)
      ..lineTo(offsets.first.dx, chart.bottom)
      ..close();
    canvas.drawPath(area, Paint()..color = lineColor.withValues(alpha: 0.08));

    final line = Paint()
      ..color = lineColor
      ..strokeWidth = 2.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(
      linePath,
      Paint()
        ..color = lineColor.withValues(alpha: 0.12)
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
    canvas.drawPath(linePath, line);

    final labelIndexes = _labelIndexes(points.length);
    for (var index = 0; index < offsets.length; index++) {
      final offset = offsets[index];
      final isLatest = index == offsets.length - 1;
      if (isLatest) {
        canvas.drawCircle(
          offset,
          11,
          Paint()..color = accentColor.withValues(alpha: 0.16),
        );
      }
      canvas.drawCircle(
        offset,
        isLatest ? 7 : 5.5,
        Paint()..color = surfaceColor,
      );
      canvas.drawCircle(
        offset,
        isLatest ? 4.5 : 3.5,
        Paint()..color = isLatest ? accentColor : lineColor,
      );
      if (!labelIndexes.contains(index)) continue;
      _paintText(
        canvas,
        _formatValue(points[index].value),
        Offset(offset.dx - 30, offset.dy - 26),
        labelColor,
        width: 60,
        align: TextAlign.center,
        bold: true,
        textColor: isLatest ? accentColor : null,
      );
      _paintText(
        canvas,
        _shortDate(points[index].date),
        Offset(offset.dx - 38, chart.bottom + 12),
        labelColor,
        width: 76,
        align: TextAlign.center,
      );
    }
  }

  Path _smoothPath(List<Offset> offsets) {
    final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (var index = 1; index < offsets.length; index++) {
      final previous = offsets[index - 1];
      final current = offsets[index];
      final middleX = (previous.dx + current.dx) / 2;
      path.cubicTo(
        middleX,
        previous.dy,
        middleX,
        current.dy,
        current.dx,
        current.dy,
      );
    }
    return path;
  }

  Set<int> _labelIndexes(int count) {
    if (count <= 6) return {for (var index = 0; index < count; index++) index};
    const maxLabels = 6;
    return {
      for (var index = 0; index < maxLabels; index++)
        (index * (count - 1) / (maxLabels - 1)).round(),
    };
  }

  void _paintText(
    Canvas canvas,
    String text,
    Offset offset,
    Color color, {
    required double width,
    TextAlign align = TextAlign.left,
    bool bold = false,
    Color? textColor,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: textColor ?? color,
          fontSize: 11,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: width);
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.unit != unit ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.accentColor != accentColor ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.labelColor != labelColor;
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.entry,
    required this.selected,
    required this.onSelected,
    required this.onEditLabel,
    required this.onDelete,
  });

  final ReportHistoryEntry entry;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final VoidCallback onEditLabel;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reportDate = _effectiveDate(entry);
    final label =
        '${reportDate.day.toString().padLeft(2, '0')}.${reportDate.month.toString().padLeft(2, '0')}.${reportDate.year}';
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 1.6 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Checkbox(
          key: ValueKey('select-${entry.id}'),
          value: selected,
          onChanged: (value) => onSelected(value ?? false),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                entry.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            IconButton(
              key: ValueKey('label-${entry.id}'),
              tooltip: 'Rapor adını düzenle',
              onPressed: onEditLabel,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton.filledTonal(
              key: ValueKey('delete-${entry.id}'),
              tooltip: 'Bu raporu sil',
              onPressed: onDelete,
              style: IconButton.styleFrom(
                backgroundColor: scheme.errorContainer,
                foregroundColor: scheme.onErrorContainer,
              ),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$label · ${entry.results.length} sonuç'),
            // Kullanıcı kendi adını verdiyse hangi dosyadan geldiği görünür kalır.
            if (entry.hasCustomLabel)
              Text(
                entry.sourceName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption(context),
              ),
          ],
        ),
        children: [
          for (final result in entry.results)
            ListTile(
              dense: true,
              title: Text(result.labTest),
              trailing: Text(
                [result.rawValue, result.unit]
                    .whereType<String>()
                    .where((value) => value.isNotEmpty)
                    .join(' '),
              ),
            ),
        ],
      ),
    );
  }
}

/// Rapor adı düzenleme penceresi.
///
/// Controller'ı kendisi sahiplenir ve kendisi kapatır; böylece pencere kapanma
/// animasyonu sürerken kullanılan bir controller'a dokunulmaz.
///
/// `Navigator.pop` değeri: `null` = vazgeçildi, `''` = etiket kaldırıldı.
class _LabelDialog extends StatefulWidget {
  const _LabelDialog({required this.entry});

  final ReportHistoryEntry entry;

  @override
  State<_LabelDialog> createState() => _LabelDialogState();
}

class _LabelDialogState extends State<_LabelDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.entry.label ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rapor adı'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const ValueKey('label-field'),
            controller: _controller,
            autofocus: true,
            maxLength: 60,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Kendi adın veya notun',
              hintText: widget.entry.sourceName,
            ),
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
          Text(
            'Boş bırakırsan dosya adı kullanılır: ${widget.entry.sourceName}',
            style: AppTextStyles.caption(context),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}

class _LocalDataNotice extends StatelessWidget {
  const _LocalDataNotice();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.lock_outline, size: 19),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            'Bu geçmiş yalnızca bu cihazdaki uygulama alanında saklanır ve istediğin zaman silinebilir.',
            style: AppTextStyles.caption(context),
          ),
        ),
      ],
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Text(
          'Henüz kaydedilmiş rapor yok.',
          style: AppTextStyles.muted(context),
        ),
      ),
    );
  }
}
