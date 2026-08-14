// PDF akışının gizlilik sözleşmesi: metin katmanı cihazda çözülebiliyorsa
// sağlık verisi hiçbir koşulda backend'e gitmez.
//
// Sahte istemci her ağ metodunda fırlatır; bir çağrı olursa test kırmızıya
// döner. Böylece "backend çağrılmadı" iddiası yorum değil, test edilmiş olur.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sana_app/core/network/sana_api_client.dart';
import 'package:sana_app/features/ml_dictionary/services/local_pdf_text_extractor.dart';
import 'package:sana_app/features/ml_dictionary/services/ml_dictionary_service.dart';

import 'local_pdf_text_extractor_test.dart' show buildTextPdf, buildImageOnlyPdf;

/// Çağrıldığı anda testi düşüren istemci.
class _ForbiddenNetworkClient extends SanaApiClient {
  int calls = 0;

  Never _reject(String method) {
    calls++;
    throw StateError('Ağ kullanılmamalıydı: $method');
  }

  @override
  Future<Map<String, dynamic>> parsePdfReport({
    required String fileName,
    required Uint8List bytes,
  }) async => _reject('parsePdfReport');

  @override
  Future<Map<String, dynamic>> parseReport(String text) async =>
      _reject('parseReport');

  @override
  Future<Map<String, dynamic>> health() async => _reject('health');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ForbiddenNetworkClient client;
  late MlDictionaryService service;

  setUp(() {
    client = _ForbiddenNetworkClient();
    service = MlDictionaryService(client: client);
  });

  test('metin katmanlı PDF cihazda ayrıştırılır, backend çağrılmaz', () async {
    final bytes = await buildTextPdf('CRP 13.5 mg/L');

    final response = await service.parsePdfReport(
      fileName: 'tahlil.pdf',
      bytes: bytes,
    );

    expect(response.parserStatus, 'parsed');
    expect(response.results, isNotEmpty);
    expect(response.results.first.labTest, 'CRP');
    expect(client.calls, 0, reason: 'yerel çözüm başarılıyken ağ kullanılmamalı');
  });

  test('birden çok değer cihazda çözülür', () async {
    final bytes = await buildTextPdf(
      'CRP 13.5 mg/L\nGlukoz 92 mg/dL\nHemoglobin 14.2 g/dL',
    );

    final response = await service.parsePdfReport(
      fileName: 'tahlil.pdf',
      bytes: bytes,
    );

    expect(response.results.length, greaterThanOrEqualTo(2));
    expect(client.calls, 0);
  });

  group('kontrollü hatalar backend’e düşmez', () {
    Future<void> expectLocalFailure(
      Uint8List bytes,
      PdfExtractionFailure reason,
    ) async {
      try {
        await service.parsePdfReport(fileName: 'tahlil.pdf', bytes: bytes);
        fail('kontrollü hata bekleniyordu');
      } on PdfExtractionException catch (error) {
        expect(error.reason, reason);
      }
      // Asıl iddia bu: hata durumunda dosya sunucuya gönderilmedi.
      expect(client.calls, 0);
    }

    test('taranmış PDF', () async {
      await expectLocalFailure(
        await buildImageOnlyPdf(),
        PdfExtractionFailure.noTextLayer,
      );
    });

    test('bozuk PDF', () async {
      await expectLocalFailure(
        Uint8List.fromList(List<int>.generate(1024, (index) => index % 256)),
        PdfExtractionFailure.corrupt,
      );
    });

    test('10 MB üzeri dosya', () async {
      await expectLocalFailure(
        Uint8List(LocalPdfTextExtractor.maxBytes + 1),
        PdfExtractionFailure.tooLarge,
      );
    });

    test('boş dosya', () async {
      await expectLocalFailure(Uint8List(0), PdfExtractionFailure.empty);
    });
  });

  test('yapıştırılan metin de cihazda çözülür', () async {
    final response = await service.parseReport('CRP 13.5 mg/L');

    expect(response.results, isNotEmpty);
    expect(client.calls, 0);
  });
}
