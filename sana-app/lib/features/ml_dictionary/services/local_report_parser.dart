import '../models/report_parse_models.dart';
import '../models/term_models.dart';
import 'local_term_repository.dart';

class LocalReportParser {
  LocalReportParser({LocalTermRepository? terms})
    : _terms = terms ?? LocalTermRepository();

  static const String _disclaimer =
      'Bu açıklama yalnızca bilgilendirme amaçlıdır; tanı, tedavi veya tıbbi '
      'karar önerisi değildir. Sonuçlarınızı doktorunuzla birlikte '
      'değerlendiriniz.';

  static final RegExp _number = RegExp(
    r'(?:^|[^\w])([<>]?\s*-?\d+(?:[.,]\d+)?)',
  );
  static final RegExp _standaloneNumber = RegExp(
    r'^\s*([<>]?\s*-?\d+(?:[.,]\d+)?)',
  );
  static final RegExp _unit = RegExp(
    r'^\s*(%|(?:[xX]\s*)?10(?:\^?\d+|[⁰¹²³⁴⁵⁶⁷⁸⁹]+)\s*/\s*[A-Za-zµμ]+|[A-Za-zµμ]+(?:\s*/\s*[A-Za-zµμ]+)?)',
  );
  static final RegExp _resultFlag = RegExp(
    r'^(?:h|l|high|low|yüksek|düşük|\*)$',
    caseSensitive: false,
  );
  static final RegExp _leadingResultFlag = RegExp(
    r'^(?:h|l|high|low|yüksek|düşük|\*)\s+',
    caseSensitive: false,
  );
  static final RegExp _boundedRange = RegExp(
    r'(-?\d+(?:[.,]\d+)?)\s*(?:[-–—]|\.\.|…|ile)\s*(-?\d+(?:[.,]\d+)?)',
    caseSensitive: false,
  );
  static final RegExp _limitRange = RegExp(
    r'(<=|>=|<|>|≤|≥)\s*(-?\d+(?:[.,]\d+)?)',
  );
  static final RegExp _rangeLabel = RegExp(
    r'(?:rapor\s+)?(?:referans(?:\s+aral(?:ı|i)ğ(?:ı|i))?|normal\s+(?:değer|deger|aralık|aralik))\s*[:=]?\s*',
    caseSensitive: false,
  );
  static final RegExp _anyNumber = RegExp(r'-?\d+(?:[.,]\d+)?');
  static final RegExp _dateDmy = RegExp(
    r'(?<!\d)(\d{1,2})[./-](\d{1,2})[./-](\d{4})(?!\d)',
  );
  static final RegExp _dateYmd = RegExp(
    r'(?<!\d)(\d{4})-(\d{1,2})-(\d{1,2})(?!\d)',
  );

  static const List<String> _dateLabels = [
    'rapor tarihi',
    'sonuç tarihi',
    'sonuc tarihi',
    'onay tarihi',
    'numune tarihi',
    'numune alma',
    'alınma tarihi',
    'alinma tarihi',
    'kabul tarihi',
    'işlem tarihi',
    'islem tarihi',
    'tarih',
  ];

  final LocalTermRepository _terms;

