import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import 'gatt_dive_parser.dart';
import 'shearwater_gatt_parser.dart';
import 'suunto_gatt_parser.dart';

/// Connects to a paired dive computer, parses GATT dive logs, and imports via API.
class BleDiveSyncService {
  BleDiveSyncService({
    List<DiveComputerGattParser>? parsers,
  }) : _parsers = parsers ??
            [
              ShearwaterGattParser(),
              SuuntoGattParser(),
            ];

  final List<DiveComputerGattParser> _parsers;

  DiveComputerGattParser? _resolveParser(
    BluetoothDevice device,
    List<BluetoothService> services,
  ) {
    for (final parser in _parsers) {
      if (parser.matches(device, services)) return parser;
    }
    return null;
  }

  Future<({int imported, int skipped, String? manufacturer})> syncDevice({
    required String deviceUuid,
    required String accessToken,
  }) async {
    final device = BluetoothDevice.fromId(deviceUuid);
    await device.connect(timeout: const Duration(seconds: 15));

    try {
      final services = await device.discoverServices();
      final parser = _resolveParser(device, services);
      if (parser == null) {
        throw StateError('Unsupported dive computer — try UDDF file import');
      }

      final dives = await parser.readDives(device, services);
      if (dives.isEmpty) {
        throw StateError('No dives found on ${parser.manufacturer} device');
      }

      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/dive-computers/import'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'device_uuid': deviceUuid,
          'dives': dives.map((d) => d.toJson()).toList(),
        }),
      );

      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw StateError('Import failed (${res.statusCode})');
      }

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return (
        imported: (body['imported'] as num?)?.toInt() ?? dives.length,
        skipped: (body['skipped'] as num?)?.toInt() ?? 0,
        manufacturer: parser.manufacturer,
      );
    } finally {
      await device.disconnect();
    }
  }
}
