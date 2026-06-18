import '../../core/models/dive_log.dart';

/// Conservative recreational no-fly / surface interval guidance.
class SurfaceIntervalStatus {
  const SurfaceIntervalStatus({
    required this.lastDiveEnd,
    required this.noFlyAt,
    required this.nextDiveOkAt,
    required this.multiDiveDay,
  });

  final DateTime lastDiveEnd;
  final DateTime noFlyAt;
  final DateTime nextDiveOkAt;
  final bool multiDiveDay;

  bool get canFlyNow => DateTime.now().isAfter(noFlyAt);
  bool get canDiveNow => DateTime.now().isAfter(nextDiveOkAt);

  Duration get untilNoFly {
    final now = DateTime.now();
    if (now.isAfter(noFlyAt)) return Duration.zero;
    return noFlyAt.difference(now);
  }

  Duration get untilNextDive {
    final now = DateTime.now();
    if (now.isAfter(nextDiveOkAt)) return Duration.zero;
    return nextDiveOkAt.difference(now);
  }

  static SurfaceIntervalStatus? fromLogs(List<DiveLog> logs) {
    if (logs.isEmpty) return null;

    final sorted = [...logs]..sort((a, b) {
        final aEnd = _endTime(a);
        final bEnd = _endTime(b);
        return bEnd.compareTo(aEnd);
      });

    final latest = sorted.first;
    final end = _endTime(latest);
    final sameDay = logs.where((l) =>
        l.diveDate.year == latest.diveDate.year &&
        l.diveDate.month == latest.diveDate.month &&
        l.diveDate.day == latest.diveDate.day);
    final multi = sameDay.length > 1;

    // RSTC-style conservative defaults (not a decompression engine).
    final surfaceHours = multi ? 18 : 12;
    final intervalMin = multi ? 60 : 45;

    return SurfaceIntervalStatus(
      lastDiveEnd: end,
      noFlyAt: end.add(Duration(hours: surfaceHours)),
      nextDiveOkAt: end.add(Duration(minutes: intervalMin)),
      multiDiveDay: multi,
    );
  }

  static DateTime _endTime(DiveLog log) {
    if (log.exitTime != null) return log.exitTime!;
    if (log.entryTime != null) {
      return log.entryTime!.add(Duration(minutes: log.durationMin));
    }
    return DateTime(
      log.diveDate.year,
      log.diveDate.month,
      log.diveDate.day,
      12,
    ).add(Duration(minutes: log.durationMin));
  }
}

String formatDuration(Duration d) {
  if (d <= Duration.zero) return 'now';
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  if (h > 0) return '${h}h ${m}m';
  return '${m}m';
}
