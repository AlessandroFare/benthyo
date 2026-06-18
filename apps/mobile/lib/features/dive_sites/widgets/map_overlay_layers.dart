import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../services/marine_currents_service.dart';
import '../map_explore_providers.dart';

class CurrentArrowsLayer extends StatelessWidget {
  const CurrentArrowsLayer({
    super.key,
    required this.samples,
  });

  final List<MarineCurrentSample> samples;

  @override
  Widget build(BuildContext context) {
    if (samples.isEmpty) return const SizedBox.shrink();

    return MarkerLayer(
      markers: samples
          .map(
            (s) => Marker(
              point: s.point,
              width: 36,
              height: 36,
              alignment: Alignment.center,
              child: _CurrentArrow(
                velocityKmh: s.velocityKmh,
                directionDeg: s.directionDeg,
              ),
            ),
          )
          .toList(),
    );
  }
}

class _CurrentArrow extends StatelessWidget {
  const _CurrentArrow({
    required this.velocityKmh,
    required this.directionDeg,
  });

  final double velocityKmh;
  final double directionDeg;

  @override
  Widget build(BuildContext context) {
    final scale = (velocityKmh / 3.0).clamp(0.5, 1.4);
    return Transform.rotate(
      angle: directionToRadians(directionDeg),
      child: Icon(
        Icons.arrow_upward_rounded,
        size: 22 * scale,
        color: Colors.cyanAccent.withValues(alpha: 0.85),
        shadows: const [Shadow(color: Colors.black54, blurRadius: 2)],
      ),
    );
  }
}

class SpeciesHeatmapLayer extends StatelessWidget {
  const SpeciesHeatmapLayer({
    super.key,
    required this.points,
    this.maxCount,
  });

  final List<SpeciesHeatmapPoint> points;
  final int? maxCount;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();

    final peak = maxCount ?? points.map((p) => p.sightingCount).reduce(math.max);

    return CircleLayer(
      circles: points
          .map(
            (p) => CircleMarker(
              point: p.location,
              radius: _radiusMeters(p.sightingCount, peak),
              color: _heatColor(p.sightingCount, peak),
              borderColor: Colors.white.withValues(alpha: 0.35),
              borderStrokeWidth: 1,
              useRadiusInMeter: true,
            ),
          )
          .toList(),
    );
  }

  double _radiusMeters(int count, int peak) {
    final t = count / peak;
    return 800 + t * 4200;
  }

  Color _heatColor(int count, int peak) {
    final t = count / peak;
    return Color.lerp(
      Colors.yellow.withValues(alpha: 0.25),
      Colors.deepOrange.withValues(alpha: 0.55),
      t,
    )!;
  }
}
