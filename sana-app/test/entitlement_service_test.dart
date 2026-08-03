import 'package:flutter_test/flutter_test.dart';

import 'package:sana_app/core/entitlements/app_entitlement.dart';
import 'package:sana_app/core/entitlements/entitlement_service.dart';

void main() {
  test('varsayılan entitlement free döner', () async {
    const service = DefaultEntitlementService();

    final entitlement = await service.load();

    expect(entitlement.tier, AccessTier.free);
    expect(entitlement.isPremium, isFalse);
  });

  test('free entitlement premium yetkisi vermez', () {
    const entitlement = AppEntitlement.free();

    expect(entitlement.tier, AccessTier.free);
    expect(entitlement.isPremium, isFalse);
    expect(entitlement.source, 'default');
  });

  test('premium entitlement kaynağıyla birlikte taşınır', () {
    const entitlement = AppEntitlement(
      tier: AccessTier.premium,
      source: 'test',
    );

    expect(entitlement.isPremium, isTrue);
    expect(entitlement.source, 'test');
  });
}
