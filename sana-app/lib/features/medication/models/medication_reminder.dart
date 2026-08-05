/// Hatırlatma sıklığı.
///
/// [daily] her gün tek bir saatte; [everyNHours] gün içinde belirli saat
/// aralıklarıyla tekrar eder (ör. 8 saatte bir → günde 3 kez).
enum ReminderSchedule { daily, everyNHours }

/// Kullanıcının kendi kurduğu ilaç hatırlatıcısı.
///
/// **Önemli:** Uygulama ilaç, doz veya kullanım sıklığı ÖNERMEZ. Buradaki
/// bilgilerin tamamını kullanıcı kendisi girer; hatırlatıcı yalnız girilen
/// zamanı hatırlatır. Doz kararı hekime aittir.
class MedicationReminder {
  const MedicationReminder({
    required this.id,
    required this.name,
    required this.hour,
    required this.minute,
    this.note,
    this.schedule = ReminderSchedule.daily,
    this.intervalHours = 8,
    this.active = true,
  });

  final String id;

  /// Kullanıcının yazdığı ilaç/hatırlatma adı.
  final String name;

  /// Kullanıcının kendi notu (ör. "1 tablet, tok karnına"). Serbest metin.
  final String? note;

  final ReminderSchedule schedule;

  /// Günlük hatırlatmada saat; aralıklı hatırlatmada ilk tetikleme saati.
  final int hour;
  final int minute;

  /// [ReminderSchedule.everyNHours] için tekrar aralığı (saat).
  final int intervalHours;

  final bool active;

  /// Gün içinde tetiklenecek tüm saatler (saat, dakika).
  ///
  /// Günlükte tek eleman döner. Aralıklıda başlangıç saatinden itibaren
  /// 24 saate sığan tüm tekrarlar üretilir; böylece tek bir "N saatte bir"
  /// kuralı, günlük tekrar eden bildirimlere çevrilebilir.
  List<({int hour, int minute})> occurrences() {
    if (schedule == ReminderSchedule.daily) {
      return [(hour: hour, minute: minute)];
    }
    final step = intervalHours.clamp(1, 24);
    final result = <({int hour, int minute})>[];
    for (var offset = 0; offset < 24; offset += step) {
      result.add((hour: (hour + offset) % 24, minute: minute));
    }
    return result;
  }

  String get scheduleLabel {
    final time = '${hour.toString().padLeft(2, '0')}'
        ':${minute.toString().padLeft(2, '0')}';
    if (schedule == ReminderSchedule.daily) return 'Her gün $time';
    final perDay = occurrences().length;
    return '$intervalHours saatte bir · $time\'dan itibaren · günde $perDay kez';
  }

  MedicationReminder copyWith({
    String? name,
    String? note,
    ReminderSchedule? schedule,
    int? hour,
    int? minute,
    int? intervalHours,
    bool? active,
    bool clearNote = false,
  }) => MedicationReminder(
    id: id,
    name: name ?? this.name,
    note: clearNote ? null : (note ?? this.note),
    schedule: schedule ?? this.schedule,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
    intervalHours: intervalHours ?? this.intervalHours,
    active: active ?? this.active,
  );

  factory MedicationReminder.fromJson(Map<String, dynamic> json) {
    final rawNote = json['note']?.toString();
    return MedicationReminder(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      note: (rawNote == null || rawNote.trim().isEmpty) ? null : rawNote.trim(),
      schedule: json['schedule'] == 'every_n_hours'
          ? ReminderSchedule.everyNHours
          : ReminderSchedule.daily,
      hour: (json['hour'] as num?)?.toInt() ?? 9,
      minute: (json['minute'] as num?)?.toInt() ?? 0,
      intervalHours: (json['interval_hours'] as num?)?.toInt() ?? 8,
      active: json['active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    if (note != null && note!.trim().isNotEmpty) 'note': note!.trim(),
    'schedule': schedule == ReminderSchedule.everyNHours
        ? 'every_n_hours'
        : 'daily',
    'hour': hour,
    'minute': minute,
    'interval_hours': intervalHours,
    'active': active,
  };
}