  Future<ReportParseResponse> parse(String text, {DateTime? today}) async {
    final definitions = await _terms.getTermDetails();
    final resolver = _LabResolver(definitions);
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    final results = <ParsedLabResult>[];
    final seen = <String>{};

    // Ayrıştırıcının kullandığı satırlar. Ölçüm gibi görünüp eşleşmeyen
    // satırları bulabilmek için hangi satırların tüketildiğini biliyoruz.
    final usedLines = <int>{};

    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final sameLine = _extractMatchedValue(line, resolver);
      var value = sameLine?.value;
      _LabMatch match;
      String? referenceRange;

      if (value == null) {
        match = resolver.resolveLine(line, null);
        if (match.labTest == null || index + 1 >= lines.length) continue;
        value = _extractStandaloneValue(lines[index + 1]);
        if (value == null) continue;
        usedLines.add(index + 1);
        var consumedThrough = index + 1;
        if (value.unit == null && index + 2 < lines.length) {
          final unit = _extractUnitOnly(lines[index + 2]);
          if (unit != null) {
            value = value.copyWith(unit: unit);
            usedLines.add(index + 2);
            consumedThrough = index + 2;
          }
        }
        referenceRange = _rangeFromFollowingLines(
          lines,
          consumedThrough + 1,
          resolver,
        );
      } else {
        match = sameLine!.match;
        referenceRange = _rangeAfterValue(line, value);
        referenceRange ??= _rangeFromFollowingLines(lines, index + 1, resolver);
      }

      final labTest = match.labTest;
      if (labTest == null) continue;
      usedLines.add(index);

      // Aynı tahlilin farklı ölçümü sessizce atılmaz: raporda iki kez geçen
      // bir değer kullanıcının görmesi gereken bir bilgidir (ör. açlık/tokluk
      // glukoz, tekrar bakılan kontrol). Yalnız birebir aynı satır elenir.
      final fingerprint = '$labTest|${value.raw}|${value.unit ?? ''}';
      if (!seen.add(fingerprint)) continue;

      results.add(
        ParsedLabResult(
          labTest: labTest,
          matchedTerm: match.matchedTerm,
          rawValue: value.raw,
          value: value.value,
          unit: value.unit,
          referenceRange: referenceRange,
          interpretation: classifyValue(value.value, referenceRange),
        ),
      );
    }

