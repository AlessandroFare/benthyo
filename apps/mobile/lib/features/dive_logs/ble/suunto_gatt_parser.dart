import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:intl/intl.dart';

import 'gatt_dive_parser.dart';

/// Suunto D5 / EON / Z-series BLE dive log parser.
class SuuntoGattParser implements DiveComputerGattParser {
  static final suuntoService = Guid('0000fe26-0000-1000-8000-00805f9b34fb');
  static final diveListChar = Guid('0000fe27-0000-1000-8000-00805f9b34fb');
  static final diveDataChar = Guid('0000fe28-0000-1000-8000-00805f9b34fb');

  @override
  String get manufacturer => 'Suunto';

  @override
  bool matches(BluetoothDevice device, List<BluetoothService> services) {
    final name = device.platformName.toLowerCase();
    if (name.contains('suunto') ||
        name.contains('d5') ||
        name.contains('eon') ||
        name.contains('zoop')) {
      return true;
    }
    return services.any((s) => s.uuid == suuntoService);
  }

  @override
  Future<List<ParsedBleDive>> readDives(
    BluetoothDevice device,
    List<BluetoothService> services,
  ) async {
    BluetoothService? suuntoSvc;
    for (final s in services) {
      if (s.uuid == suuntoService) {
        suuntoSvc = s;
        break;
      }
    }
    if (suuntoSvc == null) return [];

    BluetoothCharacteristic? listChar;
    BluetoothCharacteristic? dataChar;
    for (final c in suuntoSvc.characteristics) {
      if (c.uuid == diveListChar) listChar = c;
      if (c.uuid == diveDataChar) dataChar = c;
    }

    if (listChar != null) {
      try {
        final listData = await listChar.read();
        return _parseSuuntoList(Uint8List.fromList(listData));
      } catch (_) {}
    }

    if (dataChar != null) {
      try {
        final data = await dataChar.read();
        return _parseSuuntoPayload(Uint8List.fromList(data));
      } catch (_) {}
    }

    return [];
  }

  List<ParsedBleDive> _parseSuuntoList(Uint8List data) {
    if (data.isEmpty) return [];
    final count = data[0];
    final dives = <ParsedBleDive>[];
    var offset = 1;

    for (var i = 0; i < count && offset + 12 <= data.length; i++) {
      final maxDepthCm = _readUint16(data, offset);
      final durationMin = data[offset + 2];
      final timestamp = _readUint32(data, offset + 3);

      dives.add(ParsedBleDive(
        diveDate: DateFormat('yyyy-MM-dd').format(
          DateTime.fromMillisecondsSinceEpoch(timestamp * 1000, isUtc: true).toLocal(),
        ),
        maxDepthM: maxDepthCm / 100.0,
        durationMin: durationMin.clamp(1, 600),
      ),);
      offset += 12;
    }
    return dives;
  }

  List<ParsedBleDive> _parseSuuntoPayload(Uint8List data) {
    if (data.length < 12) return [];

    final maxDepthCm = _readUint16(data, 0);
    final durationMin = data[2];
    final timestamp = _readUint32(data, 3);

    return [
      ParsedBleDive(
        diveDate: DateFormat('yyyy-MM-dd').format(
          DateTime.fromMillisecondsSinceEpoch(timestamp * 1000, isUtc: true).toLocal(),
        ),
        maxDepthM: maxDepthCm / 100.0,
        durationMin: durationMin.clamp(1, 600),
      ),
    ];
  }

  int _readUint16(Uint8List data, int offset) =>
      data[offset] | (data[offset + 1] << 8);

  int _readUint32(Uint8List data, int offset) =>
      data[offset] |
      (data[offset + 1] << 8) |
      (data[offset + 2] << 16) |
      (data[offset + 3] << 24);
}
