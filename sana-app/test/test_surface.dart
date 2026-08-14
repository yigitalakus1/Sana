// Widget testleri için gerçekçi bir ekran yüzeyi.
//
// `flutter_test`'in varsayılanı 800x600 mantıksal pikseldir; böyle bir telefon
// yoktur ve bazı ekranlar bu yüksekliğe **piksel payıyla** sığar. Ölçüldü:
// güvenlik onayı ekranında "Uygulamaya devam et" butonunun alt kenarı 599 px,
// yüzey 600 px — yani 1 px pay. Platformlar arası küçük metin metrik farkları
// (Windows'ta geçen testler Linux CI'da kırıldı) butonu ekran dışına itiyor ve
// `tester.tap` ıskalıyor.
//
// Genişlik 800'de bırakılır: daraltmak `ResponsiveCenter` kırılım noktalarını
// değiştirir ve testlerin doğruladığı yerleşimi bozar. Yalnız yükseklik
// gerçekçi bir değere çıkarılır.
//
// Not: taşmayı bilerek arayan testler (`release_readiness_test.dart`) kendi dar
// telefon yüzeyini kullanır; buradaki yardımcıyı kullanmamalıdır.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Testi, dokunma hedeflerinin ekran dışında kalmayacağı bir yüzeyde koşturur.
///
/// Test bitince yüzey otomatik olarak eski hâline döner.
void useRoomyTestSurface(
  WidgetTester tester, {
  Size size = const Size(800, 1600),
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
