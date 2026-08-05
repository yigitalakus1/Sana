import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/notifications/notification_service.dart';
import '../models/medication_reminder.dart';

/// Hatırlatıcıları cihazda saklar ve bildirimlerini kurar/iptal eder.
///
/// Veri cihazdan çıkmaz; sunucuya hiçbir şey gönderilmez.
class MedicationReminderService {
  MedicationReminderService({NotificationService? notifications})
    : _notifications = notifications ?? NotificationService.instance;

  final NotificationService _notifications;

  static const String _storageKey = 'sana_medication_reminders_v1';
  static const Duration _storageTimeout = Duration(seconds: 2);

  /// Bir hatırlatıcı gün içinde en çok 24 kez tekrar edebilir; bildirim
  /// kimlikleri bu blok içinde türetilir, böylece çakışma olmaz.
  static const int _idsPerReminder = 24;

  Future<SharedPreferences> _prefs() =>
      SharedPreferences.getInstance().timeout(_storageTimeout);

  Future<List<MedicationReminder>> load() async {
    try {
      final raw = (await _prefs()).getString(_storageKey);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(
            (item) =>
                MedicationReminder.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((item) => item.id.isNotEmpty && item.name.trim().isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _persist(List<MedicationReminder> items) async {
    try {
      await (await _prefs())
          .setString(
            _storageKey,
            jsonEncode(items.map((item) => item.toJson()).toList()),
          )
          .timeout(_storageTimeout);
    } catch (_) {
      // Kalıcı yazma başarısız olsa da ekrandaki liste tutarlı kalır.
    }
  }

  /// Kaydeder (yeni ya da güncel) ve bildirimlerini yeniden kurar.
  Future<List<MedicationReminder>> save(MedicationReminder reminder) async {
    final items = [...await load()];
    final index = items.indexWhere((item) => item.id == reminder.id);
    if (index == -1) {
      items.add(reminder);
    } else {
      items[index] = reminder;
    }
    await _persist(items);
    await _reschedule(reminder);
    return items;
  }

  Future<List<MedicationReminder>> delete(String id) async {
    final items = [...await load()];
    final removed = items.where((item) => item.id == id).toList();
    items.removeWhere((item) => item.id == id);
    await _persist(items);
    for (final item in removed) {
      await _cancelAll(item);
    }
    return items;
  }

  /// Uygulama açılışında çağrılır: kayıtlı aktif hatırlatıcıların
  /// bildirimlerini yeniden kurar (cihaz yeniden başlamış olabilir).
  Future<void> rescheduleAll() async {
    for (final reminder in await load()) {
      await _reschedule(reminder);
    }
  }

  Future<void> _reschedule(MedicationReminder reminder) async {
    await _cancelAll(reminder);
    if (!reminder.active) return;

    final occurrences = reminder.occurrences();
    final body = (reminder.note == null || reminder.note!.trim().isEmpty)
        ? 'Hatırlatma zamanı geldi.'
        : reminder.note!.trim();

    for (var i = 0; i < occurrences.length && i < _idsPerReminder; i++) {
      await _notifications.scheduleDaily(
        id: _notificationId(reminder.id, i),
        title: reminder.name.trim(),
        body: body,
        hour: occurrences[i].hour,
        minute: occurrences[i].minute,
      );
    }
  }

  Future<void> _cancelAll(MedicationReminder reminder) async {
    for (var i = 0; i < _idsPerReminder; i++) {
      await _notifications.cancel(_notificationId(reminder.id, i));
    }
  }

  /// Kayıt kimliğinden kararlı (deterministik) bildirim kimliği üretir.
  static int _notificationId(String reminderId, int index) {
    final base = reminderId.hashCode.abs() % 80000;
    return base * _idsPerReminder + index;
  }
}
