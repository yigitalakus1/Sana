import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sana_app/features/ml_dictionary/models/report_parse_models.dart';
import 'package:sana_app/features/ml_dictionary/services/report_history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test(
    'report history saves, loads, deletes and clears local reports',
    () async {
      final service = ReportHistoryService();
      const result = ParsedLabResult(
        labTest: 'CRP',
        rawValue: '13.5',
        value: 13.5,
        unit: 'mg/L',
      );

      final first = await service.save(
        sourceName: 'ilk.pdf',
        results: const [result],
      );
      await service.save(sourceName: 'ikinci.pdf', results: const [result]);

      var entries = await service.load();
      expect(entries, hasLength(2));
      expect(entries.first.sourceName, 'ikinci.pdf');
      expect(entries.last.results.single.labTest, 'CRP');

      await service.delete(first.id);
      entries = await service.load();
      expect(entries, hasLength(1));

      await service.clear();
      expect(await service.load(), isEmpty);
    },
  );
}
