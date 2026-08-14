import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sana_app/features/ml_dictionary/models/explain_response.dart';
import 'package:sana_app/features/ml_dictionary/models/report_parse_models.dart';
import 'package:sana_app/features/ml_dictionary/models/term_models.dart';
import 'package:sana_app/features/ml_dictionary/screens/report_history_screen.dart';
import 'package:sana_app/features/ml_dictionary/screens/report_parse_screen.dart';
import 'package:sana_app/features/ml_dictionary/services/ml_dictionary_service.dart';

class _FakeReportService extends MlDictionaryService {
  String? lastExplainQuestion;

  @override
  Future<TermDetail> getTermDetail(String labTest) async => const TermDetail(
    labTest: 'CRP',
    title: 'C-Reaktif Protein',
    sections: ['Nedir?', 'Neden ölçülür?'],
    sources: [Citation(sourceTitle: 'MedlinePlus')],
    sectionContents: {
      'Nedir?':
          'CRP, vücuttaki iltihaplanma süreçleriyle ilişkili bir belirteçtir.',
      'Neden ölçülür?':
          'İltihaplanma süreçlerini değerlendirmeye yardımcı olur.',
    },
  );

  @override
  Future<ReportParseResponse> parseReport(String text) async {
    return const ReportParseResponse(
      parserStatus: 'parsed',
      results: [
        ParsedLabResult(
          labTest: 'CRP',
          matchedTerm: 'crp',
          rawValue: '13.5',
          value: 13.5,
          unit: 'mg/L',
          referenceRange: '0 - 5',
          interpretation: 'high',
        ),
      ],
      disclaimer: 'Bilgilendirme amaçlıdır.',
    );
  }

  @override
  Future<ExplainResponse> explainLab({
    required String question,
    String? labTest,
    bool useSourceText = false,
  }) async {
    lastExplainQuestion = question;
    throw StateError('Bundled explanation must not call /explain.');
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('expanded result shows explanation and opens comparison', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _FakeReportService();
    await tester.pumpWidget(
      MaterialApp(home: ReportParseScreen(service: service)),
    );

    expect(find.text('PDF laboratuvar raporu seç'), findsOneWidget);

    await tester.tap(find.text('Metin yapıştır'));
    await tester.pump();
    await tester.tap(find.text('Metni tara'));
    await tester.pumpAndSettle();

    // Ayrıştırma artık doğrudan kaydetmiyor: önce onay ekranı açılıyor.
    // Sonuç listesine ulaşmak için değerleri onaylamak gerekiyor.
    await tester.tap(find.text('Onayla ve geçmişe kaydet'));
    await tester.pumpAndSettle();

    expect(find.text('Bulunan tahliller'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -260));
    await tester.pumpAndSettle();
    expect(find.text('CRP'), findsOneWidget);

    await tester.ensureVisible(find.text('CRP'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CRP'));
    await tester.pumpAndSettle();

    expect(find.text('Eşleşen ifade'), findsOneWidget);
    expect(find.text('Rapor referans aralığı'), findsOneWidget);
    expect(find.text('0 - 5'), findsOneWidget);
    expect(find.text('Aralığa göre durum'), findsOneWidget);
    expect(find.text('Yüksek'), findsOneWidget);
    expect(service.lastExplainQuestion, isNull);
    expect(
      find.textContaining(
        'CRP, vücuttaki iltihaplanma süreçleriyle ilişkili bir belirteçtir.',
      ),
      findsOneWidget,
    );
    expect(find.text('MedlinePlus'), findsOneWidget);
    expect(
      find.textContaining('yalnızca bilgilendirme amaçlıdır'),
      findsWidgets,
    );

    final compare = find.byKey(const ValueKey('compare-CRP'));
    await tester.scrollUntilVisible(
      compare,
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(compare);
    await tester.pumpAndSettle();

    final history = tester.widget<ReportHistoryScreen>(
      find.byType(ReportHistoryScreen),
    );
    expect(history.initialLabTest, 'CRP');
  });
}
