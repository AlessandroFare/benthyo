import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import '../lib/features/dive_logs/ble/garmin_gatt_parser.dart';

void main() {
  late GarminGattParser parser;

  setUp(() {
    parser = GarminGattParser();
  });

  group('GarminGattParser', () {
    test('returns Garmin manufacturer name', () {
      expect(parser.manufacturer, equals('Garmin'));
    });

    group('parseGarminPayload', () {
      test('returns empty list for data < 16 bytes', () {
        final result = parser.parseGarminPayload(Uint8List(10));
        expect(result, isEmpty);
      });

      test('returns empty list for empty data', () {
        final result = parser.parseGarminPayload(Uint8List(0));
        expect(result, isEmpty);
      });

  // Little-endian: data[offset] = low byte, data[offset+1] = high byte
  // _readUint16: data[offset] | (data[offset + 1] << 8)

      test('parses valid dive record with correct year/month/day', () {
        final data = Uint8List(16);
        data[0] = 0x04;                     // recordType = 0x04
        data[2] = 0xEA; data[3] = 0x07;     // 0x07EA = 2026
        data[4] = 6;                        // month
        data[5] = 15;                       // day
        data[6] = 0xB8; data[7] = 0x0B;     // 0x0BB8 = 3000 cm = 30m
        data[8] = 0x60; data[9] = 0x09;     // 0x0960 = 2400 sec = 40min

        final result = parser.parseGarminPayload(data);
        expect(result, hasLength(1));
        expect(result[0].diveDate, equals('2026-06-15'));
        expect(result[0].maxDepthM, closeTo(30.0, 0.1));
        expect(result[0].durationMin, equals(40));
      });

      test('parses multiple dive records', () {
        final data = Uint8List(32);
        // Record 1: 2026-06-15, 30m, 40min
        data[0] = 0x04;  data[2] = 0xEA; data[3] = 0x07;
        data[4] = 6;  data[5] = 15;
        data[6] = 0xB8; data[7] = 0x0B;  data[8] = 0x60; data[9] = 0x09;
        // Record 2: 2026-06-16, 10m, 20min
        data[16] = 0x04; data[18] = 0xEA; data[19] = 0x07;
        data[20] = 6; data[21] = 16;
        data[22] = 0xE8; data[23] = 0x03;  // 0x03E8 = 1000 cm = 10m
        data[24] = 0xB0; data[25] = 0x04;  // 0x04B0 = 1200 sec = 20min

        final result = parser.parseGarminPayload(data);
        expect(result, hasLength(2));
        expect(result[0].diveDate, equals('2026-06-15'));
        expect(result[1].diveDate, equals('2026-06-16'));
      });

      test('skips non-dive record types (0xFF)', () {
        final data = Uint8List(16);
        data[0] = 0xFF;  // unknown record type
        data[2] = 0xEA; data[3] = 0x07;  // 2026
        data[4] = 6; data[5] = 15;

        final result = parser.parseGarminPayload(data);
        expect(result, isEmpty);
      });

      test('extracts profile samples from extended data', () {
        final data = Uint8List(40);
        data[0] = 0x04;  data[2] = 0xEA; data[3] = 0x07;
        data[4] = 6;  data[5] = 15;
        data[6] = 0xB8; data[7] = 0x0B;  // 30m
        data[8] = 0x60; data[9] = 0x09;  // 40min
        // Profile sample at offset 16: 500 cm = 5m
        data[16] = 0xF4; data[17] = 0x01;  // 0x01F4 = 500

        final result = parser.parseGarminPayload(data);
        expect(result, hasLength(1));
        expect(result[0].profileSamples, isNotEmpty);
        expect(result[0].profileSamples[0]['depth_m'], closeTo(5.0, 0.1));
        expect(result[0].profileSamples[0]['t_sec'], equals(0));
      });

      test('handles 0x0A record type as valid dive', () {
        final data = Uint8List(16);
        data[0] = 0x0A;
        data[2] = 0xEA; data[3] = 0x07;  // 2026
        data[4] = 6;  data[5] = 15;
        data[6] = 0xB8; data[7] = 0x0B;  // 30m
        data[8] = 0x60; data[9] = 0x09;  // 40min

        final result = parser.parseGarminPayload(data);
        expect(result, hasLength(1));
      });
    });
  });
}
