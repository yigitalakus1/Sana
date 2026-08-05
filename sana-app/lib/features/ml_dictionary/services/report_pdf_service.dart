// Rapor geçmişini doktora gösterilebilecek okunur bir PDF'e çevirir.
//
// JSON dışa aktarma (`ReportHistoryService.exportJson`) yedekleme içindir ve
// geri yüklenebilir; bu servis ise **okunur çıktı** üretir ve geri alınamaz.
// İkisi ayrı ihtiyaçlardır, birbirinin yerine geçmez.
//
// Belge yalnız raporda fiilen bulunan bilgiyi yazar: ölçülen değer, raporun
// kendi referans aralığı ve bu aralığa göre hesaplanan durum. Yorum, teşhis
// veya öneri üretilmez; aralık yoksa durum "Aralık verilmemiş" kalır.

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/report_parse_models.dart';

/// Belgenin her sayfasında görünen sorumluluk reddi.
const String kReportPdfDisclaimer =
    'Bu belge bir teşhis veya tıbbi görüş değildir. Tahlil değerlerinin sade '
    'bir dökümüdür; değerlendirme hekiminize aittir.';

class _Palette {
  static const brand = PdfColor.fromInt(0xFF0E9384);
  static const text = PdfColor.fromInt(0xFF101828);
  static const muted = PdfColor.fromInt(0xFF667085);
  static const border = PdfColor.fromInt(0xFFE4E7EC);
  static const softBg = PdfColor.fromInt(0xFFF9FAFB);

  // Uygulamadaki durum renkleriyle aynı; kırmızı bilinçli olarak yok.
  static const inRange = PdfColor.fromInt(0xFF12B76A);
  static const above = PdfColor.fromInt(0xFFF79009);
  static const below = PdfColor.fromInt(0xFF2E90FA);
  static const unknown = PdfColor.fromInt(0xFF98A2B3);
}

/// `interpretation` alanının görünen karşılığı. Değer yoksa uydurma
/// sınıflandırma yapılmaz — belgede "Aralık verilmemiş" yazar.
({String label, PdfColor color}) reportPdfStatus(String? interpretation) =>
    switch (interpretation) {
      'normal' => (label: 'Aralık içinde', color: _Palette.inRange),
      'high' => (label: 'Yüksek', color: _Palette.above),
      'low' => (label: 'Düşük', color: _Palette.below),
      _ => (label: 'Aralık verilmemiş', color: _Palette.unknown),
    };

String _two(int value) => value.toString().padLeft(2, '0');

String formatReportDate(DateTime date) =>
    '${_two(date.day)}.${_two(date.month)}.${date.year}';

String _formatDateTime(DateTime value) =>
    '${formatReportDate(value)} ${_two(value.hour)}:${_two(value.minute)}';

/// Ölçülen değer + birim. Raporda değer yoksa boş döner.
String formatMeasuredValue(ParsedLabResult result) => [
  if (result.rawValue != null && result.rawValue!.trim().isNotEmpty)
    result.rawValue!.trim(),
  if (result.unit != null && result.unit!.trim().isNotEmpty)
    result.unit!.trim(),
].join(' ');

class ReportPdfService {
  /// Gömülü yazı tipi. Varsayılan PDF yazı tipleri `ş/ğ/ı/İ` gliflerini
  /// içermediği için Türkçe metin bozuk çıkıyordu; font gömmek zorunlu.
  static Future<({pw.Font regular, pw.Font semiBold})>? _fontsFuture;

