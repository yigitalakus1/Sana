// Regresyon: rapordan gelen "Yüksek/Düşük" bayrakları /explain sorusuna
// sızmamalı. Backend bölüm tespitinde bu kelimeleri kullandığı için, sızdığında
// tanım sorusu yüksek/düşük yorumuna kayıyor ve cevapta tahlilin ne olduğunu
// anlatan metin hiç bulunmuyordu.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sana_app/features/ml_dictionary/models/explain_response.dart';
import 'package:sana_app/features/ml_dictionary/models/report_parse_models.dart';
import 'package:sana_app/features/ml_dictionary/screens/report_parse_screen.dart';
import 'package:sana_app/features/ml_dictionary/services/ml_dictionary_service.dart';

class _FlaggedReportService extends MlDictionaryService {
  String? lastExplainQuestion;

  @override
  Future<ReportParseResponse> parseReport(String text) async {
    return const ReportParseResponse(
      parserStatus: 'parsed',
      results: [
        ParsedLabResult(
          labTest: 'Hemoglobin',
          matchedTerm: 'hgb',
          // Gerçek raporlarda değer ve referans sütunlarında sık görülen bayraklar
          rawValue: '160 Yüksek',
          value: 160,
          unit: 'g/L',
          referenceRange: 'Düşük <132, Yüksek >173',
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
    return const ExplainResponse(
      requestId: 'test',
      responseType: 'answer',
      labTest: 'Hemoglobin',
      matchedTerm: 'hgb',
      answer: 'Hemoglobin, kanda oksijen taşıyan bir proteindir.',
      confidence: 0.9,
      confidenceLabel: 'high',
      citations: [Citation(sourceTitle: 'MedlinePlus')],
      doctorQuestions: [],
      disclaimer: 'Bilgilendirme amaçlıdır.',
      safetyNotes: [],
      retrievedChunks: [],
    );
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('rapordaki durum bayrakları açıklama sorusuna sızmaz', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _FlaggedReportService();
    await tester.pumpWidget(
      MaterialApp(home: ReportParseScreen(service: service)),
    );

    await tester.tap(find.text('Metin yapıştır'));
    await tester.pump();
    await tester.tap(find.text('Metni tara'));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -260));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Hemoglobin'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hemoglobin'));
    await tester.pumpAndSettle();

    final question = service.lastExplainQuestion;
    expect(question, isNotNull);

    // Bayrak kelimeleri temizlenmiş olmalı.
    expect(question!.toLowerCase(), isNot(contains('yüksek')));
    expect(question.toLowerCase(), isNot(contains('düşük')));

    // Soru anlamını korumalı: tahlil adı, ölçüm ve tanım isteği yerinde.
    expect(question, contains('Hemoglobin'));
    expect(question, contains('160'));
    expect(question, contains('g/L'));
    expect(question, contains('Bu tahlil nedir'));
    expect(question, contains('neden ölçülür'));

    // Ekranda ham rapor verisi yine olduğu gibi gösterilir.
    expect(find.text('Düşük <132, Yüksek >173'), findsOneWidget);
  });
}
