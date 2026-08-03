// `/explain` yanıt modelleri. Backend snake_case -> Dart camelCase.
//
// Backend public yanıtında `chunk_id`, `content`, `score` YOKTUR; bu modeller
// de onları beklemez.

List<dynamic> _asList(dynamic v) => v is List ? v : const <dynamic>[];

List<String> _asStringList(dynamic v) =>
    v is List ? v.map((e) => e.toString()).toList() : <String>[];

Map<String, dynamic> _asMap(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

class Citation {
  const Citation({required this.sourceTitle, this.sourceUrl, this.section});

  final String sourceTitle;
  final String? sourceUrl;
  final String? section;

  factory Citation.fromJson(Map<String, dynamic> json) => Citation(
    sourceTitle: (json['source_title'] ?? '').toString(),
    sourceUrl: json['source_url'] as String?,
    section: json['section'] as String?,
  );
}

class ResultContext {
  const ResultContext({
    this.rawValue,
    this.value,
    this.unit,
    this.referenceRange,
    this.interpretation,
  });

  final String? rawValue;
  final double? value;
  final String? unit;
  final String? referenceRange; // backend: her zaman null (yorum yok)
  final String? interpretation; // backend: her zaman null (yorum yok)

  factory ResultContext.fromJson(Map<String, dynamic> json) => ResultContext(
    rawValue: json['raw_value'] as String?,
    value: (json['value'] as num?)?.toDouble(),
    unit: json['unit'] as String?,
    referenceRange: json['reference_range'] as String?,
    interpretation: json['interpretation'] as String?,
  );
}

class RetrievedChunkMeta {
  const RetrievedChunkMeta({
    required this.labTest,
    this.section,
    this.sourceTitle,
  });

  final String labTest;
  final String? section;
  final String? sourceTitle;

  factory RetrievedChunkMeta.fromJson(Map<String, dynamic> json) =>
      RetrievedChunkMeta(
        labTest: (json['lab_test'] ?? '').toString(),
        section: json['section'] as String?,
        sourceTitle: json['source_title'] as String?,
      );
}

class ExplainResponse {
  const ExplainResponse({
    required this.requestId,
    required this.responseType,
    this.labTest,
    this.matchedTerm,
    required this.answer,
    required this.confidence,
    required this.confidenceLabel,
    this.resultContext,
    required this.citations,
    required this.doctorQuestions,
    required this.disclaimer,
    this.normalizedQuery,
    this.llmProvider,
    required this.safetyNotes,
    required this.retrievedChunks,
  });

  final String requestId;
  final String responseType; // answer | no_results | safety_block | error
  final String? labTest;
  final String? matchedTerm;
  final String answer;
  final double confidence;
  final String confidenceLabel; // low | medium | high
  final ResultContext? resultContext;
  final List<Citation> citations;
  final List<String> doctorQuestions;
  final String disclaimer;
  final String? normalizedQuery;
  final String? llmProvider;
  final List<String> safetyNotes;
  final List<RetrievedChunkMeta> retrievedChunks;

  bool get isAnswer => responseType == 'answer';

  factory ExplainResponse.fromJson(Map<String, dynamic> json) =>
      ExplainResponse(
        requestId: (json['request_id'] ?? '').toString(),
        responseType: (json['response_type'] ?? '').toString(),
        labTest: json['lab_test'] as String?,
        matchedTerm: json['matched_term'] as String?,
        answer: (json['answer'] ?? '').toString(),
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
        confidenceLabel: (json['confidence_label'] ?? '').toString(),
        resultContext: json['result_context'] == null
            ? null
            : ResultContext.fromJson(_asMap(json['result_context'])),
        citations: _asList(
          json['citations'],
        ).map((e) => Citation.fromJson(_asMap(e))).toList(),
        doctorQuestions: _asStringList(json['doctor_questions']),
        disclaimer: (json['disclaimer'] ?? '').toString(),
        normalizedQuery: json['normalized_query'] as String?,
        llmProvider: json['llm_provider'] as String?,
        safetyNotes: _asStringList(json['safety_notes']),
        retrievedChunks: _asList(
          json['retrieved_chunks'],
        ).map((e) => RetrievedChunkMeta.fromJson(_asMap(e))).toList(),
      );
}
