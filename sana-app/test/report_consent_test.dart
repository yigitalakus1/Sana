// Gizlilik sözleşmesinin en sert maddesi:
// **Kullanıcı onaylamadan rapor geçmişine hiçbir şey yazılmaz.**
//
// Sahte geçmiş servisi her `save` çağrısını sayar. Ayrıştırma sonrası sayaç
// sıfır kalmalı; ancak kullanıcı onay ekranından "Onayla" dediğinde artmalı.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sana_app/features/ml_dictionary/models/report_parse_models.dart';
import 'package:sana_app/features/ml_dictionary/models/term_models.dart';
import 'package:sana_app/features/ml_dictionary/screens/report_parse_screen.dart';
import 'package:sana_app/features/ml_dictionary/services/ml_dictionary_service.dart';
import 'package:sana_app/features/ml_dictionary/services/report_history_service.dart';

class _CountingHistoryService extends ReportHistoryService {
  int saveCalls = 0;
  List<ParsedLabResult> lastSaved = const [];

  @override
  Future<List<ReportHistoryEntry>> load() async => const [];

  @override
  Future<ReportHistoryEntry> save({
    required String sourceName,
    required List<ParsedLabResult> results,
    DateTime? reportDate,
  }) async {
    saveCalls++;
    lastSaved = List<ParsedLabResult>.of(results);
    return ReportHistoryEntry(
      id: '$saveCalls',
      createdAt: DateTime(2026, 3, 12),
      sourceName: sourceName,
      results: lastSaved,
      reportDate: reportDate,
    );
  }
}

class _TwoValueService extends MlDictionaryService {
  @override
  Future<List<TermSummary>> getTerms() async => const [
    TermSummary(labTest: 'CRP', title: 'C-Reaktif Protein', sections: []),
  ];

  @override
  Future<ReportParseResponse> parseReport(String text) async =>
      const ReportParseResponse(
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
        disclaimer: 'Bu bir teşhis değildir.',
      );
}

Future<void> pumpAndParse(
  WidgetTester tester,
  ReportHistoryService history,
) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: ReportParseScreen(
        service: _TwoValueService(),
        historyService: history,
      ),
    ),
  );
  await tester.pumpAndSettle();

  // Metin moduna geç ve ayrıştır.
  await tester.tap(find.text('Metin yapıştır'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Metni tara'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ayrıştırma tek başına geçmişe kayıt yapmaz', (tester) async {
    final history = _CountingHistoryService();
    await pumpAndParse(tester, history);

    // Onay ekranı açılmış olmalı ama henüz hiçbir şey kaydedilmemeli.
    expect(find.text('Değerleri kontrol et'), findsOneWidget);
    expect(
      history.saveCalls,
      0,
      reason: 'kullanıcı onaylamadan geçmişe yazılmamalı',
    );
  });

  testWidgets('vazgeçilirse hiçbir şey kaydedilmez', (tester) async {
    final history = _CountingHistoryService();
    await pumpAndParse(tester, history);

    await tester.tap(find.text('Vazgeç, kaydetme'));
    await tester.pumpAndSettle();

    expect(history.saveCalls, 0);
  });

  testWidgets('onaylanınca kaydedilir', (tester) async {
    final history = _CountingHistoryService();
    await pumpAndParse(tester, history);

    await tester.tap(find.text('Onayla ve geçmişe kaydet'));
    await tester.pumpAndSettle();

    expect(history.saveCalls, 1);
    expect(history.lastSaved, hasLength(1));
    expect(history.lastSaved.single.labTest, 'CRP');
  });

  testWidgets('kullanıcı düzeltmesi kayda yansır', (tester) async {
    final history = _CountingHistoryService();
    await pumpAndParse(tester, history);

    await tester.tap(find.text('Düzelt'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '3');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Onayla ve geçmişe kaydet'));
    await tester.pumpAndSettle();

    expect(history.saveCalls, 1);
    // Kaydedilen, ayrıştırıcının bulduğu 13.5 değil kullanıcının yazdığı 3.
    expect(history.lastSaved.single.rawValue, '3');
    expect(history.lastSaved.single.value, 3);
    // Aralık içine düştüğü için durum yeniden hesaplanmış olmalı.
    expect(history.lastSaved.single.interpretation, 'normal');
  });

  testWidgets('çıkarılan satır kaydedilmez', (tester) async {
    final history = _CountingHistoryService();
    await pumpAndParse(tester, history);

    await tester.tap(find.text('Çıkar'));
    await tester.pumpAndSettle();

    // Tek satır kalmadığında onay butonu devre dışı olur.
    final confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Onayla ve geçmişe kaydet'),
    );
    expect(confirm.onPressed, isNull);
    expect(history.saveCalls, 0);
  });
}
