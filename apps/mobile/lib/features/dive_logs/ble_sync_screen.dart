import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/config/api_config.dart';
import '../../core/supabase/supabase_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scaffold.dart';
import 'ble/ble_dive_sync_service.dart';

final bleDevicesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final token =
      ref.watch(supabaseClientProvider).auth.currentSession?.accessToken;
  if (token == null) return [];

  final res = await http.get(
    Uri.parse('${ApiConfig.baseUrl}/dive-computers'),
    headers: {'Authorization': 'Bearer $token'},
  );
  if (res.statusCode != 200) {
    throw Exception('Failed to load dive computers (${res.statusCode})');
  }
  final body = jsonDecode(res.body);
  return body is List
      ? body.cast<Map<String, dynamic>>()
      : (body['data'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
});

class BleSyncScreen extends ConsumerStatefulWidget {
  const BleSyncScreen({super.key});

  @override
  ConsumerState<BleSyncScreen> createState() => _BleSyncScreenState();
}

class _BleSyncScreenState extends ConsumerState<BleSyncScreen> {
  bool _scanning = false;
  List<ScanResult> _scanResults = [];
  String? _status;

  Future<void> _scan() async {
    if (kIsWeb) {
      setState(() => _status = 'BLE scan is not available on web');
      return;
    }

    setState(() {
      _scanning = true;
      _status = 'Scanning for dive computers…';
      _scanResults = [];
    });

    try {
      if (await FlutterBluePlus.isSupported == false) {
        setState(() => _status = 'BLE not supported on this device');
        return;
      }

      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
      await Future<void>.delayed(const Duration(seconds: 8));
      await FlutterBluePlus.stopScan();

      final results = FlutterBluePlus.lastScanResults;
      setState(() {
        _scanResults = results;
        _status = '${results.length} device(s) found';
      });
    } catch (e) {
      setState(() => _status = 'Scan failed: $e');
    } finally {
      setState(() => _scanning = false);
    }
  }

  Future<void> _registerDevice(ScanResult result) async {
    final token =
        ref.read(supabaseClientProvider).auth.currentSession?.accessToken;
    if (token == null) return;

    final device = result.device;
    await http.post(
      Uri.parse('${ApiConfig.baseUrl}/dive-computers/register'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'device_name': device.platformName.isNotEmpty
            ? device.platformName
            : device.remoteId.str,
        'device_uuid': device.remoteId.str,
        'manufacturer': result.advertisementData.manufacturerData.isNotEmpty
            ? result.advertisementData.manufacturerData.keys.first.toString()
            : null,
      }),
    );
    ref.invalidate(bleDevicesProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Device registered')),
      );
    }
  }

  Future<void> _syncDevice(String deviceUuid) async {
    final token =
        ref.read(supabaseClientProvider).auth.currentSession?.accessToken;
    if (token == null) return;

    setState(() => _status = 'Connecting to dive computer…');

    try {
      final result = await BleDiveSyncService().syncDevice(
        deviceUuid: deviceUuid,
        accessToken: token,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Imported ${result.imported} dive(s) from ${result.manufacturer ?? 'device'}'
              '${result.skipped > 0 ? ' (${result.skipped} skipped)' : ''}',
            ),
          ),
        );
        setState(() => _status = 'Sync complete');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Sync failed: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e')),
        );
      }
    }
    ref.invalidate(bleDevicesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final devicesAsync = ref.watch(bleDevicesProvider);

    return AppScaffold(
      title: 'BLE dive computer',
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text(
            'Pair Suunto or Shearwater dive computers via BLE. Supported parsers '
            'read manufacturer GATT dive log characteristics automatically.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: _scanning ? null : _scan,
            icon: _scanning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.bluetooth_searching),
            label: const Text('Scan for devices'),
          ),
          if (_status != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(_status!, style: Theme.of(context).textTheme.bodySmall),
          ],
          if (_scanResults.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Text('Nearby devices', style: Theme.of(context).textTheme.titleSmall),
            ..._scanResults.map(
              (r) => ListTile(
                leading: const Icon(Icons.watch),
                title: Text(
                  r.device.platformName.isNotEmpty
                      ? r.device.platformName
                      : r.device.remoteId.str,
                ),
                subtitle: Text(r.device.remoteId.str),
                trailing: TextButton(
                  onPressed: () => _registerDevice(r),
                  child: const Text('Pair'),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Text('Paired devices', style: Theme.of(context).textTheme.titleSmall),
          devicesAsync.when(
            data: (devices) {
              if (devices.isEmpty) {
                return const Text('No paired devices yet');
              }
              return Column(
                children: devices
                    .map(
                      (d) => ListTile(
                        leading: const Icon(Icons.scuba_diving),
                        title: Text(d['device_name'] as String? ?? 'Device'),
                        subtitle: Text(
                          d['last_sync_at'] != null
                              ? 'Last sync ${d['last_sync_at']}'
                              : 'Never synced',
                        ),
                        trailing: FilledButton(
                          onPressed: () =>
                              _syncDevice(d['device_uuid'] as String),
                          child: const Text('Sync'),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => const Text('Could not load devices'),
          ),
        ],
      ),
    );
  }
}
