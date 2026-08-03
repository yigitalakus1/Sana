import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sana_app/features/ml_dictionary/models/report_parse_models.dart';
import 'package:sana_app/features/ml_dictionary/services/report_history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await ReportHistoryService().clear();
  });

  Future<ReportHistoryEntry> saveOne(
    ReportHistoryService service, {
    required String sourceName,
    double value = 13.5,
  }) => service.save(
    sourceName: sourceName,
    results: [
      ParsedLabResult(
        labTest: 'CRP',
        rawValue: value.toString(),
        value: value,
        unit: 'mg/L',
      ),
    ],
  );

  test('dışa aktarılan JSON kimlik bilgisi ve kayıtları taşır', () async {
    final service = ReportHistoryService();
    await saveOne(service, sourceName: 'tahlil.pdf');

    final decoded = jsonDecode(await service.exportJson()) as Map;

    expect(decoded['app'], 'sana');
    expect(decoded['type'], 'report_history');
    expect(decoded['version'], ReportHistoryService.exportFormatVersion);
    expect(decoded['exported_at'], isA<String>());
    final entries = decoded['entries'] as List;
    expect(entries, hasLength(1));
    expect((entries.single as Map)['source_name'], 'tahlil.pdf');
  });

  test('dışa aktar → temizle → geri yükle kayıtları döndürür', () async {
    final service = ReportHistoryService();
    await saveOne(service, sourceName: 'ilk.pdf');
    await saveOne(service, sourceName: 'ikinci.pdf');
    final backup = await service.exportJson();

    await service.clear();
    expect(await service.load(), isEmpty);

    final result = await service.importJson(backup);

    expect(result.added, 2);
    expect(result.duplicate, 0);
    expect(result.skipped, 0);
    final restored = await service.load();
    expect(restored, hasLength(2));
    expect(
      restored.map((entry) => entry.sourceName),
      containsAll(<String>['ilk.pdf', 'ikinci.pdf']),
    );
  });

  test('geri yükleme mevcut kayıtları silmez, aynı id tekrarlanmaz', () async {
    final service = ReportHistoryService();
    final kept = await saveOne(service, sourceName: 'mevcut.pdf');
    final backup = await service.exportJson();

    // Aynı yedeği ikinci kez yüklemek yeni kayıt eklememeli.
    final result = await service.importJson(backup);

    expect(result.added, 0);
    expect(result.duplicate, 1);
    final entries = await service.load();
    expect(entries, hasLength(1));
    expect(entries.single.id, kept.id);
  });

  test('etiket ve rapor tarihi yedekte korunur', () async {
    final service = ReportHistoryService();
    final saved = await service.save(
      sourceName: 'tahlil.pdf',
      results: const [ParsedLabResult(labTest: 'CRP', value: 10)],
      reportDate: DateTime(2026, 2, 3),
    );
    await service.updateLabel(saved.id, 'Mart kontrolü');
    final backup = await service.exportJson();

    await service.clear();
    await service.importJson(backup);

    final restored = (await service.load()).single;
    expect(restored.displayName, 'Mart kontrolü');
    expect(restored.reportDate, DateTime(2026, 2, 3));
  });

  test('ham liste biçimi de kabul edilir', () async {
    final service = ReportHistoryService();
    final raw = jsonEncode([
      {
        'id': 'x1',
        'created_at': DateTime(2026, 3, 1).toIso8601String(),
        'source_name': 'ham.pdf',
        'results': [
          {'lab_test': 'CRP', 'value': 12.0, 'unit': 'mg/L'},
        ],
      },
    ]);

    final result = await service.importJson(raw);

    expect(result.added, 1);
    expect((await service.load()).single.sourceName, 'ham.pdf');
  });

  test('bozuk JSON çökmeden anlaşılır hata verir', () async {
    final service = ReportHistoryService();

    expect(
      () => service.importJson('{bu json değil'),
      throwsA(isA<HistoryImportException>()),
    );
  });

  test('yabancı JSON reddedilir', () async {
    final service = ReportHistoryService();

    expect(
      () => service.importJson('{"foo": "bar"}'),
      throwsA(isA<HistoryImportException>()),
    );
  });

  test('geçerli kayıt yoksa hata verir ve geçmiş bozulmaz', () async {
    final service = ReportHistoryService();
    await saveOne(service, sourceName: 'mevcut.pdf');

    await expectLater(
      service.importJson(jsonEncode({'entries': <dynamic>[]})),
      throwsA(isA<HistoryImportException>()),
    );

    expect((await service.load()).single.sourceName, 'mevcut.pdf');
  });

  test('bozuk kayıtlar atlanır, sağlamlar alınır', () async {
    final service = ReportHistoryService();
    final raw = jsonEncode({
      'entries': [
        'bu bir kayıt değil',
        {'id': '', 'results': <dynamic>[]},
        {
          'id': 'ok1',
          'created_at': DateTime(2026, 3, 1).toIso8601String(),
          'source_name': 'saglam.pdf',
          'results': [
            {'lab_test': 'CRP', 'value': 12.0, 'unit': 'mg/L'},
          ],
        },
      ],
    });

    final result = await service.importJson(raw);

    expect(result.added, 1);
    expect(result.skipped, 2);
    expect((await service.load()).single.sourceName, 'saglam.pdf');
  });
}
