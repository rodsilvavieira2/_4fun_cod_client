import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Context-appropriate page transitions for the app router.
///
/// Rules (see flutter-animation-engineering skill):
/// - Use [Transition] widgets (compositing only, no relayout per frame).
/// - One shared curve ([Curves.easeOutCubic]) and short desktop-grade
///   durations (150–250 ms).
/// - go_router plays [CustomTransitionPage] in reverse automatically on pop,
///   so push/pop directions stay semantically correct with no extra code.
///
/// Which transition to use:
/// - [fadeThroughPage]: unrelated fullscreen replaces driven by redirects
///   (splash, login, home) — no spatial direction exists.
/// - [slideHorizontalPage]: hierarchical or lateral navigation (auth siblings,
///   home → server/DM shells, server → members) — new screen slides in from
///   the right, pops back to the right.
/// - [modalScalePage]: card-like screens over the current context (invite) —
///   matches the fade+scale language of `showMacModalWindow`.
/// - [instantPage]: visual no-ops (redirect screens) — avoids a flash frame.
CustomTransitionPage<T> fadeThroughPage<T>({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: key,
    transitionDuration: const Duration(milliseconds: 200),
    reverseTransitionDuration: const Duration(milliseconds: 150),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(opacity: curved, child: child);
    },
    child: child,
  );
}

CustomTransitionPage<T> slideHorizontalPage<T>({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: key,
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.08, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
    child: child,
  );
}

CustomTransitionPage<T> modalScalePage<T>({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: key,
    transitionDuration: const Duration(milliseconds: 180),
    reverseTransitionDuration: const Duration(milliseconds: 150),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
    child: child,
  );
}

NoTransitionPage<T> instantPage<T>({
  required LocalKey key,
  required Widget child,
}) {
  return NoTransitionPage<T>(key: key, child: child);
}
