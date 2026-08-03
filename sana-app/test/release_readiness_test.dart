// Release öncesi kontrol: büyük yazı ve koyu tema altında ekranlar taşmadan
// çizilmeli. Taşma (RenderFlex overflow) testte istisna olarak yakalanır.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sana_app/features/ml_dictionary/models/report_parse_models.dart';
import 'package:sana_app/features/ml_dictionary/screens/report_history_screen.dart';
import 'package:sana_app/features/ml_dictionary/screens/settings_screen.dart';
import 'package:sana_app/features/ml_dictionary/screens/profile_screen.dart';
import 'package:sana_app/features/ml_dictionary/services/report_history_service.dart';
import 'package:sana_app/features/premium/screens/premium_screen.dart';

/// Dar telefon: taşma en çok burada görünür.
const _phone = Size(360, 690);

/// Sistem büyük yazısı + uygulamanın "Büyük yazı" ayarı üst üste binebilir.
const _largeTextScale = 2.0;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  for (final brightness in Brightness.values) {
    final themeName = brightness == Brightness.dark ? 'koyu' : 'açık';

    testWidgets('rapor geçmişi — büyük yazı, $themeName tema', (tester) async {
      await _pump(
        tester,
        brightness: brightness,
        child: ReportHistoryScreen(service: _FakeHistoryService(_entries())),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('ayarlar — büyük yazı, $themeName tema', (tester) async {
      await _pump(
        tester,
        brightness: brightness,
        child: SettingsScreen(
          historyService: _FakeHistoryService(_entries()),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('premium — büyük yazı, $themeName tema', (tester) async {
      await _pump(
        tester,
        brightness: brightness,
        child: const PremiumScreen(),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('sağlık profili — büyük yazı, $themeName tema', (tester) async {
      await _pump(
        tester,
        brightness: brightness,
        child: const ProfileScreen(),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('grafik ekran okuyucuya ölçümleri sözel olarak verir', (
    tester,
  ) async {
    // Aynı birimde iki ölçüm → grafik çizilir.
    final entries = [
      ReportHistoryEntry(
        id: 'r1',
        createdAt: DateTime(2026, 1, 1),
        sourceName: '01.01.2026.pdf',
        results: const [
          ParsedLabResult(labTest: 'CRP', value: 13.5, unit: 'mg/L'),
        ],
      ),
      ReportHistoryEntry(
        id: 'r2',
        createdAt: DateTime(2026, 2, 1),
        sourceName: '01.02.2026.pdf',
        results: const [
          ParsedLabResult(labTest: 'CRP', value: 20, unit: 'mg/L'),
        ],
      ),
    ];
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      brightness: Brightness.light,
      child: ReportHistoryScreen(service: _FakeHistoryService(entries)),
    );

    expect(
      find.bySemanticsLabel(RegExp(r'CRP değişim grafiği.*13\.5 mg/L')),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('rapor geçmişi büyük yazıda kaydırılabilir kalır', (
    tester,
  ) async {
    await _pump(
      tester,
      brightness: Brightness.light,
      child: ReportHistoryScreen(service: _FakeHistoryService(_entries())),
    );

    // İçerik ekrana sığmasa bile kullanıcı listeyi kaydırıp ulaşabilmeli.
    expect(find.byType(ListView), findsWidgets);
    await tester.drag(find.byType(ListView).first, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required Brightness brightness,
  required Widget child,
}) async {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: MediaQuery(
        data: const MediaQueryData(
          size: _phone,
          textScaler: TextScaler.linear(_largeTextScale),
        ),
        child: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<ReportHistoryEntry> _entries() => [
  // Etiketli + uzun dosya adlı kayıt: başlık satırı en çok burada zorlanır.
  ReportHistoryEntry(
    id: 'r1',
    createdAt: DateTime(2026, 7, 24),
    sourceName: 'cok-uzun-bir-tahlil-dosyasi-adi-03.02.2026.pdf',
    label: 'Mart kontrolü sonrası ikinci tahlil',
    reportDate: DateTime(2026, 2, 3),
    results: const [
      ParsedLabResult(
        labTest: 'CRP',
        rawValue: '13.5',
        value: 13.5,
        unit: 'mg/L',
      ),
    ],
  ),
  // Farklı birim: birim uyuşmazlığı uyarısı da çizilsin.
  ReportHistoryEntry(
    id: 'r2',
    createdAt: DateTime(2026, 6, 24),
    sourceName: '25.06.2026.pdf',
    results: const [
      ParsedLabResult(
        labTest: 'CRP',
        rawValue: '1.35',
        value: 1.35,
        unit: 'mg/dL',
      ),
    ],
  ),
];

class _FakeHistoryService extends ReportHistoryService {
  _FakeHistoryService(this.entries);

  final List<ReportHistoryEntry> entries;

  @override
  Future<List<ReportHistoryEntry>> load() async => List.of(entries);
}
