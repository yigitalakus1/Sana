import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sana_app/features/ml_dictionary/models/report_parse_models.dart';
import 'package:sana_app/features/ml_dictionary/screens/report_history_screen.dart';
import 'package:sana_app/features/ml_dictionary/services/report_history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('model', () {
    test('etiket yoksa dosya adı gösterilir', () {
      final entry = _entry('r1', 'tahlil.pdf');

      expect(entry.hasCustomLabel, isFalse);
      expect(entry.displayName, 'tahlil.pdf');
      expect(entry.toJson().containsKey('label'), isFalse);
    });

    test('etiket verilince gösterim adı etiket olur', () {
      final entry = _entry('r1', 'tahlil.pdf').withLabel('  Kontrol sonrası  ');

      expect(entry.hasCustomLabel, isTrue);
      expect(entry.displayName, 'Kontrol sonrası');
      expect(entry.sourceName, 'tahlil.pdf');
    });

    test('boş etiket temizler ve dosya adına döner', () {
      final entry = _entry('r1', 'tahlil.pdf').withLabel('Ad').withLabel('   ');

      expect(entry.hasCustomLabel, isFalse);
      expect(entry.displayName, 'tahlil.pdf');
    });

    test('etiket JSON tur atışında korunur, eski kayıtlar null kalır', () {
      final labelled = _entry('r1', 'tahlil.pdf').withLabel('Mart kontrolü');
      final restored = ReportHistoryEntry.fromJson(labelled.toJson());
      expect(restored.label, 'Mart kontrolü');
      expect(restored.displayName, 'Mart kontrolü');

      // Etiket alanı olmayan eski kayıt.
      final legacy = ReportHistoryEntry.fromJson(<String, dynamic>{
        'id': 'r0',
        'created_at': DateTime(2026, 5, 1).toIso8601String(),
        'source_name': 'eski.pdf',
        'results': const <dynamic>[],
      });
      expect(legacy.label, isNull);
      expect(legacy.displayName, 'eski.pdf');
    });
  });

  group('servis', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('etiket kalıcı olarak saklanır ve kaldırılabilir', () async {
      final service = ReportHistoryService();
      await service.clear();
      final saved = await service.save(
        sourceName: 'tahlil.pdf',
        results: const [
          ParsedLabResult(
            labTest: 'CRP',
            rawValue: '13.5',
            value: 13.5,
            unit: 'mg/L',
          ),
        ],
      );

      await service.updateLabel(saved.id, 'Mart kontrolü');
      var entries = await service.load();
      expect(entries.single.displayName, 'Mart kontrolü');
      expect(entries.single.sourceName, 'tahlil.pdf');
      expect(entries.single.results, hasLength(1));

      await service.updateLabel(saved.id, null);
      entries = await service.load();
      expect(entries.single.hasCustomLabel, isFalse);
      expect(entries.single.displayName, 'tahlil.pdf');

      await service.clear();
    });
  });

  group('ekran', () {
    testWidgets('rapor adı düzenlenip kaydedilebilir', (tester) async {
      final service = _FakeHistoryService([_entry('r1', '03.02.2026.pdf')]);

      await _pumpScreen(tester, service);
      expect(find.text('03.02.2026.pdf'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('label-r1')));
      await tester.pumpAndSettle();

      expect(find.text('Rapor adı'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('label-field')),
        'Mart kontrolü',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Kaydet'));
      await tester.pumpAndSettle();

      expect(service.labels['r1'], 'Mart kontrolü');
      // Başlık etiketi gösterir, dosya adı alt satırda görünür kalır.
      expect(find.text('Mart kontrolü'), findsOneWidget);
      expect(find.text('03.02.2026.pdf'), findsOneWidget);
    });

    testWidgets('vazgeçilince etiket değişmez', (tester) async {
      final service = _FakeHistoryService([_entry('r1', '03.02.2026.pdf')]);

      await _pumpScreen(tester, service);
      await tester.tap(find.byKey(const ValueKey('label-r1')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('label-field')),
        'Yazıldı ama kaydedilmedi',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Vazgeç'));
      await tester.pumpAndSettle();

      expect(service.labels, isEmpty);
      expect(find.text('03.02.2026.pdf'), findsOneWidget);
    });

    testWidgets('etiket boşaltılınca dosya adına dönülür', (tester) async {
      final service = _FakeHistoryService([
        _entry('r1', '03.02.2026.pdf').withLabel('Eski ad'),
      ]);

      await _pumpScreen(tester, service);
      expect(find.text('Eski ad'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('label-r1')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('label-field')), '');
      await tester.tap(find.widgetWithText(FilledButton, 'Kaydet'));
      await tester.pumpAndSettle();

      expect(service.labels['r1'], '');
      expect(find.text('Eski ad'), findsNothing);
      expect(find.text('03.02.2026.pdf'), findsOneWidget);
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

ReportHistoryEntry _entry(String id, String sourceName) => ReportHistoryEntry(
  id: id,
  createdAt: DateTime(2026, 7, 24),
  sourceName: sourceName,
  results: const [
    ParsedLabResult(
      labTest: 'CRP',
      rawValue: '10',
      value: 10,
      unit: 'mg/L',
    ),
  ],
);

class _FakeHistoryService extends ReportHistoryService {
  _FakeHistoryService(this.entries);

  final List<ReportHistoryEntry> entries;
  final Map<String, String?> labels = <String, String?>{};

  @override
  Future<List<ReportHistoryEntry>> load() async => List.of(entries);

  @override
  Future<void> updateLabel(String id, String? label) async {
    labels[id] = label;
    final index = entries.indexWhere((entry) => entry.id == id);
    if (index != -1) entries[index] = entries[index].withLabel(label);
  }
}
