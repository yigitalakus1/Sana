import 'explain_response.dart' show Citation, RetrievedChunkMeta;

List<dynamic> _asList(dynamic v) => v is List ? v : const <dynamic>[];

List<String> _asStringList(dynamic v) =>
    v is List ? v.map((e) => e.toString()).toList() : <String>[];

Map<String, dynamic> _asMap(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

class ChatMessage {
  const ChatMessage({required this.role, required this.content});

  final String role; // user | assistant
  final String content;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'role': role,
    'content': content,
  };
}

class ChatResponse {
  const ChatResponse({
    required this.requestId,
    required this.responseType,
    required this.answer,
    this.labTest,
    this.matchedTerm,
    required this.citations,
    required this.confidence,
    required this.confidenceLabel,
    required this.disclaimer,
    required this.safetyNotes,
    required this.retrievedChunks,
    required this.llmProvider,
  });

  final String requestId;
  final String responseType; // answer | safety_block | no_results | error
  final String answer;
  final String? labTest;
  final String? matchedTerm;
  final List<Citation> citations;
  final double confidence;
  final String confidenceLabel;
  final String disclaimer;
  final List<String> safetyNotes;
  final List<RetrievedChunkMeta> retrievedChunks;
  final String llmProvider;

  factory ChatResponse.fromJson(Map<String, dynamic> json) => ChatResponse(
    requestId: (json['request_id'] ?? '').toString(),
    responseType: (json['response_type'] ?? '').toString(),
    answer: (json['answer'] ?? '').toString(),
    labTest: json['lab_test'] as String?,
    matchedTerm: json['matched_term'] as String?,
    citations: _asList(
      json['citations'],
    ).map((e) => Citation.fromJson(_asMap(e))).toList(),
    confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
    confidenceLabel: (json['confidence_label'] ?? '').toString(),
    disclaimer: (json['disclaimer'] ?? '').toString(),
    safetyNotes: _asStringList(json['safety_notes']),
    retrievedChunks: _asList(
      json['retrieved_chunks'],
    ).map((e) => RetrievedChunkMeta.fromJson(_asMap(e))).toList(),
    llmProvider: (json['llm_provider'] ?? '').toString(),
  );
}
