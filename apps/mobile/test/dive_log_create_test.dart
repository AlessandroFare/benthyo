import 'package:flutter_test/flutter_test.dart';

import 'package:oceanlog/core/models/enums.dart';
import 'package:oceanlog/features/dive_logs/dive_logs_providers.dart';

void main() {
  group('validateDiveLogInput', () {
    test('accepts valid dive log input', () {
      final result = validateDiveLogInput(
        diveDate: DateTime(2024, 6, 1),
        maxDepthM: 28.5,
        durationMin: 45,
        avgDepthM: 18.0,
        rating: 4,
        tankStartBar: 200,
        tankEndBar: 50,
      );

      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('rejects future dive date', () {
      final future = DateTime.now().add(const Duration(days: 1));
      final result = validateDiveLogInput(
        diveDate: future,
        maxDepthM: 20,
        durationMin: 40,
      );

      expect(result.isValid, isFalse);
      expect(result.errors['dive_date'], isNotNull);
    });

    test('rejects avg depth greater than max depth', () {
      final result = validateDiveLogInput(
        diveDate: DateTime(2024, 1, 1),
        maxDepthM: 20,
        durationMin: 40,
        avgDepthM: 25,
      );

      expect(result.isValid, isFalse);
      expect(result.errors['avg_depth_m'], isNotNull);
    });

    test('rejects invalid tank pressures', () {
      final result = validateDiveLogInput(
        diveDate: DateTime(2024, 1, 1),
        maxDepthM: 20,
        durationMin: 40,
        tankStartBar: 100,
        tankEndBar: 150,
      );

      expect(result.isValid, isFalse);
      expect(result.errors['tank_end_bar'], isNotNull);
    });
  });

  group('DiveLogCreateInput', () {
    test('serializes payload matching DB column names', () {
      final input = DiveLogCreateInput(
        diveDate: DateTime(2024, 3, 15),
        maxDepthM: 32,
        durationMin: 50,
        gasMix: GasMix.nitrox32,
        buddyName: 'Alex',
        rating: 5,
      );

      final payload = input.toPayload('user-123', 'log-456');

      expect(payload['user_id'], 'user-123');
      expect(payload['id'], 'log-456');
      expect(payload['dive_date'], '2024-03-15');
      expect(payload['max_depth_m'], 32);
      expect(payload['duration_min'], 50);
      expect(payload['gas_mix'], 'nitrox32');
      expect(payload['buddy_name'], 'Alex');
      expect(payload['rating'], 5);
      expect(payload['synced_at'], isNotNull);
    });
  });
}
