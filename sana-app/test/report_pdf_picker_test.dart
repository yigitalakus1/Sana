// PDF dışa aktarmada kapsam seçimi: kullanıcı tek rapor ile tüm geçmiş
// arasında seçim yapar ve seçtiği kapsam onay metnine yansır.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sana_app/features/ml_dictionary/models/report_parse_models.dart';
import 'package:sana_app/features/ml_dictionary/screens/settings_screen.dart';
import 'package:sana_app/features/ml_dictionary/services/report_history_service.dart';

import 'test_surface.dart';

/// Geçmişi bellekten veren sahte servis.
///
/// Gerçek servis `SharedPreferences`'a gider; `testWidgets` içinde bu çağrıyı
/// beklemek olay döngüsü dönmediği için kilitleniyor. Burada depolama değil,
/// seçim akışı test ediliyor.
class _FakeHistoryService extends ReportHistoryService {
  _FakeHistoryService(this.entries);

  final List<ReportHistoryEntry> entries;

  @override
  Future<List<ReportHistoryEntry>> load() async => List.of(entries);
}

ReportHistoryEntry _entry(String sourceName, {int day = 12}) =>
    ReportHistoryEntry(
      id: sourceName,
      createdAt: DateTime(2026, 3, day),
      sourceName: sourceName,
      results: const [
        ParsedLabResult(
          labTest: 'CRP',
          rawValue: '13.5',
          value: 13.5,
          unit: 'mg/L',
        ),
      ],
    );

Future<void> pumpSettings(
  WidgetTester tester,
  List<ReportHistoryEntry> entries,
) async {
  useRoomyTestSurface(tester);
  await tester.pumpWidget(
    MaterialApp(home: SettingsScreen(historyService: _FakeHistoryService(entries))),
  );
  await tester.pumpAndSettle();
}

/// PDF satırını bulup dokunur ve seçim diyaloğunu bekler.
Future<void> openPicker(WidgetTester tester) async {
  await tester.tap(find.text('Rapor özeti oluştur (PDF)'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final iki = [_entry('ocak.pdf', day: 4), _entry('mart.pdf')];

  testWidgets('rapor yoksa seçim sorulmaz, kullanıcı bilgilendirilir', (
    tester,
  ) async {
    await pumpSettings(tester, const []);
    await openPicker(tester);

    expect(find.text('Hangi raporlar?'), findsNothing);
    expect(find.text('Dışa aktarılacak rapor bulunamadı.'), findsOneWidget);
  });

  testWidgets('tek rapor ve tüm geçmiş seçenekleri birlikte sunulur', (
    tester,
  ) async {
    await pumpSettings(tester, iki);
    await openPicker(tester);

    expect(find.text('Hangi raporlar?'), findsOneWidget);
    expect(find.text('Tüm raporlar'), findsOneWidget);
    expect(find.text('2 rapor tek belgede'), findsOneWidget);
    expect(find.text('ocak.pdf'), findsOneWidget);
    expect(find.text('mart.pdf'), findsOneWidget);
  });

  testWidgets('varsayılan tüm geçmiştir ve onay metni kapsamı yazar', (
    tester,
  ) async {
    await pumpSettings(tester, iki);
    await openPicker(tester);
    await tester.tap(find.text('Devam et'));
    await tester.pumpAndSettle();

    // Onay diyaloğu, hangi kapsamın dışa aktarılacağını açıkça söylemeli.
    expect(
      find.textContaining('Tüm raporların (2)'),
      findsOneWidget,
      reason: 'kullanıcı ne aktardığını onaydan önce görmeli',
    );
  });

  testWidgets('tek rapor seçilince onay o raporu adıyla söyler', (
    tester,
  ) async {
    await pumpSettings(tester, iki);
    await openPicker(tester);
    await tester.tap(find.text('ocak.pdf'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Devam et'));
    await tester.pumpAndSettle();

    expect(find.textContaining('"ocak.pdf" raporu'), findsOneWidget);
    expect(find.textContaining('Tüm raporların'), findsNothing);
  });

  testWidgets('vazgeçilince onay istenmez', (tester) async {
    await pumpSettings(tester, [_entry('ocak.pdf')]);
    await openPicker(tester);
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();

    expect(find.text('Hangi raporlar?'), findsNothing);
    expect(find.text('Rapor özeti oluştur'), findsNothing);
  });

  testWidgets('onay metni verinin uygulamadan çıktığını söyler', (
    tester,
  ) async {
    await pumpSettings(tester, [_entry('ocak.pdf')]);
    await openPicker(tester);
    await tester.tap(find.text('Devam et'));
    await tester.pumpAndSettle();

    // Sağlık verisi korumalı alanın dışına çıkıyor; bu uyarı kaybolmamalı.
    expect(find.textContaining('sağlık verini içerir'), findsOneWidget);
    expect(find.textContaining('kopyasını kendi içinde saklamaz'), findsOneWidget);
  });

  testWidgets('yedekleme ile rapor özeti ayrı satırlardır', (tester) async {
    await pumpSettings(tester, iki);

    expect(find.text('Rapor özeti oluştur (PDF)'), findsOneWidget);
    expect(find.text('Geçmişi yedekle (JSON)'), findsOneWidget);
    expect(find.text('Yedekten geri yükle'), findsOneWidget);
  });
}
