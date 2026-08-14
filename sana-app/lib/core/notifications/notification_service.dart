import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// İzin isteme sonucu.
enum NotificationPermission {
  /// Bildirim gösterilebilir.
  granted,

  /// Kullanıcı reddetti; hatırlatıcı kaydedilir ama bildirim gitmez.
  denied,

  /// Bu platformda zamanlanmış bildirim desteklenmiyor (ör. web).
  unsupported,
}

/// Yerel (cihaz üstü) bildirimleri yönetir.
///
/// Sunucuya hiçbir şey gitmez; zamanlama tamamen cihazda yapılır.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _canScheduleExact = false;

  /// Zamanlanmış bildirim yalnız mobilde güvenilir biçimde çalışır.
  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Tam zamanlı alarm kurulabiliyor mu.
  ///
  /// `false` ise hatırlatıcı yine çalışır ama Android güç tasarrufu nedeniyle
  /// saati kaydırabilir. İlaç saati için bu, kullanıcıya söylenmesi gereken
  /// bir bilgidir; sessizce geç bildirim göndermek yanılticıdır.
  bool get canScheduleExact => _canScheduleExact;

  static const AndroidNotificationDetails _androidDetails =
      AndroidNotificationDetails(
        'sana_medication',
        'İlaç hatırlatıcıları',
        channelDescription:
            'Kullanıcının kendi kurduğu ilaç ve ölçüm hatırlatmaları',
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
      );

  static const NotificationDetails _details = NotificationDetails(
    android: _androidDetails,
    iOS: DarwinNotificationDetails(),
  );

  Future<void> init() async {
    if (!supported || _ready) return;
    try {
      tzdata.initializeTimeZones();
      // Cihazın saat dilimi ayarlanmazsa zamanlama UTC'ye göre yapılır ve
      // hatırlatıcı yanlış saatte çalar.
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name.identifier));

      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(
        settings: const InitializationSettings(android: android, iOS: darwin),
      );
      _ready = true;
    } catch (_) {
      // Bildirim kurulamazsa uygulama çalışmaya devam eder; hatırlatıcılar
      // yine kaydedilir, yalnız bildirim gönderilemez.
      _ready = false;
    }
  }

  /// Bildirim iznini ister. Android 13+ ve iOS'ta kullanıcıya sorulur.
  Future<NotificationPermission> requestPermission() async {
    if (!supported) return NotificationPermission.unsupported;
    await init();
    if (!_ready) return NotificationPermission.denied;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        final granted = await android?.requestNotificationsPermission() ?? true;
        // Tam zamanlı alarm izni isteğe bağlıdır: reddedilirse bildirim yine
        // gider, yalnız birkaç dakika gecikebilir.
        if (granted) {
          try {
            await android?.requestExactAlarmsPermission();
          } catch (_) {}
          _canScheduleExact =
              await android?.canScheduleExactNotifications() ?? false;
        }
        return granted
            ? NotificationPermission.granted
            : NotificationPermission.denied;
      }
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      final granted =
          await ios?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          true;
      return granted
          ? NotificationPermission.granted
          : NotificationPermission.denied;
    } catch (_) {
      return NotificationPermission.denied;
    }
  }

  /// Her gün aynı saatte tekrar eden bir bildirim kurar.
  Future<bool> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
  }) async {
    if (!supported) return false;
    await init();
    if (!_ready) return false;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        _canScheduleExact =
            await android?.canScheduleExactNotifications() ?? false;
      }
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: _nextInstanceOf(hour, minute),
        notificationDetails: _details,
        // İlaç saatinde gecikme istenmez; izin yoksa sistem kendiliğinden
        // yaklaşık zamanlamaya düşer.
        androidScheduleMode: _canScheduleExact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> cancel(int id) async {
    if (!supported) return;
    try {
      await _plugin.cancel(id: id);
    } catch (_) {}
  }

  /// Verilen saat/dakikanın bir sonraki gerçekleşme anı (bugün geçtiyse yarın).
  tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
