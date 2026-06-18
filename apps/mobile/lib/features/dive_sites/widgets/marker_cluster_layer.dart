import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Animated marker cluster that groups nearby dive sites into a single
/// visual unit. The cluster grows and pulses when the count increases,
/// and individual markers bounce slightly on tap.
///
/// Algorithm: greedy O(N) — start with no group; for each marker, if
/// it falls within [clusterRadiusMeters] of an existing group's
/// centroid, add it to that group; otherwise start a new group. The
/// centroid is recomputed on each addition.
class MarkerClusterLayer extends StatelessWidget {
  const MarkerClusterLayer({
    super.key,
    required this.markers,
    required this.onClusterTap,
    required this.onMarkerTap,
    this.clusterRadiusMeters = 80,
  });

  final List<ClusterMarker> markers;
  final ValueChanged<List<ClusterMarker>> onClusterTap;
  final ValueChanged<ClusterMarker> onMarkerTap;
  final double clusterRadiusMeters;

  @override
  Widget build(BuildContext context) {
    final clusters = _cluster(markers, clusterRadiusMeters);
    return MarkerLayer(
      markers: [
        for (final c in clusters)
          Marker(
            width: c.isCluster ? 56 : 44,
            height: c.isCluster ? 56 : 44,
            point: c.centroid,
            child: _ClusterBubble(
              cluster: c,
              onTap: () {
                if (c.isCluster) {
                  onClusterTap(c.items);
                } else {
                  onMarkerTap(c.items.first);
                }
              },
            ),
          ),
      ],
    );
  }
}

class ClusterMarker {
  const ClusterMarker({required this.id, required this.point, this.label});
  final String id;
  final LatLng point;
  final String? label;
}

class _Cluster {
  _Cluster(this.centroid, this.items);
  final LatLng centroid;
  final List<ClusterMarker> items;
  bool get isCluster => items.length > 1;
}

class _ClusterBubble extends StatefulWidget {
  const _ClusterBubble({required this.cluster, required this.onTap});
  final _Cluster cluster;
  final VoidCallback onTap;
  @override
  State<_ClusterBubble> createState() => _ClusterBubbleState();
}

class _ClusterBubbleState extends State<_ClusterBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _scale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
    _pulse = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
    );
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(covariant _ClusterBubble old) {
    super.didUpdateWidget(old);
    if (old.cluster.items.length != widget.cluster.items.length) {
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cluster;
    final theme = Theme.of(context);
    final color = c.isCluster
        ? theme.colorScheme.primary
        : theme.colorScheme.tertiary;
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (ctx, child) {
          final s = c.isCluster ? _scale.value : _pulse.value;
          return Transform.scale(
            scale: s,
            child: child,
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: c.isCluster
              ? Text(
                  '${c.items.length}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                )
              : Icon(
                  Icons.scuba_diving,
                  size: 22,
                  color: theme.colorScheme.onTertiary,
                ),
        ),
      ),
    );
  }
}

/// Greedy O(N) cluster algorithm. Returns one [_Cluster] per group.
List<_Cluster> _cluster(
  List<ClusterMarker> markers,
  double radiusMeters,
) {
  final remaining = [...markers];
  final clusters = <_Cluster>[];
  const earthRadius = 6371000.0; // meters
  while (remaining.isNotEmpty) {
    final seed = remaining.removeAt(0);
    var latSum = seed.point.latitude;
    var lngSum = seed.point.longitude;
    var count = 1;
    final members = <ClusterMarker>[seed];
    final toRemove = <int>[];
    for (var i = 0; i < remaining.length; i++) {
      final other = remaining[i];
      final dLat = (other.point.latitude - seed.point.latitude) * math.pi / 180;
      final dLng = (other.point.longitude - seed.point.longitude) * math.pi / 180;
      final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
          math.cos(seed.point.latitude * math.pi / 180) *
              math.cos(other.point.latitude * math.pi / 180) *
              math.sin(dLng / 2) *
              math.sin(dLng / 2);
      final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
      final dist = earthRadius * c;
      if (dist <= radiusMeters) {
        latSum += other.point.latitude;
        lngSum += other.point.longitude;
        count++;
        members.add(other);
        toRemove.add(i);
      }
    }
    // Remove the consumed markers (iterate in reverse).
    for (var j = toRemove.length - 1; j >= 0; j--) {
      remaining.removeAt(toRemove[j]);
    }
    final centroid = LatLng(latSum / count, lngSum / count);
    clusters.add(_Cluster(centroid, members));
  }
  return clusters;
}
