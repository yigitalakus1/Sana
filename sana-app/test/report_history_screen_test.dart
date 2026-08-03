import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sana_app/features/ml_dictionary/models/report_parse_models.dart';
import 'package:sana_app/features/ml_dictionary/screens/report_history_screen.dart';
import 'package:sana_app/features/ml_dictionary/services/report_history_service.dart';

void main() {
  testWidgets('reports can be selected for comparison', (tester) async {
    final service = _FakeHistoryService(_sampleEntries());

    await _pumpScreen(tester, service);

    expect(find.text('2 rapor seçili'), findsOneWidget);
    expect(find.text('2/3 seçili'), findsOneWidget);
    expect(find.text('Son ölçüm'), findsOneWidget);
    expect(find.text('Değişim'), findsOneWidget);
    expect(find.text('Aralık'), findsOneWidget);
    expect(find.text('+10 mg/L'), findsOneWidget);

    final thirdReport = find.byKey(const ValueKey('select-r3'));
    await tester.scrollUntilVisible(
      thirdReport,
      360,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(thirdReport);
    await tester.pump();

    expect(find.text('3 rapor seçili'), findsOneWidget);
    expect(find.text('3/3 seçili'), findsOneWidget);
    expect(find.text('10.07.26 · 30 mg/L'), findsOneWidget);
  });

  testWidgets('a report can be deleted after confirmation', (tester) async {
    final service = _FakeHistoryService(_sampleEntries());

    await _pumpScreen(tester, service);
    await tester.tap(find.byKey(const ValueKey('delete-r1')));
    await tester.pumpAndSettle();

    expect(find.text('Rapor silinsin mi?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Sil'));
    await tester.pumpAndSettle();

    expect(service.deletedId, 'r1');
    expect(find.text('03.02.2026.pdf'), findsNothing);
    expect(find.text('1/2 seçili'), findsOneWidget);
  });

  testWidgets('requested lab selects all matching reports for the chart', (
    tester,
  ) async {
    final service = _FakeHistoryService(_sampleEntries());

    await _pumpScreen(tester, service, initialLabTest: 'CRP');

    expect(find.text('3 rapor seçili'), findsOneWidget);
    expect(find.text('3/3 seçili'), findsOneWidget);
    expect(find.text('03.02.26 · 10 mg/L'), findsOneWidget);
    expect(find.text('10.07.26 · 30 mg/L'), findsOneWidget);
  });
}

Future<void> _pumpScreen(
  WidgetTester tester,
  ReportHistoryService service, {
  String? initialLabTest,
}) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: ReportHistoryScreen(
        service: service,
        initialLabTest: initialLabTest,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<ReportHistoryEntry> _sampleEntries() => [
  _entry('r1', '03.02.2026.pdf', DateTime(2026, 7, 24), 10),
  _entry('r2', '25.06.2026.pdf', DateTime(2026, 7, 23), 20),
  _entry('r3', '10.07.2026.pdf', DateTime(2026, 7, 22), 30),
];

ReportHistoryEntry _entry(
  String id,
  String sourceName,
  DateTime createdAt,
  double value,
) => ReportHistoryEntry(
  id: id,
  createdAt: createdAt,
  sourceName: sourceName,
  results: [
    ParsedLabResult(
      labTest: 'CRP',
      rawValue: value.toStringAsFixed(0),
      value: value,
      unit: 'mg/L',
    ),
  ],
);

class _FakeHistoryService extends ReportHistoryService {
  _FakeHistoryService(this.entries);

  final List<ReportHistoryEntry> entries;
  String? deletedId;

  @override
  Future<List<ReportHistoryEntry>> load() async => List.of(entries);

  @override
  Future<void> delete(String id) async {
    deletedId = id;
    entries.removeWhere((entry) => entry.id == id);
  }

  @override
  Future<void> clear() async => entries.clear();
}
