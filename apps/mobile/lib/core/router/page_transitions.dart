import 'package:flutter/material.dart';

/// Fade + slight vertical lift. Used for tab root pages.
/// Feels like the content surfaces from beneath the previous screen.
class FadeUpPageTransitionsBuilder extends PageTransitionsBuilder {
  const FadeUpPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

/// Shared-axis horizontal slide. Used for drill-down detail routes
/// (e.g. dive log list → detail, species list → species detail).
/// Secondary animation provides the subtle push-back on the source page.
class SharedAxisHorizontalTransitionsBuilder extends PageTransitionsBuilder {
  const SharedAxisHorizontalTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Incoming page slides in from right + fades
    final enterCurve = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    // Source page slides slightly to the left while fading
    final exitCurve = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeOutCubic,
    );

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1.0, 0),
        end: Offset.zero,
      ).animate(enterCurve),
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.0, end: 1.0).animate(enterCurve),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: Offset.zero,
            end: const Offset(-0.12, 0),
          ).animate(exitCurve),
          child: child,
        ),
      ),
    );
  }
}

/// Scale + fade. Used for modal-like screens (bottom-up feel, e.g. quick
/// log, settings overlays) so they feel distinct from lateral navigation.
class ScaleFadeTransitionsBuilder extends PageTransitionsBuilder {
  const ScaleFadeTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutQuart,
      reverseCurve: Curves.easeInQuart,
    );
    return ScaleTransition(
      scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
      child: FadeTransition(opacity: curved, child: child),
    );
  }
}
