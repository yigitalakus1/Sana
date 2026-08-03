import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class UserProfile {
  const UserProfile({this.age, this.sex});

  final int? age;
  final String? sex;

  bool get isEmpty => age == null && (sex == null || sex!.isEmpty);

  Map<String, dynamic> toJson() => <String, dynamic>{
    if (age != null) 'age': age,
    if (sex != null && sex!.isNotEmpty) 'sex': sex,
  };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    age: (json['age'] as num?)?.toInt(),
    sex: json['sex']?.toString(),
  );
}

class UserProfileService {
  static const _storageKey = 'sana_user_profile_v1';

  Future<UserProfile> load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final encoded = preferences.getString(_storageKey);
      if (encoded == null || encoded.isEmpty) return const UserProfile();
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return const UserProfile();
      return UserProfile.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return const UserProfile();
    }
  }

  Future<void> save(UserProfile profile) async {
    final preferences = await SharedPreferences.getInstance();
    if (profile.isEmpty) {
      await preferences.remove(_storageKey);
      return;
    }
    await preferences.setString(_storageKey, jsonEncode(profile.toJson()));
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_storageKey);
  }
}
