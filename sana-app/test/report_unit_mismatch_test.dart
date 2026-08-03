import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sana_app/features/ml_dictionary/models/report_parse_models.dart';
import 'package:sana_app/features/ml_dictionary/screens/report_history_screen.dart';
import 'package:sana_app/features/ml_dictionary/services/report_history_service.dart';

void main() {
  testWidgets('farklı birimdeki ölçüm sessizce atlanmaz, uyarı gösterilir', (
    tester,
  ) async {
    final service = _FakeHistoryService([
      _entry('r1', '01.01.2026.pdf', 13.5, 'mg/L'),
      _entry('r2', '01.02.2026.pdf', 1.35, 'mg/dL'),
    ]);

    await _pumpScreen(tester, service);

    expect(find.textContaining('farklı birimde'), findsOneWidget);
    expect(find.textContaining('mg/dL'), findsOneWidget);
    expect(find.textContaining('Birim dönüşümü tahmin edilmez'), findsOneWidget);
  });

  testWidgets('birimler aynıysa uyarı gösterilmez', (tester) async {
    final service = _FakeHistoryService([
      _entry('r1', '01.01.2026.pdf', 13.5, 'mg/L'),
      _entry('r2', '01.02.2026.pdf', 20.0, 'mg/L'),
    ]);

    await _pumpScreen(tester, service);

    expect(find.textContaining('farklı birimde'), findsNothing);
    // Aynı birimdeki iki ölçüm grafiğe girer.
    expect(find.textContaining('13,5'), findsNothing);
    expect(find.textContaining('· 13.5 mg/L'), findsOneWidget);
    expect(find.textContaining('· 20 mg/L'), findsOneWidget);
  });

  testWidgets('birimsiz ölçüm de açıkça bildirilir', (tester) async {
    final service = _FakeHistoryService([
      _entry('r1', '01.01.2026.pdf', 13.5, 'mg/L'),
      _entry('r2', '01.02.2026.pdf', 20.0, null),
    ]);

    await _pumpScreen(tester, service);

    expect(find.textContaining('birimsiz'), findsOneWidget);
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

ReportHistoryEntry _entry(
  String id,
  String sourceName,
  double value,
  String? unit,
) => ReportHistoryEntry(
  id: id,
  createdAt: DateTime(2026, 7, 24),
  sourceName: sourceName,
  results: [
    ParsedLabResult(
      labTest: 'CRP',
      rawValue: value.toString(),
      value: value,
      unit: unit,
    ),
  ],
);

class _FakeHistoryService extends ReportHistoryService {
  _FakeHistoryService(this.entries);

  final List<ReportHistoryEntry> entries;

  @override
  Future<List<ReportHistoryEntry>> load() async => List.of(entries);
}
