import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class DiveProfileSample {
  const DiveProfileSample({required this.timeSec, required this.depthM});

  final double timeSec;
  final double depthM;

  factory DiveProfileSample.fromJson(Map<String, dynamic> json) =>
      DiveProfileSample(
        timeSec: (json['t_sec'] as num?)?.toDouble() ??
            (json['timeSec'] as num?)?.toDouble() ??
            0,
        depthM: (json['depth_m'] as num?)?.toDouble() ??
            (json['depthM'] as num?)?.toDouble() ??
            0,
      );
}

class DiveProfileChart extends StatelessWidget {
  const DiveProfileChart({super.key, required this.samples, this.height = 160});

  final List<DiveProfileSample> samples;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (samples.length < 2) {
      return const SizedBox.shrink();
    }

    // CustomPaint is invisible to assistive technology. Summarize the
    // profile numerically so TalkBack/VoiceOver can announce it.
    final sorted = [...samples]
      ..sort((a, b) => a.timeSec.compareTo(b.timeSec));
    final maxDepth = sorted.map((s) => s.depthM).reduce(math.max);
    final maxTimeSec = sorted.map((s) => s.timeSec).reduce(math.max);
    final avgDepth = sorted.map((s) => s.depthM).reduce((a, b) => a + b) /
        sorted.length;
    final profileSummary = 'Dive profile chart. '
        'Maximum depth ${maxDepth.round()} metres, '
        'average depth ${avgDepth.round()} metres, '
        'duration ${(maxTimeSec / 60).toStringAsFixed(1)} minutes.';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dive profile',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              label: profileSummary,
              textDirection: TextDirection.ltr,
              child: SizedBox(
                height: height,
                width: double.infinity,
                child: CustomPaint(
                  painter: _ProfilePainter(samples: samples),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfilePainter extends CustomPainter {
  _ProfilePainter({required this.samples});

  final List<DiveProfileSample> samples;

  @override
  void paint(Canvas canvas, Size size) {
    final sorted = [...samples]..sort((a, b) => a.timeSec.compareTo(b.timeSec));
    final maxDepth = sorted.map((s) => s.depthM).reduce(math.max);
    final maxTime = sorted.map((s) => s.timeSec).reduce(math.max);
    if (maxDepth <= 0 || maxTime <= 0) return;

    const pad = 8.0;
    final chartW = size.width - pad * 2;
    final chartH = size.height - pad * 2;

    final grid = Paint()
      ..color = Colors.grey.withValues(alpha: 0.2)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(pad, pad), Offset(pad, pad + chartH), grid);
    canvas.drawLine(Offset(pad, pad + chartH), Offset(pad + chartW, pad + chartH), grid);

    final path = Path();
    for (var i = 0; i < sorted.length; i++) {
      final s = sorted[i];
      final x = pad + (s.timeSec / maxTime) * chartW;
      final y = pad + (s.depthM / maxDepth) * chartH;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final fill = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;
    final fillPath = Path.from(path)
      ..lineTo(pad + chartW, pad + chartH)
      ..lineTo(pad, pad + chartH)
      ..close();
    canvas.drawPath(fillPath, fill);

    final line = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant _ProfilePainter oldDelegate) =>
      oldDelegate.samples != samples;
}
