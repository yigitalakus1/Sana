// PDF'in metin katmanını **cihaz üzerinde** okur; ağ kullanılmaz.
//
// Amaç, sağlık verisinin cihazdan çıkmaması. Metin katmanı bulunan PDF'ler
// burada çözülür ve doğrudan `LocalReportParser`'a gider; backend çağrılmaz.
// Taranmış (yalnız görüntü içeren) PDF'ler burada çözülemez — bu durum
// "sonuç bulunamadı" gibi gizlenmez, kullanıcıya açıkça OCR önerilir.
//
// Kullanılan paket saf Dart'tır (native bileşen yok), bu yüzden Android, web
// ve Windows'ta aynı kodla çalışır.

import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

/// PDF okunamadığında nedenini ayırt eder. UI buna göre farklı yönlendirme
/// yapar; özellikle [noTextLayer] bir hata değil, OCR'a yönlendirme sebebidir.
enum PdfExtractionFailure {
  /// Dosya 10 MB sınırını aşıyor.
  tooLarge,

  /// Dosya boş ya da hiç veri okunamadı.
  empty,

  /// Parola korumalı; içeriği açılamaz.
  encrypted,

  /// PDF yapısı bozuk veya bu bir PDF değil.
  corrupt,

  /// Geçerli PDF ama metin katmanı yok — taranmış görüntü.
  noTextLayer,
}

/// Kullanıcıya gösterilebilecek, teknik ayrıntı içermeyen PDF hatası.
///
/// [message] doğrudan ekrana yazılabilir: dosya yolu, stack trace veya paket
/// içi hata metni sızdırmaz.
class PdfExtractionException implements Exception {
  const PdfExtractionException(this.reason, this.message);

  final PdfExtractionFailure reason;
  final String message;

  /// Taranmış PDF'te kullanıcı OCR'a yönlendirilir.
  bool get suggestsOcr => reason == PdfExtractionFailure.noTextLayer;

  @override
  String toString() => message;
}

class LocalPdfTextExtractor {
  const LocalPdfTextExtractor();

  /// Kabul edilen en büyük dosya. Daha büyüğü belleğe alınmaz.
  static const int maxBytes = 10 * 1024 * 1024;

  /// Her PDF'in başında bulunan imza. Yanlış dosya türü, paketi hiç
  /// çalıştırmadan burada elenir.
  static const List<int> _signature = [0x25, 0x50, 0x44, 0x46]; // %PDF

  /// Metin katmanını döndürür.
  ///
  /// Başarısız olursa [PdfExtractionException] atar; çağıran taraf
  /// `reason` alanına göre OCR önerir ya da hatayı gösterir.
  Future<String> extractText(Uint8List bytes) async {
    _guardSize(bytes);

    // Ayrıştırma senkron ve CPU'ya bağlı. Bir kare beklemek, çağıranın
    // yükleniyor göstergesini çizmesine izin verir (web'de tek iş parçacığı).
    await Future<void>.delayed(Duration.zero);

    PdfDocument? document;
    try {
      document = PdfDocument(inputBytes: bytes);
    } catch (error) {
      throw _openFailure(bytes, error);
    }

    try {
      final text = PdfTextExtractor(document).extractText();
      if (!_hasReadableContent(text)) {
        throw const PdfExtractionException(
          PdfExtractionFailure.noTextLayer,
          'Bu PDF taranmış görüntü içeriyor. Kamera/OCR ile taramayı deneyin.',
        );
      }
      return text;
    } on PdfExtractionException {
      rethrow;
    } catch (_) {
      // Belge açıldı ama metin çıkarılamadı: yapı bozuk olabilir.
      throw const PdfExtractionException(
        PdfExtractionFailure.corrupt,
        'PDF dosyası okunamadı. Dosya bozuk olabilir.',
      );
    } finally {
      document.dispose();
    }
  }

  void _guardSize(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw const PdfExtractionException(
        PdfExtractionFailure.empty,
        'PDF dosyası boş görünüyor.',
      );
    }
    if (bytes.length > maxBytes) {
      throw const PdfExtractionException(
        PdfExtractionFailure.tooLarge,
        'PDF dosyası en fazla 10 MB olabilir.',
      );
    }
  }

  /// Açma hatasını sınıflandırır.
  ///
  /// Paketin hata metnine tek başına güvenilmez; parola koruması dosyanın
  /// kendisinde `/Encrypt` girdisiyle de aranır.
  PdfExtractionException _openFailure(Uint8List bytes, Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('encrypt') || message.contains('password')) {
      return const PdfExtractionException(
        PdfExtractionFailure.encrypted,
        'Bu PDF parola korumalı. Korumayı kaldırıp tekrar deneyin.',
      );
    }
    if (!_looksLikePdf(bytes)) {
      return const PdfExtractionException(
        PdfExtractionFailure.corrupt,
        'Bu dosya geçerli bir PDF değil.',
      );
    }
    if (_hasEncryptEntry(bytes)) {
      return const PdfExtractionException(
        PdfExtractionFailure.encrypted,
        'Bu PDF parola korumalı. Korumayı kaldırıp tekrar deneyin.',
      );
    }
    return const PdfExtractionException(
      PdfExtractionFailure.corrupt,
      'PDF dosyası okunamadı. Dosya bozuk olabilir.',
    );
  }

  static bool _looksLikePdf(Uint8List bytes) {
    if (bytes.length < _signature.length) return false;
    for (var index = 0; index < _signature.length; index++) {
      if (bytes[index] != _signature[index]) return false;
    }
    return true;
  }

  /// Trailer'daki `/Encrypt` girdisini arar. Bayt düzeyinde bakılır; belgenin
  /// açılmış olması gerekmez.
  static bool _hasEncryptEntry(Uint8List bytes) {
    const needle = [0x2F, 0x45, 0x6E, 0x63, 0x72, 0x79, 0x70, 0x74]; // /Encrypt
    final limit = bytes.length - needle.length;
    for (var start = 0; start <= limit; start++) {
      var matched = true;
      for (var offset = 0; offset < needle.length; offset++) {
        if (bytes[start + offset] != needle[offset]) {
          matched = false;
          break;
        }
      }
      if (matched) return true;
    }
    return false;
  }

  /// Metin katmanının gerçekten içerik taşıyıp taşımadığı.
  ///
  /// Taranmış PDF'ler çoğu zaman boş dize yerine yalnız boşluk/satır sonu
  /// döndürür; harf veya rakam yoksa okunabilir metin yok sayılır.
  static bool _hasReadableContent(String text) =>
      RegExp(r'[0-9A-Za-zçğıöşüÇĞİÖŞÜ]').hasMatch(text);
}
