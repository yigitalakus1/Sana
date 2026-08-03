// ignore_for_file: avoid_print
// Manuel backend doğrulama scripti (test suite'e dahil DEĞİL).
// Backend açıkken:  dart run tool/smoke_test.dart
// Gerçek SanaApiClient + modellerini canlı backend'e karşı çalıştırır.

import 'package:sana_app/core/network/sana_api_client.dart';
import 'package:sana_app/features/ml_dictionary/models/explain_response.dart';
import 'package:sana_app/features/ml_dictionary/models/report_parse_models.dart';
import 'package:sana_app/features/ml_dictionary/models/term_models.dart';

Future<void> main() async {
  final client = SanaApiClient();
  try {
    final health = await client.health();
    print('HEALTH: $health');

    final terms = (await client.getTerms())
        .map((e) => TermSummary.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    print('TERMS: ${terms.map((t) => t.labTest).toList()}');

    final detail = TermDetail.fromJson(await client.getTermDetail('crp'));
    print('TERM DETAIL (crp): lab=${detail.labTest} '
        'sections=${detail.sections.length} sources=${detail.sources.length}');

    final explain = ExplainResponse.fromJson(
      await client.explain(question: 'CRP 13.5 çıktı', labTest: 'CRP'),
    );
    print('EXPLAIN: type=${explain.responseType} lab=${explain.labTest} '
        'conf=${explain.confidenceLabel} rc=${explain.resultContext?.value} '
        'citations=${explain.citations.length} '
        'doctorQ=${explain.doctorQuestions.length} provider=${explain.llmProvider}');

    final parse = ReportParseResponse.fromJson(
      await client.parseReport('CRP: 13.5 mg/L\nGlukoz 92 mg/dL'),
    );
    print('PARSE: status=${parse.parserStatus} '
        'results=${parse.results.map((r) => '${r.labTest}=${r.value}${r.unit ?? ''}').toList()}');

    print('SMOKE_OK');
  } on SanaApiException catch (e) {
    print('SMOKE_FAIL (friendly): ${e.message}');
  } catch (e) {
    print('SMOKE_FAIL (unexpected): $e');
  } finally {
    client.close();
  }
}
