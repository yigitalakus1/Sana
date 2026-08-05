import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sana_app/core/notifications/notification_service.dart';
import 'package:sana_app/features/medication/models/medication_reminder.dart';
import 'package:sana_app/features/medication/services/medication_reminder_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('sıklık hesabı', () {
    test('günlük hatırlatma tek kez tetiklenir', () {
      const reminder = MedicationReminder(
        id: 'r1',
        name: 'Tansiyon ilacı',
        hour: 9,
        minute: 30,
      );

      expect(reminder.occurrences(), [(hour: 9, minute: 30)]);
      expect(reminder.scheduleLabel, 'Her gün 09:30');
    });

    test('8 saatte bir günde 3 kez tetiklenir', () {
      const reminder = MedicationReminder(
        id: 'r2',
        name: 'Antibiyotik',
        hour: 8,
        minute: 0,
        schedule: ReminderSchedule.everyNHours,
        intervalHours: 8,
      );

      expect(reminder.occurrences(), [
        (hour: 8, minute: 0),
        (hour: 16, minute: 0),
        (hour: 0, minute: 0),
      ]);
    });

    test('gece yarısını aşan tekrarlar güne sarar', () {
      const reminder = MedicationReminder(
        id: 'r3',
        name: 'İlaç',
        hour: 22,
        minute: 15,
        schedule: ReminderSchedule.everyNHours,
        intervalHours: 6,
      );

      expect(reminder.occurrences(), [
        (hour: 22, minute: 15),
        (hour: 4, minute: 15),
        (hour: 10, minute: 15),
        (hour: 16, minute: 15),
      ]);
    });

    test('geçersiz aralık güvenli sınıra çekilir', () {
      const reminder = MedicationReminder(
        id: 'r4',
        name: 'İlaç',
        hour: 9,
        minute: 0,
        schedule: ReminderSchedule.everyNHours,
        intervalHours: 0,
      );

      // 0 saat sonsuz döngü olurdu; en az 1 saate çekilir.
      expect(reminder.occurrences(), hasLength(24));
    });
  });

  group('saat gösterimi', () {
    // İlaç saatinde 08:00 ile 20:00'ın karışması gerçek bir risk; uygulama
    // her yerde 24 saatlik gösterim kullanır (sistem 12 saatlik olsa bile).
    Future<String> formatted(WidgetTester tester, TimeOfDay time) async {
      late String result;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('tr'),
          supportedLocales: const [Locale('tr'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: child!,
          ),
          home: Builder(
            builder: (context) {
              result = time.format(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('akşam saati AM/PM ile değil 24 saatlik gösterilir', (
      tester,
    ) async {
      final value = await formatted(tester, const TimeOfDay(hour: 20, minute: 0));

      expect(value, '20:00');
      expect(value.toUpperCase(), isNot(contains('PM')));
    });

    testWidgets('sabah saati sıfır dolgulu gösterilir', (tester) async {
      final value = await formatted(tester, const TimeOfDay(hour: 8, minute: 5));

      expect(value, '08:05');
      expect(value.toUpperCase(), isNot(contains('AM')));
    });
  });

  group('kalıcılık', () {
    test('kaydedilir, yüklenir ve silinir', () async {
      final service = MedicationReminderService(
        notifications: NotificationService.instance,
      );

      const reminder = MedicationReminder(
        id: 'r1',
        name: 'Tansiyon ilacı',
        note: '1 tablet, tok karnına',
        hour: 9,
        minute: 0,
      );
      await service.save(reminder);

      var items = await service.load();
      expect(items, hasLength(1));
      expect(items.single.name, 'Tansiyon ilacı');
      expect(items.single.note, '1 tablet, tok karnına');
      expect(items.single.active, isTrue);

      await service.save(reminder.copyWith(active: false));
      items = await service.load();
      expect(items, hasLength(1), reason: 'güncelleme kopya oluşturmamalı');
      expect(items.single.active, isFalse);

      await service.delete('r1');
      expect(await service.load(), isEmpty);
    });

    test('JSON tur atışında alanlar korunur', () {
      const reminder = MedicationReminder(
        id: 'r9',
        name: 'D vitamini',
        note: 'haftada bir',
        hour: 21,
        minute: 45,
        schedule: ReminderSchedule.everyNHours,
        intervalHours: 12,
        active: false,
      );

      final restored = MedicationReminder.fromJson(reminder.toJson());

      expect(restored.name, 'D vitamini');
      expect(restored.note, 'haftada bir');
      expect(restored.hour, 21);
      expect(restored.minute, 45);
      expect(restored.schedule, ReminderSchedule.everyNHours);
      expect(restored.intervalHours, 12);
      expect(restored.active, isFalse);
    });

    test('bozuk kayıtlar atlanır, geçmiş bozulmaz', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'sana_medication_reminders_v1':
            '[{"id":"","name":"adsiz"},{"id":"ok","name":"Geçerli","hour":8,"minute":0}]',
      });
      final service = MedicationReminderService();

      final items = await service.load();

      expect(items, hasLength(1));
      expect(items.single.name, 'Geçerli');
    });

    test('boş adlı kayıt yüklenmez', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'sana_medication_reminders_v1': '[{"id":"x","name":"   "}]',
      });

      expect(await MedicationReminderService().load(), isEmpty);
    });
  });
}
