/// Backend taban URL'i — tek yerden yönetilir.
///
/// Varsayılan: `http://localhost:8000` (Windows desktop / web / iOS simulator).
/// Android emulator için çalıştırırken:
///   flutter run --dart-define=SANA_API_BASE_URL=http://10.0.2.2:8000
class ApiConfig {
  ApiConfig._();

  static const String baseUrl = String.fromEnvironment(
    'SANA_API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );
}
