import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/report_parse_models.dart';

/// Geri yükleme sonucu: dosyadaki geçerli kayıt sayısı ve ne kadarının
/// eklendiği. Hiçbir kayıt silinmez; aynı `id` zaten varsa atlanır.
class HistoryImportResult {
  const HistoryImportResult({
    required this.added,
    required this.duplicate,
    required this.skipped,
  });

  final int added;
  final int duplicate;

  /// Biçimi bozuk olduğu için alınmayan kayıtlar.
  final int skipped;

  int get total => added + duplicate + skipped;
}

/// Geri yükleme dosyası okunamadığında atılır. Mesaj kullanıcıya gösterilir.
class HistoryImportException implements Exception {
  const HistoryImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ReportHistoryService {
  static const _storageKey = 'sana_report_history_v1';
  static const _maxReports = 100;
  static const _storageTimeout = Duration(seconds: 2);
  static final List<ReportHistoryEntry> _sessionEntries = [];
  static Future<void> _writeQueue = Future<void>.value();

  Future<SharedPreferences> _preferences() =>
      SharedPreferences.getInstance().timeout(_storageTimeout);

  List<ReportHistoryEntry> _decode(String? encoded) {
    if (encoded == null || encoded.isEmpty) return <ReportHistoryEntry>[];
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return <ReportHistoryEntry>[];
      return decoded
          .whereType<Map>()
          .map(
            (item) =>
                ReportHistoryEntry.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((entry) => entry.results.isNotEmpty)
          .toList();
    } catch (_) {
      return <ReportHistoryEntry>[];
    }
  }

  List<ReportHistoryEntry> _merge(Iterable<ReportHistoryEntry> entries) {
    final byId = <String, ReportHistoryEntry>{
      for (final entry in entries) entry.id: entry,
      for (final entry in _sessionEntries) entry.id: entry,
    };
    final merged = byId.values.toList()
      ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return merged.take(_maxReports).toList();
  }

  Future<List<ReportHistoryEntry>> load() async {
    try {
      final preferences = await _preferences();
      return _merge(_decode(preferences.getString(_storageKey)));
    } catch (_) {
      return _merge(const <ReportHistoryEntry>[]);
    }
  }

  Future<ReportHistoryEntry> save({
    required String sourceName,
    required List<ParsedLabResult> results,
    DateTime? reportDate,
  }) async {
    final now = DateTime.now();
    final entry = ReportHistoryEntry(
      id: _nextId(now),
      createdAt: now,
      sourceName: sourceName,
      results: List<ParsedLabResult>.of(results),
      reportDate: reportDate,
    );
    _sessionEntries.insert(0, entry);
    if (_sessionEntries.length > _maxReports) {
      _sessionEntries.removeRange(_maxReports, _sessionEntries.length);
    }
    unawaited(_enqueueWrite(() => _persistEntry(entry)));
    return entry;
  }

  /// Çakışmayan kayıt kimliği üretir.
  ///
  /// Yalnız `DateTime.now().microsecondsSinceEpoch` kullanmak yeterli değildi:
  /// bazı platformlarda saat çözünürlüğü kaba olduğu için arka arkaya kaydedilen
  /// iki rapor aynı kimliği alıp birbirini eziyordu (sessiz veri kaybı).
  static int _lastIdMicros = 0;

  static String _nextId(DateTime now) {
    var micros = now.microsecondsSinceEpoch;
    if (micros <= _lastIdMicros) micros = _lastIdMicros + 1;
    _lastIdMicros = micros;
    return micros.toString();
  }

  Future<void> _enqueueWrite(Future<void> Function() operation) {
    _writeQueue = _writeQueue.then((_) => operation());
    return _writeQueue;
  }

  Future<void> _persistEntry(ReportHistoryEntry entry) async {
    try {
      final preferences = await _preferences();
      final entries = _decode(preferences.getString(_storageKey));
      entries.removeWhere((item) => item.id == entry.id);
      entries.insert(0, entry);
      await _write(preferences, _merge(entries));
    } catch (_) {
      // Oturum geçmişi çalışmaya devam eder; kalıcı depolama zorunlu değildir.
    }
  }

  /// Kullanıcının rapora verdiği adı günceller. `null` veya boş değer etiketi
  /// kaldırır ve rapor yeniden dosya adıyla görünür. Rapor içeriği değişmez.
  Future<void> updateLabel(String id, String? label) async {
    final index = _sessionEntries.indexWhere((entry) => entry.id == id);
    if (index != -1) {
      _sessionEntries[index] = _sessionEntries[index].withLabel(label);
    }
    await _enqueueWrite(() => _persistLabel(id, label));
  }

  Future<void> _persistLabel(String id, String? label) async {
    try {
      final preferences = await _preferences();
      final entries = _decode(preferences.getString(_storageKey));
      final index = entries.indexWhere((entry) => entry.id == id);
      if (index == -1) return;
      entries[index] = entries[index].withLabel(label);
      await _write(preferences, entries);
    } catch (_) {
      // Oturum içindeki etiket yine güncellenmiştir.
    }
  }

  Future<void> delete(String id) async {
    _sessionEntries.removeWhere((entry) => entry.id == id);
    await _enqueueWrite(() => _deletePersisted(id));
  }

  Future<void> _deletePersisted(String id) async {
    try {
      final preferences = await _preferences();
      final entries = _decode(preferences.getString(_storageKey))
        ..removeWhere((entry) => entry.id == id);
      await _write(preferences, entries);
    } catch (_) {
      // Ekrandaki oturum kaydı yine silinmiştir.
    }
  }

  Future<void> clear() async {
    _sessionEntries.clear();
    await _enqueueWrite(_clearPersisted);
  }

  // --- Dışa aktarma / geri yükleme ----------------------------------------
  //
  // Dosya yalnız kullanıcının seçtiği konuma yazılır; uygulama kendi alanında
  // bir kopya tutmaz ve geçici dosya bırakmaz.

  static const int exportFormatVersion = 1;

  /// Rapor geçmişini paylaşılabilir bir JSON metnine çevirir.
  /// Metin yalnız bellekte üretilir; diske burada bir şey yazılmaz.
  Future<String> exportJson() async {
    final entries = await load();
    return jsonEncode(<String, dynamic>{
      'app': 'sana',
      'type': 'report_history',
      'version': exportFormatVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'entries': entries.map((entry) => entry.toJson()).toList(),
    });
  }

  /// Dışa aktarılmış JSON metnini geri yükler.
  ///
  /// Mevcut kayıtlar **silinmez**: aynı `id` zaten varsa dokunulmaz, yalnız
  /// yeni kayıtlar eklenir. Dosya okunamazsa [HistoryImportException] atar.
  Future<HistoryImportResult> importJson(String raw) async {
    final dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      throw const HistoryImportException(
        'Dosya okunamadı. Sana ile dışa aktarılmış bir JSON dosyası seçin.',
      );
    }

    final List<dynamic> rawEntries;
    if (decoded is Map && decoded['entries'] is List) {
      rawEntries = decoded['entries'] as List;
    } else if (decoded is List) {
      // Ham depolama listesi de kabul edilir.
      rawEntries = decoded;
    } else {
      throw const HistoryImportException(
        'Bu dosya bir Sana rapor geçmişi dosyasına benzemiyor.',
      );
    }

    var skipped = 0;
    final parsed = <ReportHistoryEntry>[];
    for (final item in rawEntries) {
      if (item is! Map) {
        skipped++;
        continue;
      }
      try {
        final entry = ReportHistoryEntry.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (entry.id.isEmpty || entry.results.isEmpty) {
          skipped++;
          continue;
        }
        parsed.add(entry);
      } catch (_) {
        skipped++;
      }
    }

    if (parsed.isEmpty) {
      throw const HistoryImportException(
        'Dosyada geri yüklenebilecek rapor bulunamadı.',
      );
    }

    final existing = await load();
    final existingIds = existing.map((entry) => entry.id).toSet();
    final fresh = parsed
        .where((entry) => !existingIds.contains(entry.id))
        .toList();

    if (fresh.isNotEmpty) {
      await _enqueueWrite(() => _persistImported(fresh));
    }

    return HistoryImportResult(
      added: fresh.length,
      duplicate: parsed.length - fresh.length,
      skipped: skipped,
    );
  }

  Future<void> _persistImported(List<ReportHistoryEntry> imported) async {
    try {
      final preferences = await _preferences();
      final entries = _decode(preferences.getString(_storageKey));
      final knownIds = entries.map((entry) => entry.id).toSet();
      entries.addAll(imported.where((entry) => !knownIds.contains(entry.id)));
      entries.sort((left, right) => right.createdAt.compareTo(left.createdAt));
      await _write(preferences, entries.take(_maxReports).toList());
    } catch (_) {
      // Yazılamazsa mevcut geçmiş bozulmaz.
    }
  }

  Future<void> _clearPersisted() async {
    try {
      final preferences = await _preferences();
      await preferences.remove(_storageKey).timeout(_storageTimeout);
    } catch (_) {
      // Oturum geçmişi temiz kalır.
    }
  }

  Future<void> _write(
    SharedPreferences preferences,
    List<ReportHistoryEntry> entries,
  ) async {
    await preferences
        .setString(
          _storageKey,
          jsonEncode(entries.map((entry) => entry.toJson()).toList()),
        )
        .timeout(_storageTimeout);
  }
}
