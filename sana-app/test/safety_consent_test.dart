import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sana_app/features/ml_dictionary/screens/safety_consent_screen.dart';

import 'test_surface.dart';

void main() {
  testWidgets('Safety consent requires the checkbox before continuing', (
    tester,
  ) async {
    useRoomyTestSurface(tester);
    var accepted = false;

    await tester.pumpWidget(
      MaterialApp(home: SafetyConsentScreen(onAccepted: () => accepted = true)),
    );

    final buttonFinder = find.widgetWithText(
      FilledButton,
      'Uygulamaya devam et',
    );
    expect(tester.widget<FilledButton>(buttonFinder).onPressed, isNull);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    expect(tester.widget<FilledButton>(buttonFinder).onPressed, isNotNull);
    await tester.tap(buttonFinder);
    expect(accepted, isTrue);
  });
}
