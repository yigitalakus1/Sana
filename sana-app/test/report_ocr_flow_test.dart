// OCR akışının ekran seviyesindeki sözleşmesi.
//
// En önemlisi: OCR sonucu doğrudan kaydedilmez. Metin önce düzenlenebilir
// alana düşer, kullanıcı düzeltir, ayrıştırır ve ancak onay ekranından sonra
// geçmişe yazılır.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sana_app/features/ml_dictionary/models/report_parse_models.dart';
import 'package:sana_app/features/ml_dictionary/models/term_models.dart';
import 'package:sana_app/features/ml_dictionary/screens/report_parse_screen.dart';
import 'package:sana_app/features/ml_dictionary/services/local_ocr_service.dart';
import 'package:sana_app/features/ml_dictionary/services/ml_dictionary_service.dart';
import 'package:sana_app/features/ml_dictionary/services/report_history_service.dart';

class _CountingHistoryService extends ReportHistoryService {
  int saveCalls = 0;

  @override
  Future<List<ReportHistoryEntry>> load() async => const [];

  @override
  Future<ReportHistoryEntry> save({
    required String sourceName,
    required List<ParsedLabResult> results,
    DateTime? reportDate,
  }) async {
    saveCalls++;
    return ReportHistoryEntry(
      id: '$saveCalls',
      createdAt: DateTime(2026, 3, 12),
      sourceName: sourceName,
      results: results,
    );
  }
}

class _EchoService extends MlDictionaryService {
  String? lastParsedText;

  @override
  Future<List<TermSummary>> getTerms() async => const [
    TermSummary(labTest: 'CRP', title: 'C-Reaktif Protein', sections: []),
  ];

  @override
  Future<ReportParseResponse> parseReport(String text) async {
    lastParsedText = text;
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
      disclaimer: 'Bu bir teşhis değildir.',
    );
  }
}

/// Ekranın kullandığı OCR servisini taklit eder.
class _StubOcrService extends LocalOcrService {
  _StubOcrService({this.text, this.error});

  final String? text;
  final OcrException? error;
  final List<OcrSource> scanned = [];

  // Widget testleri global platform değişkenine dokunmasın diye desteklenme
  // durumu doğrudan bildiriliyor.
  @override
  bool get isSupported => true;

  @override
  Future<String> scan(OcrSource source) async {
    scanned.add(source);
    if (error != null) throw error!;
    return text!;
  }
}

Future<void> pumpScreen(
  WidgetTester tester, {
  required LocalOcrService ocr,
  MlDictionaryService? service,
  ReportHistoryService? history,
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: ReportParseScreen(
        service: service ?? _EchoService(),
        historyService: history ?? _CountingHistoryService(),
        ocrService: ocr,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('kamera ve galeri girişleri sunulur', (tester) async {
    await pumpScreen(tester, ocr: _StubOcrService(text: 'CRP 13.5 mg/L'));

    expect(find.text('PDF yükle'), findsOneWidget);
    expect(find.text('Kamerayla çek'), findsOneWidget);
    expect(find.text('Galeriden seç'), findsOneWidget);
    expect(find.text('Metin yapıştır'), findsOneWidget);
  });

  testWidgets('OCR metni düzenlenebilir alana düşer ve kaydedilmez', (
    tester,
  ) async {
    final history = _CountingHistoryService();
    await pumpScreen(
      tester,
      ocr: _StubOcrService(text: 'CRP 13.5 mg/L'),
      history: history,
    );

    await tester.tap(find.text('Kamerayla çek'));
    await tester.pumpAndSettle();

    // Metin düzenlenebilir alanda görünür olmalı.
    expect(find.widgetWithText(TextField, 'CRP 13.5 mg/L'), findsOneWidget);
    // OCR'ın hata yapabileceği açıkça söylenmeli.
    expect(find.textContaining('Kamera okuması hata yapabilir'), findsOneWidget);
    // Ve hiçbir şey kaydedilmemiş olmalı.
    expect(history.saveCalls, 0);
  });

  testWidgets('görüntünün saklanmadığı kullanıcıya söylenir', (tester) async {
    await pumpScreen(tester, ocr: _StubOcrService(text: 'CRP 13.5 mg/L'));

    await tester.tap(find.text('Galeriden seç'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Görüntü saklanmadı'), findsOneWidget);
  });

  testWidgets('düzeltilen OCR metni ayrıştırmaya gider', (tester) async {
    final service = _EchoService();
    await pumpScreen(
      tester,
      ocr: _StubOcrService(text: 'CRP l3.5 mg/L'), // OCR 1'i l okumuş
      service: service,
    );

    await tester.tap(find.text('Kamerayla çek'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'CRP 13.5 mg/L');
    await tester.tap(find.text('Metni tara'));
    await tester.pumpAndSettle();

    // Ayrıştırıcıya kullanıcının düzelttiği metin gitmeli.
    expect(service.lastParsedText, 'CRP 13.5 mg/L');
    // Ve yine onay ekranı açılmalı.
    expect(find.text('Değerleri kontrol et'), findsOneWidget);
  });

  testWidgets('kullanıcı vazgeçerse hata gösterilmez', (tester) async {
    await pumpScreen(
      tester,
      ocr: _StubOcrService(
        error: const OcrException(OcrFailure.cancelled, 'Görüntü seçilmedi.'),
      ),
    );

    await tester.tap(find.text('Kamerayla çek'));
    await tester.pumpAndSettle();

    expect(find.text('Görüntü seçilmedi.'), findsNothing);
  });

  testWidgets('izin reddedilince çökmez, Ayarlar mesajı gösterilir', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      ocr: _StubOcrService(
        error: const OcrException(
          OcrFailure.permissionDenied,
          'Kamera izni verilmedi. Telefon ayarlarından Sana uygulamasına '
          'kamera izni verip tekrar deneyebilirsin.',
        ),
      ),
    );

    await tester.tap(find.text('Kamerayla çek'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Kamera izni verilmedi'), findsOneWidget);
    expect(find.textContaining('ayarlarından'), findsOneWidget);
  });

  testWidgets('yazı bulunamazsa açık mesaj gösterilir', (tester) async {
    await pumpScreen(
      tester,
      ocr: _StubOcrService(
        error: const OcrException(
          OcrFailure.noText,
          'Görüntüde okunabilir yazı bulunamadı. Daha yakından ve iyi ışıkta '
          'tekrar deneyin.',
        ),
      ),
    );

    await tester.tap(find.text('Galeriden seç'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('okunabilir yazı bulunamadı'), findsOneWidget);
  });

  testWidgets('galeri butonu galeri kaynağını ister', (tester) async {
    final ocr = _StubOcrService(text: 'CRP 13.5 mg/L');
    await pumpScreen(tester, ocr: ocr);

    await tester.tap(find.text('Galeriden seç'));
    await tester.pumpAndSettle();

    expect(ocr.scanned, [OcrSource.gallery]);
  });
}
