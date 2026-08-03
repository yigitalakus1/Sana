import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sana_app/features/ml_dictionary/models/term_models.dart';
import 'package:sana_app/features/ml_dictionary/screens/assistant_screen.dart';
import 'package:sana_app/features/ml_dictionary/screens/term_detail_screen.dart';
import 'package:sana_app/features/ml_dictionary/services/ml_dictionary_service.dart';

class _FakeDictionaryService extends MlDictionaryService {
  @override
  Future<TermDetail> getTermDetail(String labTest) async {
    return TermDetail.fromJson(<String, dynamic>{
      'lab_test': labTest,
      'title': '$labTest testi',
      'sections': <String>['Nedir?'],
      'sources': <dynamic>[],
    });
  }
}

void main() {
  testWidgets('AssistantScreen shows a transferred question in the composer', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AssistantScreen(
          initialQuestion: 'Ferritin nedir?',
          prefillRevision: 1,
        ),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, 'Ferritin nedir?');
  });

  testWidgets('Term detail forwards the selected lab test to Assistant', (
    tester,
  ) async {
    String? question;
    String? labTest;

    await tester.pumpWidget(
      MaterialApp(
        home: TermDetailScreen(
          labTest: 'CRP',
          service: _FakeDictionaryService(),
          onAskAssistant: (value, selectedLabTest) {
            question = value;
            labTest = selectedLabTest;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Asistana sor'), findsOneWidget);
    expect(find.text('Bu tahlili Asistana sor'), findsOneWidget);

    await tester.tap(find.byTooltip('Asistana sor'));
    await tester.pump();

    expect(question, 'CRP nedir?');
    expect(labTest, 'CRP');
  });
}
