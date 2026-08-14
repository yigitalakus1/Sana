// Uçak modu sözleşmesi.
//
// Sözlük, yerel parser, PDF okuma ve OCR internet olmadan çalışmalıdır;
// internet kesildiğinde yalnız Asistan etkilenmelidir.
//
// `_AirplaneModeClient` her ağ metodunda fırlatır. Bu dosyadaki testlerden
// biri ağa çıkarsa kırmızıya döner — "çevrimdışı çalışıyor" iddiası böylece
// yorum değil, doğrulanmış bir davranış olur.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:sana_app/core/network/sana_api_client.dart';
import 'package:sana_app/features/ml_dictionary/models/chat_models.dart';
import 'package:sana_app/features/ml_dictionary/services/local_ocr_service.dart';
import 'package:sana_app/features/ml_dictionary/services/local_pdf_text_extractor.dart';
import 'package:sana_app/features/ml_dictionary/services/ml_dictionary_service.dart';

import 'local_pdf_text_extractor_test.dart' show buildTextPdf;

/// İnternetin olmadığı durumu taklit eder: her çağrı bağlantı hatası verir.
class _AirplaneModeClient extends SanaApiClient {
  int attempts = 0;

  Never _offline(String method) {
    attempts++;
    throw SanaApiException('Bağlantı kurulamadı.');
  }

  @override
  Future<Map<String, dynamic>> health() async => _offline('health');

  @override
  Future<List<dynamic>> getTerms() async => _offline('getTerms');

  @override
  Future<Map<String, dynamic>> getTermDetail(String labTest) async =>
      _offline('getTermDetail');

  @override
  Future<Map<String, dynamic>> parseReport(String text) async =>
      _offline('parseReport');

  @override
  Future<Map<String, dynamic>> parsePdfReport({
    required String fileName,
    required Uint8List bytes,
  }) async => _offline('parsePdfReport');

  @override
  Future<Map<String, dynamic>> explain({
    required String question,
    String? labTest,
    Map<String, dynamic>? profile,
    bool includeSources = true,
    bool includeDoctorQuestions = true,
    bool useSourceText = false,
  }) async => _offline('explain');

  @override
  Future<ChatResponse> chat({
    required List<ChatMessage> messages,
    String? labTest,
    bool includeSources = true,
  }) async => _offline('chat');
}

class _OfflineOcrEngine implements OcrEngine {
  @override
  Future<String> recognize(String imagePath) async => 'CRP 13.5 mg/L';

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _AirplaneModeClient client;
  late MlDictionaryService service;

  setUp(() {
    client = _AirplaneModeClient();
    service = MlDictionaryService(client: client);
  });

  group('uçak modunda çalışması gerekenler', () {
    test('tahlil sözlüğü açılır', () async {
      final terms = await service.getTerms();

      expect(terms, isNotEmpty);
      expect(terms.length, greaterThan(100), reason: 'paketli katalog gelmeli');
      expect(client.attempts, 0);
    });

    test('tahlil ayrıntısı ve bölüm açıklamaları gelir', () async {
      final detail = await service.getTermDetail('CRP');

      expect(detail.labTest, 'CRP');
      expect(detail.contentForSection('Nedir?'), isNotNull);
      expect(client.attempts, 0);
    });

    test('yapıştırılan metin ayrıştırılır', () async {
      final response = await service.parseReport('CRP 13.5 mg/L');

      expect(response.results, isNotEmpty);
      expect(response.results.first.labTest, 'CRP');
      expect(client.attempts, 0);
    });

    test('PDF okunur ve ayrıştırılır', () async {
      final bytes = await buildTextPdf('CRP 13.5 mg/L');

      final response = await service.parsePdfReport(
        fileName: 'tahlil.pdf',
        bytes: bytes,
      );

      expect(response.results, isNotEmpty);
      expect(client.attempts, 0);
    });

    test('OCR metni okunur', () async {
      // Görüntü seçimi ve tanıma tamamen cihazda; ağ katmanı hiç devrede değil.
      final ocr = LocalOcrService(
        engine: _OfflineOcrEngine(),
        imageSource: _StaticSource('test_ocr_offline.tmp'),
      );

      final text = await ocr.scan(OcrSource.gallery);
      final response = await service.parseReport(text);

      expect(response.results, isNotEmpty);
      expect(client.attempts, 0);
    });

    test('taranmış PDF uyarısı da çevrimdışı verilir', () async {
      // Kontrollü hata backend'e düşmemeli.
      try {
        await service.parsePdfReport(
          fileName: 'bos.pdf',
          bytes: Uint8List(0),
        );
        fail('kontrollü hata bekleniyordu');
      } on PdfExtractionException catch (error) {
        expect(error.reason, PdfExtractionFailure.empty);
      }
      expect(client.attempts, 0);
    });
  });

  group('yalnız Asistan etkilenir', () {
    test('sohbet internet ister ve kontrollü hata verir', () async {
      await expectLater(
        service.chat(messages: const [ChatMessage(role: 'user', content: 'CRP')]),
        throwsA(isA<SanaApiException>()),
      );
      expect(client.attempts, 1, reason: 'Asistan ağa çıkmayı dener');
    });

    test('Asistan hatası diğer akışları bozmaz', () async {
      try {
        await service.chat(
          messages: const [ChatMessage(role: 'user', content: 'CRP')],
        );
      } catch (_) {
        // beklenen
      }

      // Sözlük ve ayrıştırma etkilenmemeli.
      final terms = await service.getTerms();
      final parsed = await service.parseReport('CRP 13.5 mg/L');

      expect(terms, isNotEmpty);
      expect(parsed.results, isNotEmpty);
    });
  });

  group('kullanıcıya teknik ayrıntı gösterilmez', () {
    test('PDF hataları yol ve yığın izi taşımaz', () async {
      for (final bytes in [
        Uint8List(0),
        Uint8List.fromList([1, 2, 3, 4]),
        Uint8List(LocalPdfTextExtractor.maxBytes + 1),
      ]) {
        try {
          await const LocalPdfTextExtractor().extractText(bytes);
        } on PdfExtractionException catch (error) {
          expect(error.message, isNot(contains('.dart')));
          expect(error.message, isNot(contains('#0')));
          expect(error.message, isNot(contains('Exception')));
          expect(error.message, isNot(contains(r'\')));
          expect(error.message, isNot(contains('/')));
        }
      }
    });

    test('OCR hataları dosya yolu taşımaz', () async {
      final ocr = LocalOcrService(
        engine: _OfflineOcrEngine(),
        imageSource: _ThrowingSource(StateError('C:\\Users\\gizli\\foto.jpg')),
      );

      try {
        await ocr.scan(OcrSource.camera);
        fail('hata bekleniyordu');
      } on OcrException catch (error) {
        expect(error.message, isNot(contains('gizli')));
        expect(error.message, isNot(contains('.jpg')));
        expect(error.message, isNot(contains('Users')));
      }
    });
  });

  test('disclaimer çevrimdışı da döner', () async {
    final response = await service.parseReport('CRP 13.5 mg/L');

    expect(response.disclaimer, isNotEmpty);
    expect(response.disclaimer.toLowerCase(), contains('tanı'));
    expect(response.disclaimer.toLowerCase(), contains('doktor'));
  });
}

class _StaticSource implements OcrImageSource {
  _StaticSource(this.path);
  final String path;

  @override
  Future<String?> pickPath(OcrSource source) async => path;
}

class _ThrowingSource implements OcrImageSource {
  _ThrowingSource(this.error);
  final Object error;

  @override
  Future<String?> pickPath(OcrSource source) async => throw error;
}
