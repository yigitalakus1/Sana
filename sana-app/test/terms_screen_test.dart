import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sana_app/features/ml_dictionary/models/term_models.dart';
import 'package:sana_app/features/ml_dictionary/screens/terms_screen.dart';
import 'package:sana_app/features/ml_dictionary/services/dictionary_preferences_service.dart';
import 'package:sana_app/features/ml_dictionary/services/ml_dictionary_service.dart';

class _FakeTermsService extends MlDictionaryService {
  @override
  Future<List<TermSummary>> getTerms() async => const [
    TermSummary(
      labTest: 'CRP',
      title: 'C-Reaktif Protein',
      sections: ['Nedir?'],
    ),
  ];
}

class _NeverCompletingPreferences extends DictionaryPreferencesService {
  @override
  Future<Set<String>> loadFavorites() async => <String>{};

  @override
  Future<List<String>> loadRecent() async => <String>[];

  @override
  Future<List<String>> addRecent(String labTest) =>
      Completer<List<String>>().future;

  @override
  Future<void> setFavorite(String labTest, bool favorite) =>
      Completer<void>().future;
}

class _PushObserver extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
    super.didPush(route, previousRoute);
  }
}

void main() {
  testWidgets('term opens without waiting for local storage', (tester) async {
    final observer = _PushObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: TermsScreen(
          service: _FakeTermsService(),
          preferences: _NeverCompletingPreferences(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('CRP'));
    await tester.pump();

    expect(observer.pushes, 2);
  });

  testWidgets('favorite icon changes immediately without waiting for storage', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TermsScreen(
          service: _FakeTermsService(),
          preferences: _NeverCompletingPreferences(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Favorilere ekle'));
    await tester.pump();

    expect(find.byTooltip('Favorilerden çıkar'), findsOneWidget);
    expect(find.text('Favoriler (1)'), findsOneWidget);
  });
}
