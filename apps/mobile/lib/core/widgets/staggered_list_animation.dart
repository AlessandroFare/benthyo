import 'package:flutter/material.dart';

/// Smooth, performant staggered list animation. Children animate from
/// `y: 16, opacity: 0` to `y: 0, opacity: 1` with a 50 ms per-item
/// delay capped at 12 items (so a 200-item list doesn't take 10 s to
/// settle).
class StaggeredListAnimation extends StatelessWidget {
  const StaggeredListAnimation({
    super.key,
    required this.children,
    this.maxStaggeredItems = 12,
    this.baseDelayMs = 0,
    this.staggerMs = 50,
    this.durationMs = 360,
    this.spacing,
  });

  final List<Widget> children;
  final int maxStaggeredItems;
  final int baseDelayMs;
  final int staggerMs;
  final int durationMs;
  final double? spacing;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < this.children.length; i++) {
      final child = this.children[i];
      final delayMs = baseDelayMs + (i.clamp(0, maxStaggeredItems) * staggerMs);
      children.add(
        _StaggeredItem(
          delayMs: delayMs,
          durationMs: durationMs,
          child: child,
        ),
      );
      if (spacing != null && i < this.children.length - 1) {
        children.add(SizedBox(height: spacing));
      }
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _StaggeredItem extends StatefulWidget {
  const _StaggeredItem({
    required this.delayMs,
    required this.durationMs,
    required this.child,
  });

  final int delayMs;
  final int durationMs;
  final Widget child;

  @override
  State<_StaggeredItem> createState() => _StaggeredItemState();
}

class _StaggeredItemState extends State<_StaggeredItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.durationMs),
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _offset = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(_opacity);

    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}
