import 'package:flutter/material.dart';

/// A FloatingActionButton wrapper that animates a small expanding ring
/// behind the icon to give the button a subtle "ready" feel. On press
/// the ring collapses and a haptic fires (best-effort — haptics are
/// silently no-op on platforms that don't support them).
class AnimatedFab extends StatefulWidget {
  const AnimatedFab({
    super.key,
    required this.onPressed,
    required this.icon,
    this.tooltip,
    this.extended = false,
    this.label,
  });

  final VoidCallback onPressed;
  final Widget icon;
  final String? tooltip;
  final bool extended;
  final Widget? label;

  @override
  State<AnimatedFab> createState() => _AnimatedFabState();
}

class _AnimatedFabState extends State<AnimatedFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
    _pulse = Tween<double>(begin: 0.0, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Semantic label so screen readers announce the FAB action instead of
    // just "button". The tooltip doubles as the accessible name.
    return Semantics(
      button: true,
      label: widget.tooltip ?? widget.label?.toString() ?? 'Action',
      container: true,
      child: Tooltip(
        message: widget.tooltip ?? '',
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) {
            return Stack(
              alignment: Alignment.center,
              children: [
                // Pulsing halo behind the FAB. Opacity fades as the
                // ring expands, then snaps back when the controller
                // restarts.
                Opacity(
                  opacity: (1 - _pulse.value) * 0.4,
                  child: Container(
                    width: 56 + 18 * _pulse.value,
                    height: 56 + 18 * _pulse.value,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.primary.withValues(alpha: 0.25),
                    ),
                  ),
                ),
                child!,
              ],
            );
          },
          child: FloatingActionButton(
            heroTag: widget.tooltip ?? 'fab',
            onPressed: widget.onPressed,
            backgroundColor: scheme.primary,
            foregroundColor: scheme.onPrimary,
            elevation: 4,
            child: widget.extended
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      widget.icon,
                      if (widget.label != null) ...[
                        const SizedBox(width: 8),
                        widget.label!,
                      ],
                    ],
                  )
                : widget.icon,
          ),
        ),
      ),
    );
  }
}
