import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sana_app/core/network/sana_api_client.dart';
import 'package:sana_app/features/ml_dictionary/models/explain_response.dart';
import 'package:sana_app/features/ml_dictionary/models/term_models.dart';
import 'package:sana_app/features/ml_dictionary/screens/term_detail_screen.dart';
import 'package:sana_app/features/ml_dictionary/services/local_term_repository.dart';
import 'package:sana_app/features/ml_dictionary/services/ml_dictionary_service.dart';

class _FailingTermsClient extends SanaApiClient {
  int termCalls = 0;

  @override
  Future<List<dynamic>> getTerms() async {
    termCalls++;
    throw StateError('Network must not be used for bundled terms.');
  }

  @override
  Future<Map<String, dynamic>> getTermDetail(String labTest) async {
    termCalls++;
    throw StateError('Network must not be used for bundled term details.');
  }
}

class _OfflineDetailService extends MlDictionaryService {
  int explainCalls = 0;

  @override
  Future<TermDetail> getTermDetail(String labTest) async => const TermDetail(
    labTest: 'CRP',
    title: 'C-Reaktif Protein (CRP)',
    sections: ['Nedir?'],
    sources: [],
    sectionContents: {
      'Nedir?': 'CRP cihazdaki onaylı kaynak metninden açıklanır.',
    },
  );

  @override
  Future<ExplainResponse> explainLab({
    required String question,
    String? labTest,
    bool useSourceText = false,
  }) async {
    explainCalls++;
    throw StateError('Offline section must not call /explain.');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'bundled catalog contains all 240 reviewed terms and section text',
    () async {
      final repository = LocalTermRepository();

      final terms = await repository.getTerms();
      final crp = await repository.getTermDetail('crp');
      final afp = await repository.getTermDetail('AFP');

      expect(terms, hasLength(240));
      expect(crp, isNotNull);
      expect(crp!.sections, hasLength(6));
      expect(crp.contentForSection('Nedir?'), contains('iltihap'));
      expect(crp.sources, isNotEmpty);
      expect(afp?.contentForSection('Nedir?'), isNotEmpty);
    },
  );

  test('dictionary service does not call network for bundled terms', () async {
    final client = _FailingTermsClient();
    final service = MlDictionaryService(client: client);

    expect(await service.getTerms(), hasLength(240));
    expect((await service.getTermDetail('CRP')).labTest, 'CRP');
    expect(client.termCalls, 0);
  });

  testWidgets('opening a bundled section does not call explain endpoint', (
    tester,
  ) async {
    final service = _OfflineDetailService();
    await tester.pumpWidget(
      MaterialApp(
        home: TermDetailScreen(labTest: 'CRP', service: service),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Nedir?'));
    await tester.pump();

    expect(
      find.text('CRP cihazdaki onaylı kaynak metninden açıklanır.'),
      findsOneWidget,
    );
    expect(service.explainCalls, 0);
  });
}
