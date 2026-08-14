import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/term_models.dart';

class LocalTermRepository {
  LocalTermRepository({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  static const String assetPath = 'assets/data/lab_terms_v1.json';
  static const int supportedSchemaVersion = 1;

  final AssetBundle _bundle;
  Future<_LocalTermCatalog>? _catalog;

  Future<List<TermSummary>> getTerms() async {
    final catalog = await _load();
    return catalog.terms
        .map(
          (term) => TermSummary(
            labTest: term.labTest,
            title: term.title,
            sections: term.sections,
          ),
        )
        .toList(growable: false);
  }

  Future<TermDetail?> getTermDetail(String labTest) async {
    final catalog = await _load();
    return catalog.byNormalizedName[_normalize(labTest)];
  }

  Future<List<TermDetail>> getTermDetails() async => (await _load()).terms;

  Future<_LocalTermCatalog> _load() => _catalog ??= _loadFromAsset();

  Future<_LocalTermCatalog> _loadFromAsset() async {
    final raw = await _bundle.loadString(assetPath);
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Offline term catalog is not an object.');
    }
    final payload = Map<String, dynamic>.from(decoded);
    if (payload['schema_version'] != supportedSchemaVersion) {
      throw const FormatException('Unsupported offline term catalog version.');
    }
    final rawTerms = payload['terms'];
    if (rawTerms is! List || rawTerms.isEmpty) {
      throw const FormatException('Offline term catalog is empty.');
    }

    final terms = rawTerms
        .whereType<Map>()
        .map((item) => TermDetail.fromJson(Map<String, dynamic>.from(item)))
        .where((term) => term.labTest.trim().isNotEmpty)
        .toList(growable: false);
    if (terms.length != payload['term_count']) {
      throw const FormatException('Offline term catalog count mismatch.');
    }
    return _LocalTermCatalog(terms);
  }

  static String _normalize(String value) =>
      value.trim().replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();
}

class _LocalTermCatalog {
  _LocalTermCatalog(this.terms)
    : byNormalizedName = {
        for (final term in terms)
          LocalTermRepository._normalize(term.labTest): term,
      };

  final List<TermDetail> terms;
  final Map<String, TermDetail> byNormalizedName;
}
