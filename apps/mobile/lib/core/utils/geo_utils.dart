import 'dart:typed_data';
import 'package:latlong2/latlong.dart';

/// Parses PostGIS geography from Supabase responses.
/// Supports:
/// - GeoJSON Point objects: {"type":"Point","coordinates":[lng,lat]}
/// - WKT strings: "POINT(lng lat)"
/// - WKB hex strings (PostGIS EWKB): "0101000020E6100000..."
LatLng? parseGeography(dynamic raw) {
  if (raw == null) return null;

  // GeoJSON object
  if (raw is Map<String, dynamic>) {
    final coords = raw['coordinates'];
    if (coords is List && coords.length >= 2) {
      final lng = (coords[0] as num).toDouble();
      final lat = (coords[1] as num).toDouble();
      return LatLng(lat, lng);
    }
  }

  if (raw is String) {
    final trimmed = raw.trim();

    // WKT: POINT(lng lat)
    final wktMatch = RegExp(
      r'POINT\s*\(\s*([-\d.]+)\s+([-\d.]+)\s*\)',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (wktMatch != null) {
      final lng = double.parse(wktMatch.group(1)!);
      final lat = double.parse(wktMatch.group(2)!);
      return LatLng(lat, lng);
    }

    // WKB hex (PostGIS EWKB little-endian)
    // Structure: [byteOrder(1)] [wkbType(4)] [srid(4, optional)] [lng(8)] [lat(8)]
    if (RegExp(r'^[0-9a-fA-F]+$').hasMatch(trimmed) && trimmed.length >= 42) {
      try {
        final bytes = Uint8List.fromList([
          for (var i = 0; i < trimmed.length - 1; i += 2)
            int.parse(trimmed.substring(i, i + 2), radix: 16),
        ]);
        final bd = ByteData.sublistView(bytes);
        if (bytes[0] == 0x01) {
          // little-endian; check if SRID flag set (bit 0x20 in type byte)
          final wkbType = bd.getUint32(1, Endian.little);
          final hasSrid = (wkbType & 0x20000000) != 0;
          final offset = hasSrid ? 9 : 5;
          if (bytes.length >= offset + 16) {
            final lng = bd.getFloat64(offset, Endian.little);
            final lat = bd.getFloat64(offset + 8, Endian.little);
            if (lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180) {
              return LatLng(lat, lng);
            }
          }
        }
      } catch (_) {
        // fall through
      }
    }
  }

  return null;
}

String geographyToWkt(LatLng point) =>
    'POINT(${point.longitude} ${point.latitude})';