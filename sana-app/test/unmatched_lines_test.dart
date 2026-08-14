// Eşleşmeyen satırlar sessizce yutulmaz.
//
// Kamera okumasında tek harf yanlış tanınınca ("HbA1c" → "Hba1e") satır
// ayrıştırıcıdan düşer. Kullanıcının bunu görmesi gerekir; aksi hâlde raporda
// olan bir değer sessizce kaybolur.
//
// Aynı zamanda gürültü testi: hasta adı, protokol numarası ve tarih gibi
// satırlar uyarıya girmemeli, yoksa uyarı işe yaramaz hâle gelir.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sana_app/features/ml_dictionary/models/report_parse_models.dart';
import 'package:sana_app/features/ml_dictionary/screens/report_confirm_screen.dart';
import 'package:sana_app/features/ml_dictionary/services/local_report_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final parser = LocalReportParser();

  test('tanınmayan ölçüm satırı bildirilir', () async {
    final response = await parser.parse(
      'CRP 13.5 mg/L\n'
      'Hba1e 6.2 %\n', // OCR "HbA1c" yerine "Hba1e" okumuş
    );

    expect(response.results, isNotEmpty);
    expect(
      response.unmatchedLines,
      contains('Hba1e 6.2 %'),
      reason: 'eşleşmeyen ölçüm satırı sessizce kaybolmamalı',
    );
  });

  test('eşleşen satırlar uyarıya girmez', () async {
    final response = await parser.parse('CRP 13.5 mg/L');

    expect(response.results, isNotEmpty);
    expect(response.unmatchedLines, isEmpty);
  });

  group('gürültü elenir', () {
    test('tarih satırı uyarıya girmez', () async {
      final response = await parser.parse(
        'Rapor Tarihi: 12.03.2026\nCRP 13.5 mg/L',
      );

      expect(
        response.unmatchedLines.any((line) => line.contains('12.03.2026')),
        isFalse,
      );
    });

    test('protokol/kimlik numarası uyarıya girmez', () async {
      final response = await parser.parse(
        'Protokol No: 202603120001\nCRP 13.5 mg/L',
      );

      expect(
        response.unmatchedLines.any((line) => line.contains('Protokol')),
        isFalse,
      );
    });

    test('rakamsız başlık satırı uyarıya girmez', () async {
      final response = await parser.parse(
        'BİYOKİMYA SONUÇLARI\nCRP 13.5 mg/L',
      );

      expect(response.unmatchedLines, isEmpty);
    });

    test('kelimesiz sayı satırı uyarıya girmez', () async {
      final response = await parser.parse('12345\nCRP 13.5 mg/L');

      expect(response.unmatchedLines, isEmpty);
    });
  });

  test('çok satırlı eşleşmenin değer satırı uyarıya girmez', () async {
    // Tahlil adı bir satırda, değeri altındaki satırda.
    final response = await parser.parse('CRP\n13.5 mg/L');

    expect(response.results, isNotEmpty);
    expect(response.unmatchedLines, isEmpty);
  });

  testWidgets('onay ekranı tanınmayan satırları gösterir', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: ReportConfirmScreen(
          results: [
            ParsedLabResult(labTest: 'CRP', rawValue: '13.5', unit: 'mg/L'),
          ],
          sourceName: 'tahlil.pdf',
          unmatchedLines: ['Hba1e 6.2 %', 'Vitamn D 18 ng/mL'],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bu satırlar tanınamadı'), findsOneWidget);
    expect(find.textContaining('Hba1e 6.2 %'), findsOneWidget);
    expect(find.textContaining('Vitamn D 18 ng/mL'), findsOneWidget);
    expect(find.textContaining('Sessizce atlanmadılar'), findsOneWidget);
  });

  testWidgets('tanınmayan satır yoksa uyarı gösterilmez', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ReportConfirmScreen(
          results: [
            ParsedLabResult(labTest: 'CRP', rawValue: '13.5', unit: 'mg/L'),
          ],
          sourceName: 'tahlil.pdf',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bu satırlar tanınamadı'), findsNothing);
  });
}
