import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sana_app/core/network/sana_api_client.dart';
import 'package:sana_app/core/profile/user_profile_service.dart';
import 'package:sana_app/features/ml_dictionary/screens/profile_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('profile is stored and cleared locally', () async {
    final service = UserProfileService();

    await service.save(const UserProfile(age: 34, sex: 'female'));
    final profile = await service.load();

    expect(profile.age, 34);
    expect(profile.sex, 'female');

    await service.clear();
    expect((await service.load()).isEmpty, isTrue);
  });

  test('explain request includes the optional profile', () async {
    Map<String, dynamic>? requestBody;
    final client = SanaApiClient(
      client: MockClient((request) async {
        requestBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{}', 200);
      }),
    );

    await client.explain(
      question: 'CRP 13.5 çıktı',
      profile: const UserProfile(age: 34, sex: 'female').toJson(),
    );

    expect(requestBody?['profile'], <String, dynamic>{
      'age': 34,
      'sex': 'female',
    });
  });

  testWidgets('profile validates age and saves valid values', (tester) async {
    final service = _FakeProfileService();
    await tester.pumpWidget(MaterialApp(home: ProfileScreen(service: service)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('profile-age')), '121');
    await tester.tap(find.widgetWithText(FilledButton, 'Kaydet'));
    await tester.pump();
    expect(find.text('Yaş 0 ile 120 arasında olmalıdır.'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('profile-age')), '42');
    await tester.tap(find.widgetWithText(FilledButton, 'Kaydet'));
    await tester.pumpAndSettle();

    expect(service.saved?.age, 42);
    expect(find.text('Profil bu cihazda kaydedildi.'), findsOneWidget);
  });
}

class _FakeProfileService extends UserProfileService {
  UserProfile? saved;

  @override
  Future<UserProfile> load() async => const UserProfile();

  @override
  Future<void> save(UserProfile profile) async => saved = profile;

  @override
  Future<void> clear() async => saved = null;
}
