// PDF çıktısının sözleşmesi: geçerli bir belge üretilir, boş geçmişte belge
// yazılmaz ve raporda olmayan bilgi uydurulmaz.

import 'package:flutter_test/flutter_test.dart';
import 'package:sana_app/features/ml_dictionary/models/report_parse_models.dart';
import 'package:sana_app/features/ml_dictionary/services/report_pdf_service.dart';

ParsedLabResult _result({
  String labTest = 'Hemoglobin',
  String? rawValue = '14.2',
  String? unit = 'g/dL',
  String? referenceRange = '12.0-16.0',
  String? interpretation = 'normal',
}) => ParsedLabResult(
  labTest: labTest,
  rawValue: rawValue,
  unit: unit,
  referenceRange: referenceRange,
  interpretation: interpretation,
);

ReportHistoryEntry _entry({
  String id = '1',
  String sourceName = 'tahlil.pdf',
  String? label,
  DateTime? reportDate,
  List<ParsedLabResult>? results,
}) => ReportHistoryEntry(
  id: id,
  createdAt: DateTime(2026, 3, 12, 9, 30),
  sourceName: sourceName,
  label: label,
  reportDate: reportDate,
  results: results ?? [_result()],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('reportPdfStatus', () {
    test('backend etiketlerini Türkçe karşılığına çevirir', () {
      expect(reportPdfStatus('normal').label, 'Aralık içinde');
      expect(reportPdfStatus('high').label, 'Yüksek');
      expect(reportPdfStatus('low').label, 'Düşük');
    });

    test('yorum yoksa sınıflandırma uydurmaz', () {
      // Raporda referans aralığı olmadığında backend interpretation
      // döndürmez; belge bunu "normal" gibi göstermemeli.
      expect(reportPdfStatus(null).label, 'Aralık verilmemiş');
      expect(reportPdfStatus('').label, 'Aralık verilmemiş');
      expect(reportPdfStatus('beklenmeyen').label, 'Aralık verilmemiş');
    });

    test('hiçbir durum kırmızı ile gösterilmez', () {
      for (final key in [null, 'normal', 'high', 'low', 'bilinmeyen']) {
        final color = reportPdfStatus(key).color;
        expect(
          color.red > 0.8 && color.green < 0.4 && color.blue < 0.4,
          isFalse,
          reason: '$key için alarmcı kırmızı kullanılmamalı',
        );
      }
    });
  });

  group('formatMeasuredValue', () {
    test('değer ve birimi birleştirir', () {
      expect(formatMeasuredValue(_result()), '14.2 g/dL');
    });

    test('birim yoksa yalnız değeri yazar', () {
      expect(formatMeasuredValue(_result(unit: null)), '14.2');
    });

    test('değer yoksa boş döner', () {
      expect(formatMeasuredValue(_result(rawValue: null, unit: null)), '');
    });
  });

  test('formatReportDate gün.ay.yıl biçiminde yazar', () {
    expect(formatReportDate(DateTime(2026, 3, 5)), '05.03.2026');
  });

  group('ReportPdfService.build', () {
    setUp(ReportPdfService.resetFontCache);

    test('geçerli bir PDF belgesi üretir', () async {
      final bytes = await ReportPdfService().build([_entry()]);

      expect(bytes.length, greaterThan(1000));
      expect(
        String.fromCharCodes(bytes.take(5)),
        '%PDF-',
        reason: 'çıktı gerçek bir PDF olmalı',
      );
      expect(
        String.fromCharCodes(bytes.skip(bytes.length - 8)),
        contains('EOF'),
        reason: 'belge eksiksiz kapanmalı',
      );
    });

    test('rapor yoksa boş belge yazmaz', () async {
      expect(
        () => ReportPdfService().build([]),
        throwsA(isA<ReportPdfEmptyException>()),
      );
    });

    test('birden çok rapor tek belgede toplanır', () async {
      final single = await ReportPdfService().build([_entry()]);
      final many = await ReportPdfService().build([
        _entry(id: '1'),
        _entry(id: '2', label: 'Kontrol'),
        _entry(id: '3', reportDate: DateTime(2026, 1, 4)),
      ]);

      expect(many.length, greaterThan(single.length));
    });

    // Regresyon: rapor bölümü tek bir Container'a sarılıydı. Container
    // bölünemediği için sayfaya sığmayan rapor MultiPage'i ilerletemiyor,
    // boş sayfa üretip TooManyPagesException atıyordu — web'de uygulama
    // donmuş görünüyordu. Tablo üst düzey çocuk olmalı ki bölünebilsin.
    test('sayfaya sığmayan rapor belgeyi kilitlemez', () async {
      final entry = ReportHistoryEntry(
        id: 'buyuk',
        createdAt: DateTime(2026, 3, 12),
        sourceName: 'buyuk.pdf',
        results: List.generate(
          60,
          (index) => _result(labTest: 'Tahlil $index'),
        ),
      );

      final bytes = await ReportPdfService().build([entry]);

      expect(bytes.length, greaterThan(1000));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('çok sayıda rapor ve değer birlikte de üretilir', () async {
      final entries = List.generate(
        12,
        (index) => _entry(
          id: 'r$index',
          sourceName: 'rapor-$index.pdf',
          results: List.generate(
            25,
            (inner) => _result(labTest: 'Tahlil $inner'),
          ),
        ),
      );

      final bytes = await ReportPdfService().build(entries);

      expect(bytes.length, greaterThan(1000));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('eksik alanlı rapor belgeyi bozmaz', () async {
      final bytes = await ReportPdfService().build([
        _entry(
          results: [
            _result(
              rawValue: null,
              unit: null,
              referenceRange: null,
              interpretation: null,
            ),
          ],
        ),
      ]);

      expect(bytes.length, greaterThan(1000));
    });
  });
}
