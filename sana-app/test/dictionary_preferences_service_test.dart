import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sana_app/features/ml_dictionary/services/dictionary_preferences_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test(
    'dictionary preferences keep favorites and recent terms locally',
    () async {
      final service = DictionaryPreferencesService();

      await service.setFavorite('CRP', true);
      await service.setFavorite('B12', true);
      expect(await service.loadFavorites(), {'B12', 'CRP'});

      await service.setFavorite('CRP', false);
      expect(await service.loadFavorites(), {'B12'});

      await service.addRecent('CRP');
      await service.addRecent('B12');
      await service.addRecent('CRP');
      expect(await service.loadRecent(), ['CRP', 'B12']);
    },
  );
}