    return ReportParseResponse(
      parserStatus: results.isEmpty ? 'no_results' : 'parsed',
      results: results,
      disclaimer: _disclaimer,
      reportDate: extractReportDate(text, today: today),
      unmatchedLines: _unmatchedLines(lines, usedLines),
    );
  }

  /// Ölçüm gibi görünüp hiçbir tahlile bağlanamayan satırlar.
  ///
  /// Kamera okumasında bir harf yanlış tanınınca (ör. "HbA1c" → "Hba1e") satır
  /// sessizce kaybolur. Kullanıcının bunu görmesi gerekir; ekranda kehribar
  /// uyarıyla listelenir ve sözlükten elle eklenebilir.
  ///
  /// Gürültüyü azaltmak için yalnız **hem sayı hem kelime** içeren satırlara
  /// bakılır; tarih, protokol numarası ve uzun kimlik dizileri elenir.
  static List<String> _unmatchedLines(List<String> lines, Set<int> usedLines) {
    final candidates = <String>[];
    for (var index = 0; index < lines.length; index++) {
      if (usedLines.contains(index)) continue;
      final line = lines[index];
      if (!_looksLikeMeasurement(line)) continue;
      candidates.add(line);
    }
    return List.unmodifiable(candidates);
  }

  static final RegExp _word = RegExp(r'[A-Za-zçğıöşüÇĞİÖŞÜ]{3,}');
  static final RegExp _longDigitRun = RegExp(r'\d{8,}');

  static bool _looksLikeMeasurement(String line) {
    if (!_anyNumber.hasMatch(line)) return false;
    if (!_word.hasMatch(line)) return false;
    // Tarih satırı ölçüm değildir.
    if (_dateDmy.hasMatch(line) || _dateYmd.hasMatch(line)) return false;
    // Protokol/TC/telefon gibi uzun rakam dizileri.
    if (_longDigitRun.hasMatch(line)) return false;
    return true;
  }

  static _MatchedValue? _extractMatchedValue(
    String line,
    _LabResolver resolver,
  ) {
    for (final numberMatch in _number.allMatches(line)) {
      final value = _parsedValue(line, numberMatch);
      if (value == null) continue;
      final lab = resolver.resolveLabel(
        line.substring(0, _numberGroupStart(numberMatch)),
        value.unit,
      );
      if (lab.labTest != null) return _MatchedValue(value, lab);
    }
    return null;
  }

  static _ParsedValue? _extractStandaloneValue(String line) {
    final match = _standaloneNumber.firstMatch(line);
    if (match == null) return null;
    final parsed = _parsedValue(line, match);
    if (parsed == null) return null;
    var remainder = line.substring(parsed.consumedThrough).trim();
    if (remainder.isNotEmpty && !_resultFlag.hasMatch(remainder)) return null;
    return parsed;
  }

  static _ParsedValue? _parsedValue(String line, RegExpMatch match) {
    final token = match.group(1);
    if (token == null) return null;
    final raw = token.replaceAll('<', '').replaceAll('>', '').trim();
    final value = double.tryParse(raw.replaceAll(',', '.'));
    if (value == null) return null;

    var consumedThrough = match.end;
    String? unit;
    final unitMatch = _unit.firstMatch(line.substring(consumedThrough));
    if (unitMatch != null) {
      unit = unitMatch.group(1);
      consumedThrough += unitMatch.end;
    }
    return _ParsedValue(
      raw: raw,
      value: value,
      unit: unit,
      consumedThrough: consumedThrough,
    );
  }

  static int _numberGroupStart(RegExpMatch match) {
    final full = match.group(0)!;
    final captured = match.group(1)!;
    return match.start + full.indexOf(captured);
  }

  static String? _extractUnitOnly(String line) {
    final match = _unit.firstMatch(line.trim());
    return match != null && match.end == line.trim().length
        ? match.group(1)
        : null;
  }

  static String? _rangeAfterValue(String line, _ParsedValue value) {
    final remainder = line
        .substring(value.consumedThrough)
        .trim()
        .replaceFirst(_leadingResultFlag, '');
    return _extractReferenceRange(remainder);
  }

  static String? _rangeFromFollowingLines(
    List<String> lines,
    int start,
    _LabResolver resolver,
  ) {
    final end = (start + 3).clamp(0, lines.length);
    for (var index = start; index < end; index++) {
      final candidate = lines[index];
      if (resolver.resolveLine(candidate, null).labTest != null) break;
      final range = _extractReferenceRange(candidate);
      if (range != null) return range;
    }
    return null;
  }

  static String? _extractReferenceRange(String text) {
    if (text.trim().isEmpty) return null;
    var search = text.trim().replaceAll(RegExp(r'^[\(\[\{]+|[\)\]\}]+$'), '');
    final label = _rangeLabel.firstMatch(search);
    if (label != null) search = search.substring(label.end);

    final bounded = _boundedRange.allMatches(search).toList();
    final limits = _limitRange.allMatches(search).toList();
    if (bounded.length + limits.length != 1) return null;

    final match = bounded.isNotEmpty ? bounded.single : limits.single;
    final remainder =
        '${search.substring(0, match.start)} '
        '${search.substring(match.end)}';
    if (_anyNumber.hasMatch(remainder)) return null;

    if (bounded.isNotEmpty) {
      final low = _toDouble(match.group(1));
      final high = _toDouble(match.group(2));
      if (low == null || high == null || low > high) return null;
      return '${match.group(1)} - ${match.group(2)}';
    }
    final operator = match
        .group(1)
        ?.replaceAll('≤', '<=')
        .replaceAll('≥', '>=');
    return '$operator ${match.group(2)}';
  }

  /// Değeri raporun **kendi** referans aralığına göre sınıflandırır.
  ///
  /// Aralık yoksa `null` döner — sınıflandırma uydurulmaz. Onay ekranı da
  /// kullanıcı değeri veya aralığı düzenlediğinde bu fonksiyonu yeniden
  /// çağırır, böylece tek bir kural kalır.
  static String? classifyValue(double value, String? referenceRange) {
    if (referenceRange == null) return null;
    final bounded = _boundedRange.firstMatch(referenceRange);
    if (bounded != null && bounded.group(0) == referenceRange) {
      final low = _toDouble(bounded.group(1));
      final high = _toDouble(bounded.group(2));
      if (low == null || high == null || low > high) return null;
      if (value < low) return 'low';
      if (value > high) return 'high';
      return 'normal';
    }
    final limit = _limitRange.firstMatch(referenceRange);
    if (limit == null || limit.group(0) != referenceRange) return null;
    final boundary = _toDouble(limit.group(2));
    if (boundary == null) return null;
    switch (limit.group(1)?.replaceAll('≤', '<=').replaceAll('≥', '>=')) {
      case '<':
        return value < boundary ? 'normal' : 'high';
      case '<=':
        return value <= boundary ? 'normal' : 'high';
      case '>':
        return value > boundary ? 'normal' : 'low';
      case '>=':
        return value >= boundary ? 'normal' : 'low';
    }
    return null;
  }

  static double? _toDouble(String? value) =>
      value == null ? null : double.tryParse(value.replaceAll(',', '.'));

  static DateTime? extractReportDate(String text, {DateTime? today}) {
    final current = today ?? DateTime.now();
    final candidates = <int, DateTime>{};
    for (final line in text.split(RegExp(r'\r?\n'))) {
      final lower = _turkishLower(line);
      if (lower.contains('doğum') || lower.contains('dogum')) continue;
      final labelIndex = _dateLabels.indexWhere(lower.contains);
      if (labelIndex < 0) continue;
      final dates = <DateTime>[];
      for (final match in _dateDmy.allMatches(line)) {
        final parsed = _safeDate(
          int.parse(match.group(3)!),
          int.parse(match.group(2)!),
          int.parse(match.group(1)!),
          current,
        );
        if (parsed != null) dates.add(parsed);
      }
      for (final match in _dateYmd.allMatches(line)) {
        final parsed = _safeDate(
          int.parse(match.group(1)!),
          int.parse(match.group(2)!),
          int.parse(match.group(3)!),
          current,
        );
        if (parsed != null) dates.add(parsed);
      }
      if (dates.isNotEmpty) {
        candidates.putIfAbsent(labelIndex, () => dates.first);
      }
    }
    if (candidates.isEmpty) return null;
    final bestIndex = candidates.keys.reduce(
      (left, right) => left < right ? left : right,
    );
    return candidates[bestIndex];
  }

  static DateTime? _safeDate(int year, int month, int day, DateTime today) {
    if (year < 1990) return null;
    final parsed = DateTime(year, month, day);
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      return null;
    }
    final todayOnly = DateTime(today.year, today.month, today.day);
    return parsed.isAfter(todayOnly) ? null : parsed;
  }

  static String _normalize(String value) => _turkishLower(value)
      .replaceAll(RegExp(r'[^\wçğıöşü\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _turkishLower(String value) =>
      value.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();
}

class _LabResolver {
  _LabResolver(List<TermDetail> terms)
    : _aliases = [
        for (final term in terms)
          for (final alias in <String>{
            term.labTest,
            term.title ?? '',
            ...term.aliases,
          })
            if (alias.trim().isNotEmpty)
              _LabAlias(term.labTest, LocalReportParser._normalize(alias)),
      ]..sort((left, right) => right.alias.length.compareTo(left.alias.length));

  final List<_LabAlias> _aliases;

  _LabMatch resolveLine(String line, String? unit) {
    for (final number in LocalReportParser._number.allMatches(line)) {
      final match = resolveLabel(
        line.substring(0, LocalReportParser._numberGroupStart(number)),
        unit,
      );
      if (match.labTest != null) return match;
    }
    return resolveLabel(line, unit);
  }

  _LabMatch resolveLabel(String rawLabel, String? unit) {
    var label = LocalReportParser._normalize(rawLabel);
    label = label
        .replaceAll(RegExp(r'\b(?:high|low|yuksek|dusuk|yüksek|düşük)\b'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (label == 'pct') {
      return _canonical(unit == '%' ? 'Plateletkrit' : 'Prokalsitonin');
    }
    for (final alias in _aliases) {
      if (label == alias.alias || label.startsWith('${alias.alias} ')) {
        return _LabMatch(alias.labTest, alias.alias);
      }
    }
    return const _LabMatch(null, null);
  }

  _LabMatch _canonical(String labTest) {
    for (final alias in _aliases) {
      if (alias.labTest == labTest) return _LabMatch(labTest, alias.alias);
    }
    return const _LabMatch(null, null);
  }
}

class _LabAlias {
  const _LabAlias(this.labTest, this.alias);

  final String labTest;
  final String alias;
}

class _LabMatch {
  const _LabMatch(this.labTest, this.matchedTerm);

  final String? labTest;
  final String? matchedTerm;
}

class _ParsedValue {
  const _ParsedValue({
    required this.raw,
    required this.value,
    required this.unit,
    required this.consumedThrough,
  });

  final String raw;
  final double value;
  final String? unit;
  final int consumedThrough;

  _ParsedValue copyWith({String? unit}) => _ParsedValue(
    raw: raw,
    value: value,
    unit: unit ?? this.unit,
    consumedThrough: consumedThrough,
  );
}

class _MatchedValue {
  const _MatchedValue(this.value, this.match);

  final _ParsedValue value;
  final _LabMatch match;
}
