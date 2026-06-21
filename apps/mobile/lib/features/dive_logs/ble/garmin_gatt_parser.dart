import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:intl/intl.dart';

import 'gatt_dive_parser.dart';

/// Garmin Descent series BLE dive log parser.
///
/// Garmin dive computers (Descent Mk1/Mk2/Mk2i/Mk3, Descent G1) expose
/// dive logs via the Garmin Proprietary Service with a dedicated dive
/// log characteristic. The binary format follows Garmin's FIT-protocol
/// encapsulation for dive summaries.
class GarminGattParser implements DiveComputerGattParser {
  static final garminService = Guid('0000fe00-0000-1000-8000-00805f9b34fb');
  static final diveLogChar = Guid('0000fe01-0000-1000-8000-00805f9b34fb');
  static final diveRequestChar = Guid('0000fe02-0000-1000-8000-00805f9b34fb');

  static final garminDiveService = Guid('0000fe29-0000-1000-8000-00805f9b34fb');
  static final diveSummaryChar = Guid('0000fe2a-0000-1000-8000-00805f9b34fb');

  @override
  String get manufacturer => 'Garmin';

  @override
  bool matches(BluetoothDevice device, List<BluetoothService> services) {
    final name = device.platformName.toLowerCase();
    if (name.contains('garmin') ||
        name.contains('descent') ||
        name.contains('mk1') ||
        name.contains('mk2') ||
        name.contains('mk3') ||
        name.contains('g1')) {
      return true;
    }
    return services.any((s) => s.uuid == garminService || s.uuid == garminDiveService);
  }

  @override
  Future<List<ParsedBleDive>> readDives(
    BluetoothDevice device,
    List<BluetoothService> services,
  ) async {
    for (final service in services) {
      if (service.uuid == garminService) {
        final dives = await _readGarminLegacy(service);
        if (dives.isNotEmpty) return dives;
      }
      if (service.uuid == garminDiveService) {
        final dives = await _readGarminDiveService(service);
        if (dives.isNotEmpty) return dives;
      }
    }
    return [];
  }

  Future<List<ParsedBleDive>> _readGarminLegacy(BluetoothService service) async {
    BluetoothCharacteristic? logChar;
    BluetoothCharacteristic? reqChar;
    for (final c in service.characteristics) {
      if (c.uuid == diveLogChar) logChar = c;
      if (c.uuid == diveRequestChar) reqChar = c;
    }
    if (logChar == null) return [];

    try {
      if (reqChar != null) {
        final request = Uint8List.fromList([0x01]);
        await reqChar.write(request, withoutResponse: false);
      }

      final data = await logChar.read();
      return _parseGarminPayload(Uint8List.fromList(data));
    } catch (_) {
      return [];
    }
  }

  Future<List<ParsedBleDive>> _readGarminDiveService(BluetoothService service) async {
    BluetoothCharacteristic? summaryChar;
    for (final c in service.characteristics) {
      if (c.uuid == diveSummaryChar) {
        summaryChar = c;
        break;
      }
    }
    if (summaryChar == null) return [];

    try {
      final data = await summaryChar.read();
      return _parseGarminPayload(Uint8List.fromList(data));
    } catch (_) {
      return [];
    }
  }

  List<ParsedBleDive> _parseGarminPayload(Uint8List data) {
    if (data.length < 16) return [];

    final dives = <ParsedBleDive>[];
    var offset = 0;

    while (offset + 16 <= data.length) {
      final recordType = data[offset];
      if (recordType != 0x04 && recordType != 0x0A) {
        offset += 1;
        continue;
      }

      final year = _readUint16(data, offset + 2);
      final month = data[offset + 4];
      final day = data[offset + 5];

      if (year < 2000 || year > 2100 || month < 1 || month > 12 || day < 1 || day > 31) {
        offset += 16;
        continue;
      }

      final maxDepthCm = _readUint16(data, offset + 6);
      final durationSec = _readUint16(data, offset + 8);

      final maxDepthM = maxDepthCm / 100.0;
      final durationMin = (durationSec / 60).round().clamp(1, 600);

      final diveDate = DateFormat('yyyy-MM-dd').format(
        DateTime(year, month, day),
      );

      final profileSamples = <Map<String, dynamic>>[];
      if (offset + 32 <= data.length) {
        for (var i = 0; i < 8; i++) {
          final sampleOffset = offset + 16 + (i * 2);
          if (sampleOffset + 2 > data.length) break;
          final depthCm = _readUint16(data, sampleOffset);
          if (depthCm == 0 && i > 2) break;
          profileSamples.add({
            't_sec': i * 60,
            'depth_m': depthCm / 100.0,
          });
        }
      }

      dives.add(ParsedBleDive(
        diveDate: diveDate,
        maxDepthM: maxDepthM,
        durationMin: durationMin,
        profileSamples: profileSamples,
      ));

      offset += 16;
    }

    return dives;
  }

  int _readUint16(Uint8List data, int offset) =>
      data[offset] | (data[offset + 1] << 8);
}
