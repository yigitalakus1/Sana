// `/reports/parse` yanıt modelleri. Değer alan adları `ResultContext` ile uyumlu.
//
// `reference_range` yalnız raporda açıkça bulunduğunda, `interpretation` ise
// bu aralığa göre deterministik hesaplanabildiğinde dolar.

Map<String, dynamic> _asMap(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

class ParsedLabResult {
  const ParsedLabResult({
    required this.labTest,
    this.matchedTerm,
    this.rawValue,
    this.value,
    this.unit,
    this.referenceRange,
    this.interpretation,
  });

  final String labTest;
  final String? matchedTerm;
  final String? rawValue;
  final double? value;
  final String? unit;
  final String? referenceRange;
  final String? interpretation;

  factory ParsedLabResult.fromJson(Map<String, dynamic> json) =>
      ParsedLabResult(
        labTest: (json['lab_test'] ?? '').toString(),
        matchedTerm: json['matched_term'] as String?,
        rawValue: json['raw_value'] as String?,
        value: (json['value'] as num?)?.toDouble(),
        unit: json['unit'] as String?,
        referenceRange: json['reference_range'] as String?,
        interpretation: json['interpretation'] as String?,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'lab_test': labTest,
    'matched_term': matchedTerm,
    'raw_value': rawValue,
    'value': value,
    'unit': unit,
    'reference_range': referenceRange,
    'interpretation': interpretation,
  };
}

class ReportParseResponse {
  const ReportParseResponse({
    required this.parserStatus,
    required this.results,
    required this.disclaimer,
    this.reportDate,
  });

  final String parserStatus; // parsed | no_results
  final List<ParsedLabResult> results;
  final String disclaimer;

  /// Rapor metnindeki etiketli tarih. Backend emin olamazsa null döner.
  final DateTime? reportDate;

  factory ReportParseResponse.fromJson(Map<String, dynamic> json) =>
      ReportParseResponse(
        parserStatus: (json['parser_status'] ?? '').toString(),
        results: (json['results'] is List ? json['results'] as List : const [])
            .map((e) => ParsedLabResult.fromJson(_asMap(e)))
            .toList(),
        disclaimer: (json['disclaimer'] ?? '').toString(),
        reportDate: _parseDate(json['report_date']),
      );
}

/// `YYYY-MM-DD` metnini güvenle tarihe çevirir; geçersizse null.
DateTime? _parseDate(dynamic raw) {
  final text = raw?.toString().trim();
  if (text == null || text.isEmpty) return null;
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}

class ReportHistoryEntry {
  const ReportHistoryEntry({
    required this.id,
    required this.createdAt,
    required this.sourceName,
    required this.results,
    this.label,
    this.reportDate,
  });

  final String id;
  final DateTime createdAt;

  /// Rapor metninden çıkarılan tarih. Bulunamadıysa null kalır ve gösterimde
  /// dosya adı → kayıt zamanı yedeğine düşülür.
  final DateTime? reportDate;

  /// Raporun geldiği dosyanın adı. Kullanıcı tarafından değiştirilmez.
  final String sourceName;
  final List<ParsedLabResult> results;

  /// Kullanıcının bu rapora verdiği ad/not. Boş veya null ise dosya adı
  /// kullanılır. Eski kayıtlarda bulunmaz; JSON'da yoksa null kalır.
  final String? label;

  /// Etiket girilmişse etiket, yoksa dosya adı.
  String get displayName => hasCustomLabel ? label!.trim() : sourceName;

  bool get hasCustomLabel => label != null && label!.trim().isNotEmpty;

  /// Etiketi değiştirilmiş bir kopya döndürür. `null` etiketi kaldırır.
  ReportHistoryEntry withLabel(String? newLabel) => ReportHistoryEntry(
    id: id,
    createdAt: createdAt,
    sourceName: sourceName,
    results: results,
    reportDate: reportDate,
    label: (newLabel == null || newLabel.trim().isEmpty)
        ? null
        : newLabel.trim(),
  );

  factory ReportHistoryEntry.fromJson(Map<String, dynamic> json) {
    final rawLabel = json['label']?.toString();
    return ReportHistoryEntry(
      id: (json['id'] ?? '').toString(),
      createdAt:
          DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      sourceName: (json['source_name'] ?? 'Rapor').toString(),
      results: (json['results'] is List ? json['results'] as List : const [])
          .map((item) => ParsedLabResult.fromJson(_asMap(item)))
          .toList(),
      label: (rawLabel == null || rawLabel.trim().isEmpty)
          ? null
          : rawLabel.trim(),
      reportDate: _parseDate(json['report_date']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'created_at': createdAt.toIso8601String(),
    'source_name': sourceName,
    'results': results.map((result) => result.toJson()).toList(),
    if (hasCustomLabel) 'label': label!.trim(),
    if (reportDate != null)
      'report_date': reportDate!.toIso8601String().split('T').first,
  };
}
