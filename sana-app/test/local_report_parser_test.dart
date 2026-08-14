import 'package:flutter_test/flutter_test.dart';

import 'package:sana_app/core/network/sana_api_client.dart';
import 'package:sana_app/features/ml_dictionary/services/local_report_parser.dart';
import 'package:sana_app/features/ml_dictionary/services/local_term_repository.dart';
import 'package:sana_app/features/ml_dictionary/services/ml_dictionary_service.dart';

class _FailingParseClient extends SanaApiClient {
  int parseCalls = 0;

  @override
  Future<Map<String, dynamic>> parseReport(String text) async {
    parseCalls++;
    throw StateError('Network must not be used for report text parsing.');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalReportParser parser;

  setUp(() => parser = LocalReportParser());

  test('sample report parses three values with units', () async {
    final response = await parser.parse(
      'CRP: 13.5 mg/L\nGlukoz 92 mg/dL\nFerritin: 8 ng/mL',
    );

    expect(response.parserStatus, 'parsed');
    expect(response.results.map((item) => item.labTest), [
      'CRP',
      'Glukoz',
      'Ferritin',
    ]);
    expect(response.results.first.value, 13.5);
    expect(response.results.first.unit, 'mg/L');
    expect(
      response.results.every((item) => item.interpretation == null),
      isTrue,
    );
  });

  test('test name digits are not mistaken for a measured value', () async {
    final empty = await parser.parse('B12 nedir?');
    final measured = await parser.parse('B12 350 pg/mL');

    expect(empty.parserStatus, 'no_results');
    expect(empty.results, isEmpty);
    expect(measured.results.single.labTest, 'B12');
    expect(measured.results.single.value, 350);
  });

  test('common aliases resolve to canonical bundled terms', () async {
    final response = await parser.parse(
      'C reaktif protein 13,5\nSGPT 25 U/L\nPLT 250 10^3/uL',
    );

    expect(response.results.map((item) => item.labTest).toSet(), {
      'CRP',
      'ALT',
      'Trombosit',
    });
  });

  test('all 240 canonical test names are parseable', () async {
    final terms = await LocalTermRepository().getTermDetails();
    final failures = <String>[];
    for (final term in terms) {
      final response = await parser.parse('${term.labTest} 7.5 mg/L');
      final actual = response.results.isEmpty
          ? null
          : response.results.first.labTest;
      if (actual != term.labTest) failures.add('${term.labTest} -> $actual');
    }

    expect(failures, isEmpty, reason: failures.join(', '));
  });

  test('multiline value, unit and bounded range are parsed safely', () async {
    final response = await parser.parse('AFP\n2.3\nng/mL\n0.0 - 8.0');
    final result = response.results.single;

    expect(result.labTest, 'AFP');
    expect(result.value, 2.3);
    expect(result.unit, 'ng/mL');
    expect(result.referenceRange, '0.0 - 8.0');
    expect(result.interpretation, 'normal');
  });

  test('same-line and limit ranges are classified deterministically', () async {
    final response = await parser.parse(
      'CRP 13.5 mg/L Referans: 0 - 5\n'
      'HDL Kolesterol 35 mg/dL Referans: >= 40',
    );
    final byLab = {for (final item in response.results) item.labTest: item};

    expect(byLab['CRP']?.interpretation, 'high');
    expect(byLab['HDL Kolesterol']?.interpretation, 'low');
  });

  test('ambiguous and reversed ranges are not guessed', () async {
    final response = await parser.parse(
      'Ferritin 20 ng/mL Referans: kadın 10-120 erkek 20-250\n'
      'CRP 3 mg/L Referans: 5-0',
    );

    expect(response.results, hasLength(2));
    expect(
      response.results.every((item) => item.referenceRange == null),
      isTrue,
    );
    expect(
      response.results.every((item) => item.interpretation == null),
      isTrue,
    );
  });

  test('labeled report date wins and birth date is ignored', () async {
    final response = await parser.parse(
      'Doğum Tarihi: 12.05.1980\nRapor Tarihi: 03.02.2026\nCRP 3 mg/L',
      today: DateTime(2026, 7, 27),
    );

    expect(response.reportDate, DateTime(2026, 2, 3));
  });

  test('service uses local parser without calling backend', () async {
    final client = _FailingParseClient();
    final service = MlDictionaryService(client: client);

    final response = await service.parseReport('ALT 25 U/L');

    expect(response.results.single.labTest, 'ALT');
    expect(client.parseCalls, 0);
  });
}
