import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Live ocean surface current sample (Open-Meteo Marine / Copernicus SMOC).
class MarineCurrentSample {
  const MarineCurrentSample({
    required this.point,
    required this.velocityKmh,
    required this.directionDeg,
  });

  final LatLng point;
  final double velocityKmh;
  final double directionDeg;

  bool get isSignificant => velocityKmh >= 0.3;
}

class MarineBounds {
  const MarineBounds({
    required this.south,
    required this.north,
    required this.west,
    required this.east,
  });

  final double south;
  final double north;
  final double west;
  final double east;

  @override
  bool operator ==(Object other) =>
      other is MarineBounds &&
      other.south == south &&
      other.north == north &&
      other.west == west &&
      other.east == east;

  @override
  int get hashCode => Object.hash(south, north, west, east);
}

class MarineCurrentsService {
  MarineCurrentsService({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;
  static const _base = 'https://marine-api.open-meteo.com/v1/marine';

  /// Fetch a coarse grid of current vectors inside [bounds] (max 36 points).
  Future<List<MarineCurrentSample>> fetchGrid(MarineBounds bounds) async {
    final points = _gridPoints(bounds, gridSize: 6);
    if (points.isEmpty) return const [];

    final lats = points.map((p) => p.latitude.toStringAsFixed(2)).join(',');
    final lngs = points.map((p) => p.longitude.toStringAsFixed(2)).join(',');

    final uri = Uri.parse(_base).replace(
      queryParameters: {
        'latitude': lats,
        'longitude': lngs,
        'current': 'ocean_current_velocity,ocean_current_direction',
        'cell_selection': 'sea',
      },
    );

    final res = await _http.get(uri);
    if (res.statusCode >= 400) {
      throw Exception('Marine API ${res.statusCode}');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is List) {
      return decoded
          .whereType<Map<String, dynamic>>()
          .expand((block) => _parseSingle(block))
          .where((s) => s.isSignificant)
          .toList();
    }

    final body = decoded as Map<String, dynamic>;
    return _parseSingle(body).where((s) => s.isSignificant).toList();
  }

  List<MarineCurrentSample> _parseSingle(Map<String, dynamic> body) {
    if (body.containsKey('current')) {
      final current = body['current'] as Map<String, dynamic>;
      final velocity = (current['ocean_current_velocity'] as num?)?.toDouble();
      final direction = (current['ocean_current_direction'] as num?)?.toDouble();
      final lat = (body['latitude'] as num?)?.toDouble();
      final lng = (body['longitude'] as num?)?.toDouble();
      if (velocity != null && direction != null && lat != null && lng != null) {
        return [
          MarineCurrentSample(
            point: LatLng(lat, lng),
            velocityKmh: velocity,
            directionDeg: direction,
          ),
        ];
      }
    }
    return const [];
  }

  Future<MarineCurrentSample?> fetchPoint(LatLng point) async {
    final uri = Uri.parse(_base).replace(
      queryParameters: {
        'latitude': point.latitude.toStringAsFixed(4),
        'longitude': point.longitude.toStringAsFixed(4),
        'current': 'ocean_current_velocity,ocean_current_direction',
        'cell_selection': 'sea',
      },
    );
    final res = await _http.get(uri);
    if (res.statusCode >= 400) return null;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final current = body['current'] as Map<String, dynamic>?;
    if (current == null) return null;
    final velocity = (current['ocean_current_velocity'] as num?)?.toDouble();
    final direction = (current['ocean_current_direction'] as num?)?.toDouble();
    if (velocity == null || direction == null) return null;
    return MarineCurrentSample(
      point: point,
      velocityKmh: velocity,
      directionDeg: direction,
    );
  }

  List<LatLng> _gridPoints(MarineBounds bounds, {required int gridSize}) {
    final latStep = (bounds.north - bounds.south) / (gridSize - 1);
    final lngStep = (bounds.east - bounds.west) / (gridSize - 1);
    if (latStep.abs() < 0.01 || lngStep.abs() < 0.01) {
      return [LatLng((bounds.north + bounds.south) / 2, (bounds.east + bounds.west) / 2)];
    }

    final points = <LatLng>[];
    for (var i = 0; i < gridSize; i++) {
      for (var j = 0; j < gridSize; j++) {
        points.add(LatLng(bounds.south + latStep * i, bounds.west + lngStep * j));
      }
    }
    return points;
  }

  void dispose() => _http.close();
}

/// Drift-planning hint from bathymetry profile + currents.
class DriftPlanHint {
  const DriftPlanHint({
    required this.label,
    required this.detail,
    required this.level,
  });

  final String label;
  final String detail;
  final DriftRiskLevel level;

  static DriftPlanHint compute({
    required double depthMin,
    required double depthMax,
    required String siteType,
    MarineCurrentSample? liveCurrent,
    double? loggedVisibilityM,
  }) {
    final drop = depthMax - depthMin;
    final steep = drop >= 15 || depthMax >= 30;
    final wallLike = siteType == 'wall' || siteType == 'pinnacle';
    final liveKmh = liveCurrent?.velocityKmh ?? 0;
    final strongLive = liveKmh >= 1.5;
    final moderateLive = liveKmh >= 0.6;

    if ((steep || wallLike) && strongLive) {
      return DriftPlanHint(
        label: 'Drift dive likely',
        detail:
            'Steep profile (${depthMin.round()}–${depthMax.round()}m) with live current ~${liveKmh.toStringAsFixed(1)} km/h. Plan boat cover.',
        level: DriftRiskLevel.high,
      );
    }
    if (wallLike && moderateLive) {
      return DriftPlanHint(
        label: 'Along-wall drift',
        detail:
            'Moderate live current (${liveKmh.toStringAsFixed(1)} km/h). Use slope as reference; note exit point.',
        level: DriftRiskLevel.moderate,
      );
    }
    if (steep && drop > 25) {
      return DriftPlanHint(
        label: 'Vertical profile',
        detail:
            'Large depth range — check isolines for slope; ${loggedVisibilityM != null ? 'typical vis ${loggedVisibilityM.round()}m' : 'log visibility after dive'}.',
        level: DriftRiskLevel.moderate,
      );
    }
    if (liveKmh > 0 && liveKmh < 0.6) {
      return DriftPlanHint(
        label: 'Mostly sheltered',
        detail: 'Light live current (${liveKmh.toStringAsFixed(1)} km/h). Good for training or photography.',
        level: DriftRiskLevel.low,
      );
    }
    return DriftPlanHint(
      label: 'Standard profile',
      detail: 'Use isolines overlay to inspect bottom shape before planning entry/exit.',
      level: DriftRiskLevel.low,
    );
  }
}

enum DriftRiskLevel { low, moderate, high }

double directionToRadians(double directionDeg) =>
    (directionDeg - 90) * math.pi / 180;
