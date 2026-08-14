// Kamera/galeri görüntüsünden **cihaz üzerinde** metin okur.
//
// Metin tanıma ML Kit'in cihaza gömülü Latin modeliyle yapılır: bulut OCR yok,
// API anahtarı yok, ilk kullanımda model indirme yok. Görüntü hiçbir zaman
// sunucuya gönderilmez ve okuma bittiğinde geçici dosya silinir — uygulama
// fotoğrafı saklamaz.
//
// Motor ve görüntü seçici arayüz arkasındadır; testler gerçek kamera ya da
// ML Kit olmadan tüm akışı doğrulayabilir.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

/// Görüntünün nereden geleceği.
enum OcrSource { camera, gallery }

enum OcrFailure {
  /// Masaüstü/web'de cihaz üzerinde OCR yok.
  unsupportedPlatform,

  /// Kamera veya galeri izni verilmedi.
  permissionDenied,

  /// Kullanıcı seçimden vazgeçti.
  cancelled,

  /// Görüntü okundu ama içinde metin bulunamadı.
  noText,

  /// Beklenmeyen okuma hatası.
  failed,
}

/// Kullanıcıya gösterilebilecek, teknik ayrıntı içermeyen OCR hatası.
class OcrException implements Exception {
  const OcrException(this.reason, this.message);

  final OcrFailure reason;
  final String message;

  /// İzin reddedildiyse kullanıcı Ayarlar'a yönlendirilir.
  bool get needsSettings => reason == OcrFailure.permissionDenied;

  /// Vazgeçme bir hata değildir; ekranda uyarı gösterilmez.
  bool get isCancellation => reason == OcrFailure.cancelled;

  @override
  String toString() => message;
}

/// Görüntüden metin çıkaran motor.
abstract class OcrEngine {
  Future<String> recognize(String imagePath);
  Future<void> dispose();
}

/// Görüntü dosyası seçtiren katman. Yol döner, `null` = vazgeçildi.
abstract class OcrImageSource {
  Future<String?> pickPath(OcrSource source);
}

/// ML Kit'in cihaza gömülü Latin metin tanıyıcısı.
class MlKitOcrEngine implements OcrEngine {
  TextRecognizer? _recognizer;

  @override
  Future<String> recognize(String imagePath) async {
    final recognizer =
        _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
    final recognized = await recognizer.processImage(
      InputImage.fromFilePath(imagePath),
    );
    return recognized.text;
  }

  @override
  Future<void> dispose() async {
    await _recognizer?.close();
    _recognizer = null;
  }
}

/// `image_picker` tabanlı seçici.
///
/// Kamera yolu sistemin kamera uygulamasını açar; galeri yolu Android 13+'ta
/// Foto Seçici'yi kullanır. İkisi ayrı akışlardır, bu yüzden galeriden seçim
/// kamera izni istemez.
class PickerOcrImageSource implements OcrImageSource {
  PickerOcrImageSource({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<String?> pickPath(OcrSource source) async {
    final file = await _picker.pickImage(
      source: source == OcrSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      // Rapor fotoğrafında küçük yazılar okunabilsin diye çözünürlük
      // düşürülmez; yalnız aşırı büyük görüntüler sınırlanır.
      maxWidth: 3000,
      imageQuality: 95,
    );
    return file?.path;
  }
}

class LocalOcrService {
  LocalOcrService({OcrEngine? engine, OcrImageSource? imageSource})
    : _engine = engine ?? MlKitOcrEngine(),
      _imageSource = imageSource ?? PickerOcrImageSource();

  final OcrEngine _engine;
  final OcrImageSource _imageSource;

  /// Cihaz üzerinde OCR yalnız mobilde vardır.
  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Örnek üzerinden sorulabilen sürüm.
  ///
  /// UI bunu kullanır; böylece widget testleri global `defaultTargetPlatform`
  /// değişkenini değiştirmek zorunda kalmaz (flutter_test bunu test gövdesi
  /// biterken sıfırlanmış görmek ister).
  bool get isSupported => supported;

  /// Seçilen görüntüden metni okur.
  ///
  /// Görüntü okuma bittiğinde silinir; uygulama kopya tutmaz ve hiçbir aşamada
  /// sunucuya gönderilmez.
  Future<String> scan(OcrSource source) async {
    if (!supported) {
      throw const OcrException(
        OcrFailure.unsupportedPlatform,
        'Bu cihazda kamerayla tarama desteklenmiyor. Rapor metnini elle '
        'yazabilirsin.',
      );
    }

    final String? path;
    try {
      path = await _imageSource.pickPath(source);
    } catch (error) {
      throw _pickFailure(source, error);
    }
    if (path == null) {
      throw const OcrException(
        OcrFailure.cancelled,
        'Görüntü seçilmedi.',
      );
    }

    try {
      final text = await _engine.recognize(path);
      if (!_hasReadableContent(text)) {
        throw const OcrException(
          OcrFailure.noText,
          'Görüntüde okunabilir yazı bulunamadı. Daha yakından ve iyi ışıkta '
          'tekrar deneyin.',
        );
      }
      return text;
    } on OcrException {
      rethrow;
    } catch (_) {
      throw const OcrException(
        OcrFailure.failed,
        'Görüntü okunamadı. Tekrar deneyin.',
      );
    } finally {
      // Gizlilik: geçici görüntü uygulamada birikmesin.
      await _deleteQuietly(path);
    }
  }

  Future<void> dispose() => _engine.dispose();

  /// Seçim hatasını sınıflandırır; izin reddi ayrı ele alınır çünkü kullanıcı
  /// Ayarlar'a yönlendirilmelidir.
  OcrException _pickFailure(OcrSource source, Object error) {
    final message = error.toString().toLowerCase();
    final denied =
        message.contains('access_denied') ||
        message.contains('permission') ||
        message.contains('denied');
    if (denied) {
      return OcrException(
        OcrFailure.permissionDenied,
        source == OcrSource.camera
            ? 'Kamera izni verilmedi. Telefon ayarlarından Sana uygulamasına '
                  'kamera izni verip tekrar deneyebilirsin.'
            : 'Galeri izni verilmedi. Telefon ayarlarından Sana uygulamasına '
                  'fotoğraf izni verip tekrar deneyebilirsin.',
      );
    }
    return const OcrException(
      OcrFailure.failed,
      'Görüntü seçilemedi. Tekrar deneyin.',
    );
  }

  static Future<void> _deleteQuietly(String path) async {
    if (kIsWeb) return;
    try {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    } catch (_) {
      // Silinemezse akış bozulmaz; dosya sistemin geçici alanındadır.
    }
  }

  static bool _hasReadableContent(String text) =>
      RegExp(r'[0-9A-Za-zçğıöşüÇĞİÖŞÜ]').hasMatch(text);
}
