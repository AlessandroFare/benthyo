import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:intl/intl.dart';

import 'gatt_dive_parser.dart';

/// Shearwater Petrel/Teríc/Predator BLE dive log parser.
///
/// Uses the Nordic UART service for dive log transfer and parses the
/// manufacturer binary dive record format (OCi family).
class ShearwaterGattParser implements DiveComputerGattParser {
  static final nordicUartService = Guid('6E400001-B5A3-F393-E0A9-E50E24DCCA9E');
  static final rxCharacteristic = Guid('6E400002-B5A3-F393-E0A9-E50E24DCCA9E');
  static final txCharacteristic = Guid('6E400003-B5A3-F393-E0A9-E50E24DCCA9E');

  static final diveLogService = Guid('0000fe58-0000-1000-8000-00805f9b34fb');
  static final diveLogCharacteristic = Guid('0000fe59-0000-1000-8000-00805f9b34fb');

  @override
  String get manufacturer => 'Shearwater';

  @override
  bool matches(BluetoothDevice device, List<BluetoothService> services) {
    final name = device.platformName.toLowerCase();
    if (name.contains('shearwater') ||
        name.contains('petrel') ||
        name.contains('predator') ||
        name.contains('perdix') ||
        name.contains('teric')) {
      return true;
    }
    return services.any(
      (s) =>
          s.uuid == nordicUartService ||
          s.uuid == diveLogService,
    );
  }

  @override
  Future<List<ParsedBleDive>> readDives(
    BluetoothDevice device,
    List<BluetoothService> services,
  ) async {
    for (final service in services) {
      if (service.uuid == diveLogService) {
        final dives = await _readDiveLogCharacteristic(service);
        if (dives.isNotEmpty) return dives;
      }
      if (service.uuid == nordicUartService) {
        final dives = await _readNordicUart(service);
        if (dives.isNotEmpty) return dives;
      }
    }
    return [];
  }

  Future<List<ParsedBleDive>> _readDiveLogCharacteristic(
    BluetoothService service,
  ) async {
    for (final char in service.characteristics) {
      if (char.uuid != diveLogCharacteristic && !char.properties.read) continue;
      try {
        final data = await char.read();
        return _parseShearwaterPayload(Uint8List.fromList(data));
      } catch (_) {
        continue;
      }
    }
    return [];
  }

  Future<List<ParsedBleDive>> _readNordicUart(BluetoothService service) async {
    BluetoothCharacteristic? tx;
    BluetoothCharacteristic? rx;
    for (final char in service.characteristics) {
      if (char.uuid == txCharacteristic) tx = char;
      if (char.uuid == rxCharacteristic) rx = char;
    }
    if (tx == null || rx == null) return [];

    try {
      await tx.setNotifyValue(true);
      final request = Uint8List.fromList([0x01, 0x00]); // request dive list
      await rx.write(request, withoutResponse: false);

      final response = await tx.onValueReceived.first.timeout(
        const Duration(seconds: 10),
      );
      await tx.setNotifyValue(false);
      return _parseShearwaterPayload(Uint8List.fromList(response));
    } catch (_) {
      return [];
    }
  }

  List<ParsedBleDive> _parseShearwaterPayload(Uint8List data) {
    if (data.length < 8) return [];

    final dives = <ParsedBleDive>[];
    var offset = 0;

    while (offset + 16 <= data.length) {
      final maxDepthDm = _readUint16(data, offset);
      final durationSec = _readUint32(data, offset + 2);
      final unixTime = _readUint32(data, offset + 6);

      if (maxDepthDm == 0 && durationSec == 0) break;

      final maxDepthM = maxDepthDm / 10.0;
      final durationMin = (durationSec / 60).round().clamp(1, 600);
      final diveDate = DateFormat('yyyy-MM-dd').format(
        DateTime.fromMillisecondsSinceEpoch(unixTime * 1000, isUtc: true).toLocal(),
      );

      dives.add(ParsedBleDive(
        diveDate: diveDate,
        maxDepthM: maxDepthM,
        durationMin: durationMin,
      ));

      offset += 16;
    }

    return dives;
  }

  int _readUint16(Uint8List data, int offset) =>
      data[offset] | (data[offset + 1] << 8);

  int _readUint32(Uint8List data, int offset) =>
      data[offset] |
      (data[offset + 1] << 8) |
      (data[offset + 2] << 16) |
      (data[offset + 3] << 24);
}
