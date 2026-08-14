import 'explain_response.dart' show Citation;

List<String> _asStringList(dynamic v) =>
    v is List ? v.map((e) => e.toString()).toList() : <String>[];

Map<String, dynamic> _asMap(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

Map<String, String> _asStringMap(dynamic v) => v is Map
    ? v.map((key, value) => MapEntry(key.toString(), value.toString()))
    : <String, String>{};

const String _turkishAlphabet = 'ABCÇDEFGĞHIİJKLMNOÖPQRSŞTUÜVWXYZ';

String _turkishUpper(String value) =>
    value.trim().replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

int _turkishCharacterWeight(int rune) {
  if (rune >= 48 && rune <= 57) return rune - 48;
  final index = _turkishAlphabet.indexOf(String.fromCharCode(rune));
  return index < 0 ? 1000 + rune : 10 + index;
}

int _compareTurkish(String left, String right) {
  final leftRunes = _turkishUpper(left).runes.toList();
  final rightRunes = _turkishUpper(right).runes.toList();
  final length = leftRunes.length < rightRunes.length
      ? leftRunes.length
      : rightRunes.length;

  for (var i = 0; i < length; i++) {
    final comparison = _turkishCharacterWeight(
      leftRunes[i],
    ).compareTo(_turkishCharacterWeight(rightRunes[i]));
    if (comparison != 0) return comparison;
  }
  return leftRunes.length.compareTo(rightRunes.length);
}

List<TermSummary> sortTermSummariesAlphabetically(
  Iterable<TermSummary> terms,
) =>
    List<TermSummary>.of(terms)
      ..sort((left, right) => _compareTurkish(left.labTest, right.labTest));

class TermSummary {
  const TermSummary({
    required this.labTest,
    this.title,
    required this.sections,
  });

  final String labTest;
  final String? title;
  final List<String> sections;

  factory TermSummary.fromJson(Map<String, dynamic> json) => TermSummary(
    labTest: (json['lab_test'] ?? '').toString(),
    title: json['title'] as String?,
    sections: _asStringList(json['sections']),
  );
}

class TermDetail {
  const TermDetail({
    required this.labTest,
    this.title,
    required this.sections,
    required this.sources,
    this.aliases = const [],
    this.sectionContents = const {},
  });

  final String labTest;
  final String? title;
  final List<String> sections;
  final List<Citation> sources;
  final List<String> aliases;
  final Map<String, String> sectionContents;

  String? contentForSection(String section) {
    final content = sectionContents[section]?.trim();
    return content == null || content.isEmpty ? null : content;
  }

  factory TermDetail.fromJson(Map<String, dynamic> json) => TermDetail(
    labTest: (json['lab_test'] ?? '').toString(),
    title: json['title'] as String?,
    sections: _asStringList(json['sections']),
    sources: (json['sources'] is List ? json['sources'] as List : const [])
        .map((e) => Citation.fromJson(_asMap(e)))
        .toList(),
    aliases: _asStringList(json['aliases']),
    sectionContents: _asStringMap(json['section_contents']),
  );
}
