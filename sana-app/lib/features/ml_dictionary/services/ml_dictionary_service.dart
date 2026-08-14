import 'dart:typed_data';

import '../../../core/network/sana_api_client.dart';
import '../../../core/profile/user_profile_service.dart';
import '../models/chat_models.dart';
import '../models/explain_response.dart';
import '../models/report_parse_models.dart';
import '../models/term_models.dart';
import 'local_pdf_text_extractor.dart';
import 'local_term_repository.dart';
import 'local_report_parser.dart';

/// Backend istemcisini saran sözlük/açıklama servisi.
///
/// Açıklama akışı `/explain` üzerinden çalışır (`/query` KULLANILMAZ).
/// Ağ hataları `SanaApiException` olarak yukarı taşınır; UI bunları kullanıcı
/// dostu mesaja çevirir. `healthCheck` ise hata yutar ve `false` döner, böylece
/// ana ekran backend kapalıyken de çökmez.
class MlDictionaryService {
  MlDictionaryService({
    SanaApiClient? client,
    UserProfileService? profileService,
    LocalTermRepository? localTerms,
    LocalReportParser? localReportParser,
    LocalPdfTextExtractor? pdfExtractor,
  }) : _client = client ?? SanaApiClient(),
       _profileService = profileService ?? UserProfileService(),
       _localTerms = localTerms ?? LocalTermRepository(),
       _localReportParser = localReportParser,
       _pdfExtractor = pdfExtractor ?? const LocalPdfTextExtractor();

  final SanaApiClient _client;
  final UserProfileService _profileService;
  final LocalTermRepository _localTerms;
  final LocalPdfTextExtractor _pdfExtractor;
  LocalReportParser? _localReportParser;

  Future<bool> healthCheck() async {
    try {
      final res = await _client.health();
      return res['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  /// [useSourceText] açıkken cevap yerel modelle yeniden ifade edilmez;
  /// backend onaylı kaynak metnini doğrudan döndürür. Sözlükteki hazır bölüm
  /// açıklamalarında beklemeyi ortadan kaldırır.
  Future<ExplainResponse> explainLab({
    required String question,
    String? labTest,
    bool useSourceText = false,
  }) async {
    final profile = await _profileService.load();
    final json = await _client.explain(
      question: question,
      labTest: labTest,
      profile: profile.isEmpty ? null : profile.toJson(),
      useSourceText: useSourceText,
    );
    return ExplainResponse.fromJson(json);
  }

  Future<List<TermSummary>> getTerms() async {
    try {
      return await _localTerms.getTerms();
    } catch (_) {
      final list = await _client.getTerms();
      return list
          .whereType<Map>()
          .map((e) => TermSummary.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
  }

  Future<TermDetail> getTermDetail(String labTest) async {
    try {
      final local = await _localTerms.getTermDetail(labTest);
      if (local != null) return local;
    } catch (_) {
      // A missing/corrupt asset falls back to the existing public API.
    }
    final json = await _client.getTermDetail(labTest);
    return TermDetail.fromJson(json);
  }

  Future<ReportParseResponse> parseReport(String text) async {
    try {
      final parser = _localReportParser ??= LocalReportParser(
        terms: _localTerms,
      );
      return await parser.parse(text);
    } catch (_) {
      final json = await _client.parseReport(text);
      return ReportParseResponse.fromJson(json);
    }
  }

  /// PDF raporunu **önce cihaz üzerinde** çözmeye çalışır.
  ///
  /// Metin katmanı varsa metin cihazda çıkarılır, cihazdaki parser'a verilir ve
  /// backend'e hiç gidilmez — sağlık verisi cihazdan çıkmaz.
  ///
  /// Kontrollü hatalar ([PdfExtractionException]) backend'e düşmez: parola
  /// korumalı, bozuk, boş, çok büyük ya da taranmış PDF'te kullanıcıya durumu
  /// söylemek, sessizce sunucuya veri göndermekten doğrudur. Yalnız beklenmedik
  /// bir hata olduğunda, geçiş süresi boyunca eski backend yolu denenir.
  Future<ReportParseResponse> parsePdfReport({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final String text;
    try {
      text = await _pdfExtractor.extractText(bytes);
    } on PdfExtractionException {
      rethrow;
    } catch (_) {
      return _parsePdfViaBackend(fileName: fileName, bytes: bytes);
    }

    try {
      final parser = _localReportParser ??= LocalReportParser(
        terms: _localTerms,
      );
      return await parser.parse(text);
    } catch (_) {
      return _parsePdfViaBackend(fileName: fileName, bytes: bytes);
    }
  }

  /// Eski backend yolu; yalnız yerel çözüm beklenmedik biçimde başarısızsa.
  Future<ReportParseResponse> _parsePdfViaBackend({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final json = await _client.parsePdfReport(fileName: fileName, bytes: bytes);
    return ReportParseResponse.fromJson(json);
  }

  Future<ChatResponse> chat({
    required List<ChatMessage> messages,
    String? labTest,
  }) => _client.chat(messages: messages, labTest: labTest);
}
