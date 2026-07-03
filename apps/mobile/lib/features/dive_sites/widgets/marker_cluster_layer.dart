import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/models/enums.dart';

/// Returns the icon and fill color that best represent a [SiteType].
({IconData icon, Color color}) siteTypeStyle(SiteType? type) {
  return switch (type) {
    SiteType.reef     => (icon: Icons.grass,                    color: const Color(0xFF2ECC71)),
    SiteType.wreck    => (icon: Icons.anchor,                   color: const Color(0xFFE74C3C)),
    SiteType.wall     => (icon: Icons.format_align_right,       color: const Color(0xFF3498DB)),
    SiteType.cave     => (icon: Icons.circle_outlined,          color: const Color(0xFF9B59B6)),
    SiteType.pinnacle => (icon: Icons.landscape,                color: const Color(0xFFF39C12)),
    SiteType.muck     => (icon: Icons.water,                    color: const Color(0xFF95A5A6)),
    _                 => (icon: Icons.scuba_diving,             color: const Color(0xFF00E5FF)),
  };
}

/// Animated marker cluster that groups nearby dive sites into a single
/// visual unit. Single markers show a type-appropriate icon in the site's
/// color; cluster bubbles use an ocean-depth gradient with a count label.
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
            width: c.isCluster ? 56 : 48,
            height: c.isCluster ? 56 : 48,
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
  const ClusterMarker({
    required this.id,
    required this.point,
    this.label,
    this.siteType,
  });
  final String id;
  final LatLng point;
  final String? label;
  final SiteType? siteType;
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

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _scale = Tween<double>(begin: 0.75, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
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

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (ctx, child) => Transform.scale(
          scale: _scale.value,
          child: child,
        ),
        child: c.isCluster
            ? _ClusterPill(count: c.items.length)
            : _SingleMarker(siteType: c.items.first.siteType),
      ),
    );
  }
}

// ── Single-site marker ─────────────────────────────────────────────────────────

class _SingleMarker extends StatelessWidget {
  const _SingleMarker({this.siteType});
  final SiteType? siteType;

  @override
  Widget build(BuildContext context) {
    final style = siteTypeStyle(siteType);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: style.color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: style.color.withValues(alpha: 0.40),
            blurRadius: 10,
            spreadRadius: 1,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(
        style.icon,
        size: 20,
        color: Colors.white,
      ),
    );
  }
}

// ── Cluster bubble ─────────────────────────────────────────────────────────────

class _ClusterPill extends StatelessWidget {
  const _ClusterPill({required this.count});
  final int count;

  /// Map count to an ocean-depth palette: shallow→deep.
  static Color _clusterColor(int count) {
    if (count < 5) return const Color(0xFF0284C7);   // sky-600
    if (count < 15) return const Color(0xFF1D4ED8);  // blue-700
    if (count < 40) return const Color(0xFF1E40AF);  // blue-800
    return const Color(0xFF1E3A5F);                  // deep-navy
  }

  @override
  Widget build(BuildContext context) {
    final color = _clusterColor(count);
    final size = count > 99 ? 60.0 : 52.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: 0.9),
            color,
          ],
          radius: 0.85,
        ),
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.75),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.50),
            blurRadius: 14,
            spreadRadius: 2,
            offset: const Offset(0, 3),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.20),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            count > 99 ? '99+' : '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              height: 1.0,
            ),
          ),
          Text(
            'sites',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 9,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
            ),
          ),
        ],
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
  const earthRadius = 6371000.0;
  while (remaining.isNotEmpty) {
    final seed = remaining.removeAt(0);
    var latSum = seed.point.latitude;
    var lngSum = seed.point.longitude;
    var count = 1;
    final members = <ClusterMarker>[seed];
    final toRemove = <int>[];
    for (var i = 0; i < remaining.length; i++) {
      final other = remaining[i];
      final dLat =
          (other.point.latitude - seed.point.latitude) * math.pi / 180;
      final dLng =
          (other.point.longitude - seed.point.longitude) * math.pi / 180;
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
    for (var j = toRemove.length - 1; j >= 0; j--) {
      remaining.removeAt(toRemove[j]);
    }
    final centroid = LatLng(latSum / count, lngSum / count);
    clusters.add(_Cluster(centroid, members));
  }
  return clusters;
}
