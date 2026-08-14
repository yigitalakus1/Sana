// Cihaz üzerinde OCR sözleşmesi.
//
// Gerçek kamera, gerçek ML Kit veya ağ kullanılmaz: motor ve görüntü seçici
// arayüz arkasında olduğu için tüm akış sahtelerle doğrulanabiliyor.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sana_app/features/ml_dictionary/services/local_ocr_service.dart';

class _FakeEngine implements OcrEngine {
  _FakeEngine({this.text = 'CRP 13.5 mg/L', this.throwOnRecognize = false});

  final String text;
  final bool throwOnRecognize;
  final List<String> recognized = [];
  bool disposed = false;

  @override
  Future<String> recognize(String imagePath) async {
    recognized.add(imagePath);
    if (throwOnRecognize) throw StateError('motor hatası');
    return text;
  }

  @override
  Future<void> dispose() async => disposed = true;
}

class _FakeSource implements OcrImageSource {
  _FakeSource({this.path, this.error});

  final String? path;
  final Object? error;
  final List<OcrSource> requested = [];

  @override
  Future<String?> pickPath(OcrSource source) async {
    requested.add(source);
    if (error != null) throw error!;
    return path;
  }
}

/// Gerçek bir geçici dosya üretir; servis silme davranışı da test edilebilsin.
File makeTempImage() {
  final file = File(
    '${Directory.systemTemp.path}/sana_ocr_test_'
    '${DateTime.now().microsecondsSinceEpoch}.jpg',
  );
  file.writeAsBytesSync(List<int>.filled(16, 0));
  return file;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // OCR yalnız mobilde desteklenir; testler Android'i taklit eder.
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('kameradan okunan metin döner', () async {
    final image = makeTempImage();
    final engine = _FakeEngine(text: 'CRP 13.5 mg/L');
    final service = LocalOcrService(
      engine: engine,
      imageSource: _FakeSource(path: image.path),
    );

    final text = await service.scan(OcrSource.camera);

    expect(text, contains('CRP'));
    expect(engine.recognized, [image.path]);
  });

  test('galeri seçimi kamera akışını kullanmaz', () async {
    final image = makeTempImage();
    final source = _FakeSource(path: image.path);
    final service = LocalOcrService(engine: _FakeEngine(), imageSource: source);

    await service.scan(OcrSource.gallery);

    // Galeri istendiğinde kamera kaynağı hiç talep edilmemeli; kamera izni
    // ancak kamera akışında gündeme gelir.
    expect(source.requested, [OcrSource.gallery]);
    expect(source.requested, isNot(contains(OcrSource.camera)));
  });

  test('okuma bittiğinde görüntü silinir', () async {
    final image = makeTempImage();
    expect(image.existsSync(), isTrue);

    await LocalOcrService(
      engine: _FakeEngine(),
      imageSource: _FakeSource(path: image.path),
    ).scan(OcrSource.camera);

    expect(
      image.existsSync(),
      isFalse,
      reason: 'uygulama rapor fotoğrafını saklamamalı',
    );
  });

  test('okuma hata verse bile görüntü silinir', () async {
    final image = makeTempImage();

    try {
      await LocalOcrService(
        engine: _FakeEngine(throwOnRecognize: true),
        imageSource: _FakeSource(path: image.path),
      ).scan(OcrSource.camera);
    } on OcrException catch (error) {
      expect(error.reason, OcrFailure.failed);
    }

    expect(image.existsSync(), isFalse);
  });

  group('kontrollü hatalar', () {
    test('kullanıcı vazgeçerse hata gösterilmez', () async {
      final service = LocalOcrService(
        engine: _FakeEngine(),
        imageSource: _FakeSource(),
      );

      try {
        await service.scan(OcrSource.camera);
        fail('vazgeçme sinyali bekleniyordu');
      } on OcrException catch (error) {
        expect(error.reason, OcrFailure.cancelled);
        expect(error.isCancellation, isTrue);
        expect(error.needsSettings, isFalse);
      }
    });

    test('izin reddi çökmez, Ayarlar’a yönlendirir', () async {
      final service = LocalOcrService(
        engine: _FakeEngine(),
        imageSource: _FakeSource(
          error: PlatformExceptionLike('camera_access_denied'),
        ),
      );

      try {
        await service.scan(OcrSource.camera);
        fail('izin hatası bekleniyordu');
      } on OcrException catch (error) {
        expect(error.reason, OcrFailure.permissionDenied);
        expect(error.needsSettings, isTrue);
        expect(error.message.toLowerCase(), contains('ayar'));
      }
    });

    test('görüntüde yazı yoksa açık mesaj verilir', () async {
      final image = makeTempImage();
      final service = LocalOcrService(
        engine: _FakeEngine(text: '   \n  \n'),
        imageSource: _FakeSource(path: image.path),
      );

      try {
        await service.scan(OcrSource.camera);
        fail('boş metin hatası bekleniyordu');
      } on OcrException catch (error) {
        expect(error.reason, OcrFailure.noText);
        expect(error.message, contains('okunabilir yazı bulunamadı'));
      }
    });

    test('masaüstünde kontrollü biçimde reddedilir', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      try {
        await LocalOcrService(
          engine: _FakeEngine(),
          imageSource: _FakeSource(path: 'x.jpg'),
        ).scan(OcrSource.camera);
        fail('desteklenmiyor hatası bekleniyordu');
      } on OcrException catch (error) {
        expect(error.reason, OcrFailure.unsupportedPlatform);
      }
    });
  });

  group('gizlilik', () {
    test('hata mesajları teknik ayrıntı sızdırmaz', () async {
      final service = LocalOcrService(
        engine: _FakeEngine(),
        imageSource: _FakeSource(error: StateError('C:\\gizli\\yol.jpg')),
      );

      try {
        await service.scan(OcrSource.camera);
        fail('hata bekleniyordu');
      } on OcrException catch (error) {
        expect(error.message, isNot(contains('gizli')));
        expect(error.message, isNot(contains('.jpg')));
        expect(error.message, isNot(contains('Error')));
      }
    });
  });

  test('supported masaüstünde false, Android’de true', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(LocalOcrService.supported, isTrue);

    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(LocalOcrService.supported, isFalse);
  });
}

/// `PlatformException` yerine kullanılan hafif taklit: paket bağımlılığı
/// olmadan aynı mesaj biçimini üretir.
class PlatformExceptionLike implements Exception {
  PlatformExceptionLike(this.code);

  final String code;

  @override
  String toString() => 'PlatformException($code, null, null, null)';
}
