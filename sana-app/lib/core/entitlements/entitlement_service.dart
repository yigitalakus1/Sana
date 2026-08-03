import 'package:flutter/foundation.dart';

import 'app_entitlement.dart';

/// Erişim seviyesini çözen katman.
///
/// Satın alma sağlayıcısından bağımsızdır: gerçek mağaza entegrasyonu
/// geldiğinde yalnız bu arayüzün yeni bir implementasyonu yazılır, ekranlar
/// değişmez. Testler constructor üzerinden sahte bir implementasyon verebilir.
abstract interface class EntitlementService {
  Future<AppEntitlement> load();
}

/// Üretimde kullanılan implementasyon.
///
/// Gerçek mağaza doğrulaması bulunmadığı sürece herkes `free`'dir. Cihazda
/// kalıcı bir `isPremium=true` bayrağı tutulmaz; böyle bir bayrak doğrulanmamış
/// bir üretim yetkisi taklidi olurdu.
class DefaultEntitlementService implements EntitlementService {
  const DefaultEntitlementService();

  /// Yalnız geliştirme sırasında premium ekranını görebilmek için kullanılan
  /// açık anahtar: `--dart-define=SANA_DEBUG_PREMIUM=true`.
  ///
  /// [kDebugMode] ile birlikte değerlendirildiği için release build bu değeri
  /// kabul etmez.
  static const bool _debugPremiumOverride = bool.fromEnvironment(
    'SANA_DEBUG_PREMIUM',
  );

  @override
  Future<AppEntitlement> load() async {
    if (kDebugMode && _debugPremiumOverride) {
      return const AppEntitlement(
        tier: AccessTier.premium,
        source: 'debug-override',
      );
    }
    return const AppEntitlement.free();
  }
}
