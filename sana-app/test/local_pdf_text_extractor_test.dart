// Cihaz üzerinde PDF metin çıkarma sözleşmesi.
//
// Hiçbir test ağa, backend'e veya harici servise gitmez. Örnek PDF'ler testin
// içinde `pdf` paketiyle üretilir, böylece ikili dosya deposuna girmez.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sana_app/features/ml_dictionary/services/local_pdf_text_extractor.dart';

/// Metin katmanı olan gerçek bir PDF üretir.
Future<Uint8List> buildTextPdf(String body) async {
  final document = pw.Document();
  document.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (_) => pw.Text(body),
    ),
  );
  return document.save();
}

/// Metin katmanı olmayan (yalnız çizim içeren) PDF — taranmış belgeyi temsil
/// eder: geçerli PDF ama çıkarılabilir metni yok.
Future<Uint8List> buildImageOnlyPdf() async {
  final document = pw.Document();
  document.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (_) => pw.Container(
        width: 200,
        height: 120,
        color: PdfColors.grey400,
      ),
    ),
  );
  return document.save();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const extractor = LocalPdfTextExtractor();

  group('metin katmanlı PDF', () {
    test('metin cihaz üzerinde çıkarılır', () async {
      final bytes = await buildTextPdf('CRP 13.5 mg/L');

      final text = await extractor.extractText(bytes);

      expect(text, contains('CRP'));
      expect(text, contains('13.5'));
    });

    test('çok satırlı rapor metni korunur', () async {
      final bytes = await buildTextPdf(
        'Hemoglobin 14.2 g/dL\nGlukoz 92 mg/dL',
      );

      final text = await extractor.extractText(bytes);

      expect(text, contains('Hemoglobin'));
      expect(text, contains('Glukoz'));
    });
  });

  group('kontrollü retler', () {
    test('boş dosya', () async {
      await expectLater(
        extractor.extractText(Uint8List(0)),
        throwsA(
          isA<PdfExtractionException>().having(
            (error) => error.reason,
            'reason',
            PdfExtractionFailure.empty,
          ),
        ),
      );
    });

    test('10 MB üzeri dosya okunmadan reddedilir', () async {
      final tooBig = Uint8List(LocalPdfTextExtractor.maxBytes + 1);

      await expectLater(
        extractor.extractText(tooBig),
        throwsA(
          isA<PdfExtractionException>().having(
            (error) => error.reason,
            'reason',
            PdfExtractionFailure.tooLarge,
          ),
        ),
      );
    });

    test('bozuk dosya kontrollü hata verir', () async {
      final garbage = Uint8List.fromList(
        List<int>.generate(2048, (index) => index % 256),
      );

      await expectLater(
        extractor.extractText(garbage),
        throwsA(
          isA<PdfExtractionException>().having(
            (error) => error.reason,
            'reason',
            PdfExtractionFailure.corrupt,
          ),
        ),
      );
    });

    test('kesilmiş PDF kontrollü hata verir', () async {
      final full = await buildTextPdf('CRP 13.5 mg/L');
      final truncated = Uint8List.sublistView(full, 0, full.length ~/ 2);

      await expectLater(
        extractor.extractText(truncated),
        throwsA(isA<PdfExtractionException>()),
      );
    });

    test('parola korumalı PDF kontrollü hata verir', () async {
      final encrypted = _buildEncryptedPdf();

      await expectLater(
        extractor.extractText(encrypted),
        throwsA(
          isA<PdfExtractionException>().having(
            (error) => error.reason,
            'reason',
            PdfExtractionFailure.encrypted,
          ),
        ),
      );
    });
  });

  group('taranmış PDF', () {
    test('metin katmanı yoksa OCR önerilir, sonuç gizlenmez', () async {
      final bytes = await buildImageOnlyPdf();

      try {
        await extractor.extractText(bytes);
        fail('taranmış PDF sessizce başarılı sayılmamalı');
      } on PdfExtractionException catch (error) {
        expect(error.reason, PdfExtractionFailure.noTextLayer);
        expect(error.suggestsOcr, isTrue);
        expect(error.message, contains('taranmış'));
        expect(error.message.toLowerCase(), contains('kamera'));
      }
    });
  });

  group('gizlilik', () {
    test('hata mesajları teknik ayrıntı sızdırmaz', () async {
      final garbage = Uint8List.fromList([1, 2, 3, 4, 5]);

      try {
        await extractor.extractText(garbage);
        fail('hata bekleniyordu');
      } on PdfExtractionException catch (error) {
        // Kullanıcıya dosya yolu, sınıf adı veya yığın izi gösterilmemeli.
        expect(error.message, isNot(contains('Exception')));
        expect(error.message, isNot(contains('#0')));
        expect(error.message, isNot(contains(r'\')));
        expect(error.message, isNot(contains('.dart')));
      }
    });
  });
}

/// Parola korumalı, yapısal olarak geçerli bir PDF üretir.
///
/// `pdf` paketinin `PdfEncryption` sınıfı soyut olduğu için şifreli belge
/// üretemiyor. Geçerli bir belgeye yalnız `/Encrypt` referansı eklemek de
/// yetmedi: sallantıdaki referans yok sayılıp belge açıldı. Bu yüzden standart
/// güvenlik işleyicisinin tüm zorunlu alanlarını (`/Filter /Standard`, `/V`,
/// `/R`, 32 baytlık `/O` ve `/U`, `/P`) taşıyan eksiksiz bir sözlük kuruluyor;
/// xref uzaklıkları da hesaplanıyor ki belge gerçekten ayrıştırılabilsin.
Uint8List _buildEncryptedPdf() {
  final objects = <String>[
    '<</Type/Catalog/Pages 2 0 R>>',
    '<</Type/Pages/Kids[3 0 R]/Count 1>>',
    '<</Type/Page/Parent 2 0 R/MediaBox[0 0 612 792]>>',
    // R2 (RC4 40-bit) sahibi/kullanıcı parolası alanları 32 bayt olmak
    // zorundadır; içerik önemli değil, uzunluk önemli.
    '<</Filter/Standard/V 1/R 2'
        '/O <${'AB' * 32}>'
        '/U <${'CD' * 32}>'
        '/P -1>>',
  ];

  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var index = 0; index < objects.length; index++) {
    offsets.add(buffer.length);
    buffer.write('${index + 1} 0 obj\n${objects[index]}\nendobj\n');
  }

  final xrefOffset = buffer.length;
  buffer.write('xref\n0 ${objects.length + 1}\n');
  buffer.write('0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer.write(
    'trailer\n'
    '<</Size ${objects.length + 1}/Root 1 0 R/Encrypt 4 0 R'
    '/ID[<${'11' * 16}><${'22' * 16}>]>>\n'
    'startxref\n$xrefOffset\n%%EOF\n',
  );

  return Uint8List.fromList(buffer.toString().codeUnits);
}