  static Future<({pw.Font regular, pw.Font semiBold})> _fonts() {
    final pending = _fontsFuture;
    if (pending != null) return pending;

    final future = () async {
      final regular = await rootBundle.load(
        'assets/fonts/HankenGrotesk-Regular.ttf',
      );
      final semiBold = await rootBundle.load(
        'assets/fonts/HankenGrotesk-SemiBold.ttf',
      );
      return (regular: pw.Font.ttf(regular), semiBold: pw.Font.ttf(semiBold));
    }();
    _fontsFuture = future;

    // Yükleme başarısızsa önbellek temizlenir; aksi hâlde bir kerelik hata
    // kalıcı olur ve kullanıcı tekrar denese de hep aynı hatayı alır.
    future.then<void>((_) {}, onError: (Object _) => _fontsFuture = null);
    return future;
  }

  /// Testlerde font önbelleğini sıfırlamak için.
  static void resetFontCache() => _fontsFuture = null;

  /// Verilen raporlardan tek bir PDF üretir. Liste boşsa
  /// [ReportPdfEmptyException] atar; boş belge yazılmaz.
  Future<Uint8List> build(
    List<ReportHistoryEntry> entries, {
    DateTime? generatedAt,
  }) async {
    if (entries.isEmpty) {
      throw const ReportPdfEmptyException(
        'Dışa aktarılacak rapor bulunamadı.',
      );
    }

    final fonts = await _fonts();
    final createdAt = generatedAt ?? DateTime.now();
    final document = pw.Document(
      title: 'Sana - Tahlil Rapor Özeti',
      subject: kReportPdfDisclaimer,
    );

    document.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 28),
          theme: pw.ThemeData.withFont(
            base: fonts.regular,
            bold: fonts.semiBold,
          ),
        ),
        header: (context) =>
            context.pageNumber == 1 ? _header(createdAt) : _runningHeader(),
        footer: _footer,
        build: (context) => [
          _intro(entries),
          for (final entry in entries) ..._section(entry),
        ],
      ),
    );

    return document.save();
  }

  // --- Parçalar -----------------------------------------------------------

  pw.Widget _header(DateTime createdAt) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Row(
              children: [
                pw.Container(
                  width: 18,
                  height: 18,
                  decoration: pw.BoxDecoration(
                    shape: pw.BoxShape.circle,
                    border: pw.Border.all(color: _Palette.brand, width: 2),
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Text(
                  'sana',
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: _Palette.brand,
                  ),
                ),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'Tahlil Rapor Özeti',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: _Palette.text,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'Oluşturulma: ${_formatDateTime(createdAt)}',
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: _Palette.muted,
                  ),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Divider(color: _Palette.border, height: 1, thickness: 1),
        pw.SizedBox(height: 14),
      ],
    );
  }

  pw.Widget _runningHeader() => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 12),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'sana',
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            color: _Palette.brand,
          ),
        ),
        pw.Text(
          'Tahlil Rapor Özeti',
          style: const pw.TextStyle(fontSize: 9, color: _Palette.muted),
        ),
      ],
    ),
  );

  pw.Widget _intro(List<ReportHistoryEntry> entries) {
    final valueCount = entries.fold<int>(
      0,
      (total, entry) => total + entry.results.length,
    );
    final outOfRange = entries.fold<int>(
      0,
      (total, entry) =>
          total +
          entry.results
              .where(
                (result) =>
                    result.interpretation == 'high' ||
                    result.interpretation == 'low',
              )
              .length,
    );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: _Palette.softBg,
            border: pw.Border.all(color: _Palette.border),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                '${entries.length} rapor · $valueCount değer'
                '${outOfRange > 0 ? ' · $outOfRange değer referans aralığının dışında' : ''}',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: _Palette.text,
                ),
              ),
              pw.SizedBox(height: 5),
              pw.Text(
                kReportPdfDisclaimer,
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: _Palette.muted,
                  lineSpacing: 2,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 16),
      ],
    );
  }

  /// Bir raporun parçaları, **`MultiPage`'e ayrı ayrı** verilmek üzere.
  ///
  /// Hepsini tek bir `Container`'a sarmak cazip ama bozuk: `Container`
  /// bölünemez, dolayısıyla çok değerli bir rapor sayfaya sığmayınca
  /// `MultiPage` ilerleyemeden boş sayfa üretip `TooManyPagesException`
  /// atıyordu (web'de uygulama donmuş görünüyordu). Tablo doğrudan üst düzey
  /// çocuk olduğunda sayfalar arasında bölünebiliyor.
  List<pw.Widget> _section(ReportHistoryEntry entry) {
    final meta = <String>[
      if (entry.reportDate != null)
        'Rapor tarihi: ${formatReportDate(entry.reportDate!)}'
      else
        'Kayıt: ${formatReportDate(entry.createdAt)}',
      if (entry.hasCustomLabel) 'Dosya: ${entry.sourceName}',
    ];

    return [
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            entry.displayName,
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: _Palette.text,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            meta.join('  ·  '),
            style: const pw.TextStyle(fontSize: 9, color: _Palette.muted),
          ),
          pw.SizedBox(height: 8),
        ],
      ),
      _table(entry.results),
      pw.SizedBox(height: 18),
    ];
  }

  pw.Widget _table(List<ParsedLabResult> results) {
    return pw.Table(
      border: pw.TableBorder.symmetric(
        inside: const pw.BorderSide(color: _Palette.border, width: 0.5),
        outside: const pw.BorderSide(color: _Palette.border, width: 0.5),
      ),
      columnWidths: const {
        0: pw.FlexColumnWidth(3.2),
        1: pw.FlexColumnWidth(2.2),
        2: pw.FlexColumnWidth(2.2),
        3: pw.FlexColumnWidth(2.4),
      },
      children: [
        pw.TableRow(
          // Tablo sayfaya bölündüğünde başlık her sayfada tekrarlansın.
          repeat: true,
          decoration: const pw.BoxDecoration(color: _Palette.softBg),
          children: [
            _headerCell('Tahlil'),
            _headerCell('Sonuç'),
            _headerCell('Referans aralığı'),
            _headerCell('Durum'),
          ],
        ),
        for (final result in results) _row(result),
      ],
    );
  }

  pw.TableRow _row(ParsedLabResult result) {
    final status = reportPdfStatus(result.interpretation);
    final measured = formatMeasuredValue(result);
    return pw.TableRow(
      children: [
        _cell(result.labTest, bold: true),
        _cell(measured.isEmpty ? '—' : measured),
        _cell(result.referenceRange?.trim().isNotEmpty == true
            ? result.referenceRange!.trim()
            : '—'),
        // Durum yalnız renkle anlatılmaz; siyah-beyaz baskıda da okunsun diye
        // metin her zaman yazılır.
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Container(
                width: 6,
                height: 6,
                decoration: pw.BoxDecoration(
                  color: status.color,
                  shape: pw.BoxShape.circle,
                ),
              ),
              pw.SizedBox(width: 5),
              pw.Expanded(
                child: pw.Text(
                  status.label,
                  style: const pw.TextStyle(fontSize: 9.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _headerCell(String text) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 9,
        fontWeight: pw.FontWeight.bold,
        color: _Palette.muted,
      ),
    ),
  );

  pw.Widget _cell(String text, {bool bold = false}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 9.5,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: _Palette.text,
      ),
    ),
  );

  pw.Widget _footer(pw.Context context) => pw.Column(
    children: [
      pw.Divider(color: _Palette.border, height: 1, thickness: 0.5),
      pw.SizedBox(height: 6),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Text(
              kReportPdfDisclaimer,
              style: const pw.TextStyle(fontSize: 7.5, color: _Palette.muted),
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Text(
            'Sayfa ${context.pageNumber} / ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 7.5, color: _Palette.muted),
          ),
        ],
      ),
    ],
  );
}

/// Dışa aktarılacak rapor kalmadığında atılır; mesaj kullanıcıya gösterilir.
class ReportPdfEmptyException implements Exception {
  const ReportPdfEmptyException(this.message);

  final String message;

  @override
  String toString() => message;
}
