// Onay ekranının sözleşmesi.
//
// En kritik iddia: kullanıcı onaylamadan rapor geçmişine hiçbir şey yazılmaz.
// Ağ kullanılmaz; sözlük sahte servisten gelir.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sana_app/features/ml_dictionary/models/report_parse_models.dart';
import 'package:sana_app/features/ml_dictionary/models/term_models.dart';
import 'package:sana_app/features/ml_dictionary/screens/report_confirm_screen.dart';
import 'package:sana_app/features/ml_dictionary/services/ml_dictionary_service.dart';

/// Sözlüğü bellekten veren, ağa çıkmayan servis.
class _FakeDictionaryService extends MlDictionaryService {
  int termCalls = 0;

  @override
  Future<List<TermSummary>> getTerms() async {
    termCalls++;
    return const [
      TermSummary(labTest: 'CRP', title: 'C-Reaktif Protein', sections: []),
      TermSummary(labTest: 'Ferritin', title: 'Ferritin', sections: []),
    ];
  }
}

ParsedLabResult _result({
  String labTest = 'CRP',
  String? rawValue = '13.5',
  double? value = 13.5,
  String? unit = 'mg/L',
  String? referenceRange = '0 - 5',
  String? interpretation = 'high',
  String? matchedTerm = 'crp',
}) => ParsedLabResult(
  labTest: labTest,
  matchedTerm: matchedTerm,
  rawValue: rawValue,
  value: value,
  unit: unit,
  referenceRange: referenceRange,
  interpretation: interpretation,
);

/// Ekranı açar ve onay sonucunu yakalar. `null` = kullanıcı vazgeçti.
Future<List<ParsedLabResult>?> pumpConfirm(
  WidgetTester tester,
  List<ParsedLabResult> results, {
  MlDictionaryService? service,
}) async {
  List<ParsedLabResult>? captured;
  var popped = false;

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            captured = await Navigator.of(context)
                .push<List<ParsedLabResult>>(
                  MaterialPageRoute<List<ParsedLabResult>>(
                    builder: (_) => ReportConfirmScreen(
                      results: results,
                      sourceName: 'tahlil.pdf',
                      service: service ?? _FakeDictionaryService(),
                    ),
                  ),
                );
            popped = true;
          },
          child: const Text('aç'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('aç'));
  await tester.pumpAndSettle();
  expect(popped, isFalse);
  return captured;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ayrıştırılan alanların hepsi gösterilir', (tester) async {
    await pumpConfirm(tester, [_result()]);

    expect(find.text('CRP'), findsOneWidget);
    expect(find.textContaining('crp'), findsOneWidget); // eşleşen ifade
    expect(find.text('13.5 mg/L'), findsOneWidget);
    expect(find.text('0 - 5'), findsOneWidget);
    expect(find.text('Yüksek'), findsWidgets);
  });

  testWidgets('referans aralığı yoksa sınıflandırma uydurulmaz', (
    tester,
  ) async {
    await pumpConfirm(tester, [
      _result(referenceRange: null, interpretation: null),
    ]);

    expect(find.text('Raporda yok'), findsOneWidget);
    expect(find.text('Aralık verilmemiş'), findsWidgets);
    expect(find.text('Aralık içinde'), findsNothing);
  });

  testWidgets('vazgeçilirse hiçbir değer döndürülmez', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReportConfirmScreen(
          results: [_result()],
          sourceName: 'tahlil.pdf',
          service: _FakeDictionaryService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Vazgeç, kaydetme'), findsOneWidget);
    expect(find.text('Onayla ve geçmişe kaydet'), findsOneWidget);
  });

  testWidgets('onaylanınca düzeltilmiş liste döner', (tester) async {
    // İki kart + onay butonu varsayılan test yüzeyine sığmıyor; kaydırma
    // yerine yüzeyi büyütmek testi kararlı kılıyor.
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    List<ParsedLabResult>? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                captured = await Navigator.of(context)
                    .push<List<ParsedLabResult>>(
                      MaterialPageRoute<List<ParsedLabResult>>(
                        builder: (_) => ReportConfirmScreen(
                          results: [_result(), _result(labTest: 'Ferritin')],
                          sourceName: 'tahlil.pdf',
                          service: _FakeDictionaryService(),
                        ),
                      ),
                    );
              },
              child: const Text('aç'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('aç'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Onayla ve geçmişe kaydet'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured, hasLength(2));
  });

  testWidgets('yanlış bulunan satır çıkarılabilir', (tester) async {
    await pumpConfirm(tester, [
      _result(),
      _result(labTest: 'Ferritin', matchedTerm: 'ferritin'),
    ]);

    expect(find.text('2 değer'), findsOneWidget);

    await tester.tap(find.text('Çıkar').first);
    await tester.pumpAndSettle();

    expect(find.text('1 değer'), findsOneWidget);
    expect(find.text('CRP'), findsNothing);
  });

  testWidgets('aynı tahlilin iki ölçümü sessizce silinmez, uyarı gösterilir', (
    tester,
  ) async {
    await pumpConfirm(tester, [
      _result(rawValue: '92', value: 92, labTest: 'Glukoz'),
      _result(rawValue: '140', value: 140, labTest: 'Glukoz'),
    ]);

    // İkisi de listede kalmalı.
    expect(find.text('2 değer'), findsOneWidget);
    expect(find.textContaining('birden fazla ölçümle'), findsOneWidget);
    expect(find.textContaining('birden çok kez geçiyor'), findsWidgets);
  });

  testWidgets('değer düzeltilince durum yeniden hesaplanır', (tester) async {
    await pumpConfirm(tester, [_result()]);

    await tester.tap(find.text('Düzelt'));
    await tester.pumpAndSettle();

    // 13.5 (yüksek) yerine aralık içi bir değer yaz.
    await tester.enterText(find.byType(TextField).first, '3');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();

    expect(find.text('3 mg/L'), findsOneWidget);
    expect(find.text('Aralık içinde'), findsWidgets);
  });

  testWidgets('aralık silinirse durum boşalır, uydurulmaz', (tester) async {
    await pumpConfirm(tester, [_result()]);

    await tester.tap(find.text('Düzelt'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(2), '');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();

    expect(find.text('Aralık verilmemiş'), findsWidgets);
    expect(find.text('Yüksek'), findsNothing);
  });

  testWidgets('sayı olmayan değer reddedilir', (tester) async {
    await pumpConfirm(tester, [_result()]);

    await tester.tap(find.text('Düzelt'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'abc');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();

    // Diyalog kapanmamalı ve sebep gösterilmeli.
    expect(find.textContaining('Sayı olarak yazın'), findsOneWidget);
  });

  testWidgets('tanınmayan tahlil sözlükten eklenebilir', (tester) async {
    final service = _FakeDictionaryService();
    await pumpConfirm(tester, [_result()], service: service);

    await tester.tap(find.text('Değer ekle'));
    await tester.pumpAndSettle();

    expect(service.termCalls, 1);
    expect(find.text('Tahlil seç'), findsOneWidget);

    await tester.tap(find.text('Ferritin').first);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '8');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();

    expect(find.text('2 değer'), findsOneWidget);
    expect(find.text('Ferritin'), findsWidgets);
  });

  testWidgets('gizlilik bilgisi ekranda görünür', (tester) async {
    await pumpConfirm(tester, [_result()]);

    expect(find.textContaining('bu cihazda işlenir'), findsOneWidget);
  });
}
