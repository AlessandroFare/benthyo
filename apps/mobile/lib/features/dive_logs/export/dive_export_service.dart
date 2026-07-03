import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/models/dive_log.dart';
import '../../../core/models/enums.dart';
import '../widgets/dive_profile_chart.dart';

/// Generates GPX 1.1 and UDDF 3.2 export files from a [DiveLog] and
/// exposes them via the system share sheet.
class DiveExportService {
  /// Exports [log] in the requested [format], writes the file to the
  /// OS temp directory, and triggers the share sheet.
  static Future<void> share(DiveLog log, DiveExportFormat format) async {
    final String content;
    final String filename;
    final String mimeType;

    switch (format) {
      case DiveExportFormat.gpx:
        content = _buildGpx(log);
        filename =
            'dive_${log.diveNumber ?? log.id.substring(0, 8)}_${_safeDate(log.diveDate)}.gpx';
        mimeType = 'application/gpx+xml';
      case DiveExportFormat.uddf:
        content = _buildUddf(log);
        filename =
            'dive_${log.diveNumber ?? log.id.substring(0, 8)}_${_safeDate(log.diveDate)}.uddf';
        mimeType = 'application/x-uddf';
    }

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$filename');
    await file.writeAsString(content, flush: true);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: mimeType)],
      subject: filename,
    );
  }

  // ---------------------------------------------------------------------------
  // GPX 1.1 builder
  // Generates a track with one trackpoint per sample.
  // Depth is conveyed via the Garmin TrackPointExtension namespace
  // (gpxtpx:depth), which is understood by Subsurface, DiveIno, etc.
  // When no GPS coordinates are available, lat/lon are omitted from the
  // extension (0,0 would mislead mapping tools).
  // ---------------------------------------------------------------------------
  static String _buildGpx(DiveLog log) {
    final buf = StringBuffer();
    final ts = log.entryTime ?? log.diveDate;
    final samples = log.profileSamples
        .map(DiveProfileSample.fromJson)
        .toList()
      ..sort((a, b) => a.timeSec.compareTo(b.timeSec));

    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln(
      '<gpx version="1.1" creator="Benthyo"'
      ' xmlns="http://www.topografix.com/GPX/1/1"'
      ' xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v2"'
      ' xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"'
      ' xsi:schemaLocation="http://www.topografix.com/GPX/1/1'
      ' http://www.topografix.com/GPX/1/1/gpx.xsd">',
    );
    buf.writeln('  <metadata>');
    buf.writeln(
        '    <name>Dive #${log.diveNumber ?? "?"} — ${_safeDate(log.diveDate)}</name>');
    buf.writeln('    <time>${ts.toUtc().toIso8601String()}</time>');
    buf.writeln('  </metadata>');
    buf.writeln('  <trk>');
    buf.writeln('    <name>Dive ${log.diveNumber ?? log.id.substring(0, 8)}</name>');
    buf.writeln('    <type>diving</type>');

    if (samples.isEmpty) {
      // No profile data — write a single summary waypoint.
      buf.writeln('    <trkseg>');
      buf.writeln(_gpxTrkpt(ts, 0, log.maxDepthM));
      buf.writeln('    </trkseg>');
    } else {
      buf.writeln('    <trkseg>');
      for (final s in samples) {
        final sampleTime =
            ts.add(Duration(seconds: s.timeSec.round()));
        buf.writeln(_gpxTrkpt(sampleTime, s.timeSec, s.depthM));
      }
      buf.writeln('    </trkseg>');
    }

    buf.writeln('  </trk>');
    buf.writeln('</gpx>');
    return buf.toString();
  }

  static String _gpxTrkpt(DateTime time, double timeSec, double depthM) {
    // lat/lon are placeholder zeros — real GPS would come from the dive site.
    // Garmin Connect and Subsurface both handle lat=0 lon=0 gracefully by
    // ignoring the map track while still importing the depth profile.
    final iso = time.toUtc().toIso8601String();
    return '      <trkpt lat="0" lon="0">'
        '<time>$iso</time>'
        '<extensions><gpxtpx:TrackPointExtension>'
        '<gpxtpx:depth>${depthM.toStringAsFixed(2)}</gpxtpx:depth>'
        '</gpxtpx:TrackPointExtension></extensions>'
        '</trkpt>';
  }

  // ---------------------------------------------------------------------------
  // UDDF 3.2 builder
  // UDDF (Universal Dive Data Format) is the ISO/DAN-endorsed exchange format
  // supported by Subsurface, DivingLog, Dive+, and most modern logbooks.
  // ---------------------------------------------------------------------------
  static String _buildUddf(DiveLog log) {
    final buf = StringBuffer();
    final ts = log.entryTime ?? log.diveDate;
    final samples = log.profileSamples
        .map(DiveProfileSample.fromJson)
        .toList()
      ..sort((a, b) => a.timeSec.compareTo(b.timeSec));

    final o2Fraction = _o2Fraction(log.gasMix);
    final heFraction = _heFraction(log.gasMix);
    final n2Fraction =
        (1.0 - o2Fraction - heFraction).clamp(0.0, 1.0);

    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln(
      '<uddf xmlns="http://www.streit.cc/uddf/3.2/" version="3.2.0">',
    );

    // Generator block
    buf.writeln('  <generator>');
    buf.writeln('    <name>Benthyo</name>');
    buf.writeln('    <version>1.0</version>');
    buf.writeln(
        '    <datetime>${DateTime.now().toUtc().toIso8601String()}</datetime>');
    buf.writeln('  </generator>');

    // Diver block
    buf.writeln('  <diver>');
    buf.writeln('    <owner id="owner">');
    buf.writeln('      <personal/>');
    buf.writeln('    </owner>');
    buf.writeln('  </diver>');

    // Gas definitions
    buf.writeln('  <gasdefinitions>');
    buf.writeln('    <mix id="mix1">');
    buf.writeln('      <name>${log.gasMix.dbValue.toUpperCase()}</name>');
    buf.writeln(
        '      <o2>${o2Fraction.toStringAsFixed(4)}</o2>');
    buf.writeln(
        '      <n2>${n2Fraction.toStringAsFixed(4)}</n2>');
    buf.writeln(
        '      <he>${heFraction.toStringAsFixed(4)}</he>');
    buf.writeln('    </mix>');
    buf.writeln('  </gasdefinitions>');

    // Profile data
    buf.writeln('  <profiledata>');
    buf.writeln('    <repetitiongroup id="rg1">');
    buf.writeln('      <dive id="dive1">');
    buf.writeln('        <informationbeforedive>');
    if (log.diveNumber != null) {
      buf.writeln('          <divenumber>${log.diveNumber}</divenumber>');
    }
    buf.writeln('          <datetime>${ts.toUtc().toIso8601String()}</datetime>');
    if (log.tankStartBar != null) {
      buf.writeln(
          '          <tankpressurebegin>${_barToPa(log.tankStartBar!)}</tankpressurebegin>');
    }
    buf.writeln('        </informationbeforedive>');

    // Tank / equipment
    if (log.tankSizeL != null || log.tankStartBar != null) {
      buf.writeln('        <tankdata>');
      buf.writeln('          <link ref="mix1"/>');
      if (log.tankSizeL != null) {
        buf.writeln(
            '          <tankvolume>${(log.tankSizeL! / 1000.0).toStringAsFixed(4)}</tankvolume>');
      }
      buf.writeln('        </tankdata>');
    }

    // Samples / waypoints
    buf.writeln('        <samples>');
    if (samples.isEmpty) {
      // Synthesise a minimal 3-point profile from header metadata.
      final durSec = log.durationMin * 60.0;
      buf.writeln('          <waypoint>');
      buf.writeln('            <divetime>0</divetime>');
      buf.writeln('            <depth>0.00</depth>');
      buf.writeln('          </waypoint>');
      buf.writeln('          <waypoint>');
      buf.writeln(
          '            <divetime>${(durSec / 2).round()}</divetime>');
      buf.writeln(
          '            <depth>${log.maxDepthM.toStringAsFixed(2)}</depth>');
      buf.writeln('          </waypoint>');
      buf.writeln('          <waypoint>');
      buf.writeln(
          '            <divetime>${durSec.round()}</divetime>');
      buf.writeln('            <depth>0.00</depth>');
      buf.writeln('          </waypoint>');
    } else {
      for (final s in samples) {
        buf.writeln('          <waypoint>');
        buf.writeln(
            '            <divetime>${s.timeSec.round()}</divetime>');
        buf.writeln(
            '            <depth>${s.depthM.toStringAsFixed(2)}</depth>');
        buf.writeln('          </waypoint>');
      }
    }
    buf.writeln('        </samples>');

    // Post-dive information
    buf.writeln('        <informationafterdive>');
    buf.writeln(
        '          <greatestdepth>${log.maxDepthM.toStringAsFixed(2)}</greatestdepth>');
    buf.writeln(
        '          <diveduration>${log.durationMin * 60}</diveduration>');
    if (log.avgDepthM != null) {
      buf.writeln(
          '          <averagedepth>${log.avgDepthM!.toStringAsFixed(2)}</averagedepth>');
    }
    if (log.waterTempBottomC != null) {
      buf.writeln(
          '          <lowesttemperature>${_celsiusToKelvin(log.waterTempBottomC!)}</lowesttemperature>');
    }
    if (log.tankEndBar != null) {
      buf.writeln(
          '          <tankpressureend>${_barToPa(log.tankEndBar!)}</tankpressureend>');
    }
    buf.writeln('        </informationafterdive>');

    buf.writeln('      </dive>');
    buf.writeln('    </repetitiongroup>');
    buf.writeln('  </profiledata>');
    buf.writeln('</uddf>');
    return buf.toString();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  static String _safeDate(DateTime d) =>
      DateFormat('yyyyMMdd').format(d);

  /// Bar → Pascals (UDDF uses Pascals for pressure).
  static int _barToPa(double bar) => (bar * 100000).round();

  /// Celsius → Kelvin (UDDF uses Kelvin for temperature).
  static String _celsiusToKelvin(double c) =>
      (c + 273.15).toStringAsFixed(2);

  static double _o2Fraction(GasMix mix) => switch (mix) {
        GasMix.air => 0.2095,
        GasMix.nitrox32 => 0.32,
        GasMix.nitrox36 => 0.36,
        GasMix.trimix => 0.21,
      };

  static double _heFraction(GasMix mix) => switch (mix) {
        GasMix.trimix => 0.35,
        _ => 0.0,
      };
}

enum DiveExportFormat { gpx, uddf }
