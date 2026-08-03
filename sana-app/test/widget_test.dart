import 'package:flutter_test/flutter_test.dart';

import 'package:sana_app/features/ml_dictionary/models/chat_models.dart';
import 'package:sana_app/features/ml_dictionary/models/explain_response.dart';
import 'package:sana_app/features/ml_dictionary/models/report_parse_models.dart';
import 'package:sana_app/features/ml_dictionary/models/term_models.dart';

void main() {
  test('ExplainResponse.fromJson maps snake_case fields', () {
    final json = <String, dynamic>{
      'request_id': 'abc',
      'response_type': 'answer',
      'lab_test': 'CRP',
      'matched_term': 'crp',
      'answer': 'CRP açıklaması',
      'confidence': 0.8,
      'confidence_label': 'high',
      'result_context': {
        'raw_value': '13.5',
        'value': 13.5,
        'unit': null,
        'reference_range': null,
        'interpretation': null,
      },
      'citations': [
        {
          'source_title': 'MedlinePlus',
          'source_url': 'https://x',
          'section': 'Nedir?',
        },
      ],
      'doctor_questions': ['Soru 1'],
      'disclaimer': 'uyarı',
      'normalized_query': 'crp 13 5',
      'llm_provider': 'dummy',
      'safety_notes': <dynamic>[],
      'retrieved_chunks': [
        {'lab_test': 'CRP', 'section': 'Nedir?', 'source_title': 'MedlinePlus'},
      ],
    };

    final r = ExplainResponse.fromJson(json);
    expect(r.responseType, 'answer');
    expect(r.labTest, 'CRP');
    expect(r.confidence, 0.8);
    expect(r.confidenceLabel, 'high');
    expect(r.resultContext, isNotNull);
    expect(r.resultContext!.value, 13.5);
    expect(r.resultContext!.interpretation, isNull);
    expect(r.resultContext!.referenceRange, isNull);
    expect(r.citations.length, 1);
    expect(r.citations.first.sourceTitle, 'MedlinePlus');
    expect(r.doctorQuestions, ['Soru 1']);
    expect(r.llmProvider, 'dummy');
    expect(r.retrievedChunks.first.labTest, 'CRP');
  });

  test('ExplainResponse handles null result_context and missing lists', () {
    final r = ExplainResponse.fromJson(<String, dynamic>{
      'request_id': 'a',
      'response_type': 'no_results',
      'answer': 'x',
      'confidence': 0.0,
      'confidence_label': 'low',
      'disclaimer': 'd',
    });
    expect(r.resultContext, isNull);
    expect(r.citations, isEmpty);
    expect(r.doctorQuestions, isEmpty);
    expect(r.safetyNotes, isEmpty);
    expect(r.retrievedChunks, isEmpty);
  });

  test('TermSummary and TermDetail parse', () {
    final s = TermSummary.fromJson(<String, dynamic>{
      'lab_test': 'CRP',
      'title': 'C-Reaktif Protein (CRP)',
      'sections': ['Nedir?', 'Neden ölçülür?'],
    });
    expect(s.labTest, 'CRP');
    expect(s.sections.length, 2);

    final d = TermDetail.fromJson(<String, dynamic>{
      'lab_test': 'CRP',
      'title': 't',
      'sections': ['Nedir?'],
      'sources': [
        {
          'source_title': 'MedlinePlus',
          'source_url': 'https://x',
          'section': null,
        },
      ],
    });
    expect(d.sources.first.sourceTitle, 'MedlinePlus');
    expect(d.sources.first.section, isNull);
  });

  test('Term summaries are sorted using the Turkish alphabet', () {
    TermSummary term(String labTest) =>
        TermSummary(labTest: labTest, sections: const []);

    final sorted = sortTermSummariesAlphabetically([
      term('Şeker'),
      term('Çinko'),
      term('D vitamini'),
      term('CRP'),
      term('İnsülin'),
      term('Işık testi'),
      term('AFP'),
    ]);

    expect(sorted.map((term) => term.labTest), [
      'AFP',
      'CRP',
      'Çinko',
      'D vitamini',
      'Işık testi',
      'İnsülin',
      'Şeker',
    ]);
  });

  test('ReportParseResponse parses results', () {
    final r = ReportParseResponse.fromJson(<String, dynamic>{
      'parser_status': 'parsed',
      'results': [
        {
          'lab_test': 'CRP',
          'matched_term': 'crp',
          'raw_value': '13.5',
          'value': 13.5,
          'unit': 'mg/L',
          'reference_range': null,
          'interpretation': null,
        },
      ],
      'disclaimer': 'd',
    });
    expect(r.parserStatus, 'parsed');
    expect(r.results.length, 1);
    expect(r.results.first.value, 13.5);
    expect(r.results.first.unit, 'mg/L');
    expect(r.results.first.interpretation, isNull);
    expect(r.results.first.referenceRange, isNull);
  });

  test('ChatResponse parses public fields', () {
    final r = ChatResponse.fromJson(<String, dynamic>{
      'request_id': 'chat-1',
      'response_type': 'answer',
      'answer': 'CRP açıklaması',
      'lab_test': 'CRP',
      'matched_term': 'crp',
      'citations': [
        {
          'source_title': 'MedlinePlus',
          'source_url': 'https://x',
          'section': 'Nedir?',
        },
      ],
      'confidence': 0.82,
      'confidence_label': 'high',
      'disclaimer': 'uyarı',
      'safety_notes': ['not'],
      'retrieved_chunks': [
        {'lab_test': 'CRP', 'section': 'Nedir?', 'source_title': 'MedlinePlus'},
      ],
      'llm_provider': 'ollama',
    });

    expect(r.requestId, 'chat-1');
    expect(r.responseType, 'answer');
    expect(r.labTest, 'CRP');
    expect(r.citations.first.sourceTitle, 'MedlinePlus');
    expect(r.confidence, 0.82);
    expect(r.safetyNotes, ['not']);
    expect(r.retrievedChunks.first.section, 'Nedir?');
    expect(r.llmProvider, 'ollama');
  });

  test('ChatMessage serializes role and content', () {
    const message = ChatMessage(role: 'user', content: 'CRP nedir?');
    expect(message.toJson(), <String, dynamic>{
      'role': 'user',
      'content': 'CRP nedir?',
    });
  });
}
