import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../../features/ml_dictionary/models/chat_models.dart';

/// Backend hatalarını UI'a taşınabilir, kullanıcı dostu bir biçimde sarar.
class SanaApiException implements Exception {
  SanaApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'SanaApiException(${statusCode ?? '-'}): $message';
}

/// Sana backend'ine HTTP istekleri atan ince istemci.
///
/// Yalnız non-diagnostic public endpointleri çağırır. `/query` KULLANILMAZ;
/// ana açıklama endpoint'i `/explain`'dir.
class SanaApiClient {
  SanaApiClient({http.Client? client, Duration? timeout, Duration? llmTimeout})
    : _client = client ?? http.Client(),
      _timeout = timeout ?? const Duration(seconds: 10),
      _llmTimeout = llmTimeout ?? const Duration(seconds: 150);

  final http.Client _client;
  final Duration _timeout;
  final Duration _llmTimeout;

  Uri _uri(String path) => Uri.parse('${ApiConfig.baseUrl}$path');

  static const Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  Future<Map<String, dynamic>> health() => _getObject('/health');

  Future<Map<String, dynamic>> explain({
    required String question,
    String? labTest,
    Map<String, dynamic>? profile,
    bool includeSources = true,
    bool includeDoctorQuestions = true,
    bool useSourceText = false,
  }) {
    final body = <String, dynamic>{
      'question': question,
      if (labTest != null && labTest.isNotEmpty) 'lab_test': labTest,
      if (profile != null && profile.isNotEmpty) 'profile': profile,
      'options': <String, dynamic>{
        'language': 'tr',
        'include_sources': includeSources,
        'include_doctor_questions': includeDoctorQuestions,
        'use_source_text': useSourceText,
      },
    };
    return _postObject('/explain', body, timeout: _llmTimeout);
  }

  Future<List<dynamic>> getTerms() async {
    final decoded = await _get('/terms');
    if (decoded is List) return decoded;
    throw SanaApiException('Beklenmeyen yanıt biçimi (/terms).');
  }

  Future<Map<String, dynamic>> getTermDetail(String labTest) =>
      _getObject('/terms/${Uri.encodeComponent(labTest)}');

  Future<Map<String, dynamic>> parseReport(String text) =>
      _postObject('/reports/parse', <String, dynamic>{'text': text});

  Future<Map<String, dynamic>> parsePdfReport({
    required String fileName,
    required Uint8List bytes,
  }) => _postObject('/reports/parse-pdf', <String, dynamic>{
    'file_name': fileName,
    'content_base64': base64Encode(bytes),
  });

  Future<ChatResponse> chat({
    required List<ChatMessage> messages,
    String? labTest,
    bool includeSources = true,
  }) async {
    final body = <String, dynamic>{
      'messages': messages.map((m) => m.toJson()).toList(),
      if (labTest != null && labTest.isNotEmpty) 'lab_test': labTest,
      'include_sources': includeSources,
    };
    final json = await _postObject('/chat', body, timeout: _llmTimeout);
    return ChatResponse.fromJson(json);
  }

  // --- helpers ---

  Future<dynamic> _get(String path) async {
    http.Response res;
    try {
      res = await _client
          .get(_uri(path), headers: _jsonHeaders)
          .timeout(_timeout);
    } on TimeoutException {
      throw SanaApiException('Sunucuya zamanında ulaşılamadı.');
    } catch (_) {
      throw SanaApiException(
        'Sunucuya bağlanılamadı. Lütfen daha sonra deneyin.',
      );
    }
    return _decode(res);
  }

  Future<dynamic> _post(
    String path,
    Map<String, dynamic> body, {
    Duration? timeout,
  }) async {
    http.Response res;
    try {
      res = await _client
          .post(_uri(path), headers: _jsonHeaders, body: jsonEncode(body))
          .timeout(timeout ?? _timeout);
    } on TimeoutException {
      throw SanaApiException('Sunucuya zamanında ulaşılamadı.');
    } catch (_) {
      throw SanaApiException(
        'Sunucuya bağlanılamadı. Lütfen daha sonra deneyin.',
      );
    }
    return _decode(res);
  }

  Future<Map<String, dynamic>> _getObject(String path) async =>
      _asObject(await _get(path), path);

  Future<Map<String, dynamic>> _postObject(
    String path,
    Map<String, dynamic> body, {
    Duration? timeout,
  }) async => _asObject(await _post(path, body, timeout: timeout), path);

  dynamic _decode(http.Response res) {
    if (res.statusCode != 200) {
      throw SanaApiException(_errorMessage(res), statusCode: res.statusCode);
    }
    try {
      return jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      throw SanaApiException('Yanıt çözümlenemedi.');
    }
  }

  String _errorMessage(http.Response res) {
    try {
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is Map) {
        if (body['detail'] != null) return body['detail'].toString();
        final error = body['error'];
        if (error is Map && error['message'] != null) {
          return error['message'].toString();
        }
      }
    } catch (_) {
      // gövde çözümlenemediyse genel mesaja düş
    }
    return 'İstek başarısız oldu (HTTP ${res.statusCode}).';
  }

  Map<String, dynamic> _asObject(dynamic decoded, String path) {
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw SanaApiException('Beklenmeyen yanıt biçimi ($path).');
  }

  void close() => _client.close();
}
