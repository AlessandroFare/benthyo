import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Parsed dive ready for API import.
class ParsedBleDive {
  const ParsedBleDive({
    required this.diveDate,
    required this.maxDepthM,
    required this.durationMin,
    this.profileSamples = const [],
  });

  final String diveDate;
  final double maxDepthM;
  final int durationMin;
  final List<Map<String, dynamic>> profileSamples;

  Map<String, dynamic> toJson() => {
        'dive_date': diveDate,
        'max_depth_m': maxDepthM,
        'duration_min': durationMin,
        if (profileSamples.isNotEmpty) 'profile_samples': profileSamples,
      };
}

/// Manufacturer-specific BLE GATT dive log parser.
abstract class DiveComputerGattParser {
  String get manufacturer;

  bool matches(BluetoothDevice device, List<BluetoothService> services);

  Future<List<ParsedBleDive>> readDives(
    BluetoothDevice device,
    List<BluetoothService> services,
  );
}
