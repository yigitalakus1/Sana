import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sana_app/features/ml_dictionary/models/report_parse_models.dart';
import 'package:sana_app/features/ml_dictionary/screens/report_history_screen.dart';
import 'package:sana_app/features/ml_dictionary/services/report_history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parse yanıtı', () {
    test('report_date okunur', () {
      final response = ReportParseResponse.fromJson(<String, dynamic>{
        'parser_status': 'parsed',
        'results': const <dynamic>[],
        'disclaimer': 'uyarı',
        'report_date': '2026-02-03',
      });

      expect(response.reportDate, DateTime(2026, 2, 3));
    });

    test('report_date yoksa veya bozuksa null kalır', () {
      ReportParseResponse build(Object? raw) =>
          ReportParseResponse.fromJson(<String, dynamic>{
            'parser_status': 'parsed',
            'results': const <dynamic>[],
            'disclaimer': 'uyarı',
            'report_date': ?raw,
          });

      expect(build(null).reportDate, isNull);
      expect(build('').reportDate, isNull);
      expect(build('tarih değil').reportDate, isNull);
    });
  });

  group('geçmiş kaydı', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('rapor tarihi kalıcı olarak saklanır', () async {
      final service = ReportHistoryService();
      await service.clear();

      await service.save(
        sourceName: 'tahlil.pdf',
        results: const [ParsedLabResult(labTest: 'CRP', value: 10)],
        reportDate: DateTime(2026, 2, 3),
      );

      final entries = await service.load();
      expect(entries.single.reportDate, DateTime(2026, 2, 3));

      // Etiket düzenlemesi tarihi bozmaz.
      await service.updateLabel(entries.single.id, 'Mart kontrolü');
      final updated = await service.load();
      expect(updated.single.reportDate, DateTime(2026, 2, 3));
      expect(updated.single.displayName, 'Mart kontrolü');

      await service.clear();
    });

    test('rapor tarihi JSON tur atışında korunur, eski kayıtlar null', () {
      final entry = ReportHistoryEntry(
        id: 'r1',
        createdAt: DateTime(2026, 7, 24),
        sourceName: 'tahlil.pdf',
        results: const [],
        reportDate: DateTime(2026, 2, 3),
      );
      final restored = ReportHistoryEntry.fromJson(entry.toJson());
      expect(restored.reportDate, DateTime(2026, 2, 3));

      final legacy = ReportHistoryEntry.fromJson(<String, dynamic>{
        'id': 'r0',
        'created_at': DateTime(2026, 5, 1).toIso8601String(),
        'source_name': 'eski.pdf',
        'results': const <dynamic>[],
      });
      expect(legacy.reportDate, isNull);
    });
  });

  group('gösterim önceliği', () {
    testWidgets('rapor tarihi dosya adındaki tarihi geçersiz kılar', (
      tester,
    ) async {
      // Dosya adı 03.02.2026 diyor; rapor içeriği 15.06.2026 diyor.
      final service = _FakeHistoryService([
        ReportHistoryEntry(
          id: 'r1',
          createdAt: DateTime(2026, 7, 24),
          sourceName: '03.02.2026.pdf',
          results: const [ParsedLabResult(labTest: 'CRP', value: 10)],
          reportDate: DateTime(2026, 6, 15),
        ),
      ]);

      await _pumpScreen(tester, service);

      expect(find.textContaining('15.06.2026'), findsOneWidget);
      expect(find.textContaining('03.02.2026 ·'), findsNothing);
    });

    testWidgets('rapor tarihi yoksa dosya adındaki tarih kullanılır', (
      tester,
    ) async {
      final service = _FakeHistoryService([
        ReportHistoryEntry(
          id: 'r1',
          createdAt: DateTime(2026, 7, 24),
          sourceName: '03.02.2026.pdf',
          results: const [ParsedLabResult(labTest: 'CRP', value: 10)],
        ),
      ]);

      await _pumpScreen(tester, service);

      expect(find.textContaining('03.02.2026'), findsWidgets);
    });

    testWidgets('tarih hiç yoksa kayıt zamanına düşülür', (tester) async {
      final service = _FakeHistoryService([
        ReportHistoryEntry(
          id: 'r1',
          createdAt: DateTime(2026, 7, 24),
          sourceName: 'tahlil.pdf',
          results: const [ParsedLabResult(labTest: 'CRP', value: 10)],
        ),
      ]);

      await _pumpScreen(tester, service);

      expect(find.textContaining('24.07.2026'), findsOneWidget);
    });
  });
}

Future<void> _pumpScreen(
  WidgetTester tester,
  ReportHistoryService service,
) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(home: ReportHistoryScreen(service: service)),
  );
  await tester.pumpAndSettle();
}

class _FakeHistoryService extends ReportHistoryService {
  _FakeHistoryService(this.entries);

  final List<ReportHistoryEntry> entries;

  @override
  Future<List<ReportHistoryEntry>> load() async => List.of(entries);
}
