import 'package:shared_preferences/shared_preferences.dart';

class DictionaryPreferencesService {
  static const _favoritesKey = 'sana_dictionary_favorites_v1';
  static const _recentKey = 'sana_dictionary_recent_v1';

  Future<Set<String>> loadFavorites() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getStringList(_favoritesKey)?.toSet() ?? <String>{};
  }

  Future<List<String>> loadRecent() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getStringList(_recentKey) ?? <String>[];
  }

  Future<void> setFavorite(String labTest, bool favorite) async {
    final preferences = await SharedPreferences.getInstance();
    final favorites =
        preferences.getStringList(_favoritesKey)?.toSet() ?? <String>{};
    favorite ? favorites.add(labTest) : favorites.remove(labTest);
    final values = favorites.toList()..sort();
    await preferences.setStringList(_favoritesKey, values);
  }

  Future<List<String>> addRecent(String labTest) async {
    final preferences = await SharedPreferences.getInstance();
    final recent = preferences.getStringList(_recentKey) ?? <String>[];
    recent
      ..remove(labTest)
      ..insert(0, labTest);
    if (recent.length > 6) recent.removeRange(6, recent.length);
    await preferences.setStringList(_recentKey, recent);
    return recent;
  }
}
