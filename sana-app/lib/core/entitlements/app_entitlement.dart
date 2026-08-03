/// Uygulama içi erişim seviyesi.
///
/// `free` üretim varsayılanıdır; `premium` yalnız doğrulanmış bir kaynaktan
/// gelebilir. Sağlık güvenliği özellikleri (safety block, disclaimer,
/// kaynaklar, tek raporun açıklaması) hiçbir zaman bu ayrımın arkasına
/// konmaz.
enum AccessTier { free, premium }

/// Tek bir erişim kararı: hangi seviye ve kararın nereden geldiği.
///
/// [source] yalnız tanılama/log amaçlıdır; erişim kararı her zaman [tier]
/// üzerinden verilir.
class AppEntitlement {
  const AppEntitlement({required this.tier, required this.source});

  /// Üretim varsayılanı.
  const AppEntitlement.free({this.source = 'default'}) : tier = AccessTier.free;

  final AccessTier tier;
  final String source;

  bool get isPremium => tier == AccessTier.premium;
}
