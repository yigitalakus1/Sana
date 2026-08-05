import 'dart:typed_data';

import '../../../core/network/sana_api_client.dart';
import '../../../core/profile/user_profile_service.dart';
import '../models/chat_models.dart';
import '../models/explain_response.dart';
import '../models/report_parse_models.dart';
import '../models/term_models.dart';

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
  }) : _client = client ?? SanaApiClient(),
       _profileService = profileService ?? UserProfileService();

  final SanaApiClient _client;
  final UserProfileService _profileService;

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
    final list = await _client.getTerms();
    return list
        .whereType<Map>()
        .map((e) => TermSummary.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<TermDetail> getTermDetail(String labTest) async {
    final json = await _client.getTermDetail(labTest);
    return TermDetail.fromJson(json);
  }

  Future<ReportParseResponse> parseReport(String text) async {
    final json = await _client.parseReport(text);
    return ReportParseResponse.fromJson(json);
  }

  Future<ReportParseResponse> parsePdfReport({
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
