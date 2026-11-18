import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

enum AppMotionLevel { full, reduced, none }

/// UI policy only: media clocks, recording and network work never depend on it.
class AppMotionScope extends InheritedWidget {
  const AppMotionScope({
    super.key,
    required super.child,
    this.performanceMode = false,
    this.senior = false,
    this.reduceTransparency = false,
  });

  final bool performanceMode, senior, reduceTransparency;

  static AppMotionLevel levelOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppMotionScope>();
    if (scope?.performanceMode == true) return AppMotionLevel.none;
    if (scope?.senior == true ||
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context)) {
      return AppMotionLevel.reduced;
    }
    return AppMotionLevel.full;
  }

  static bool solidOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppMotionScope>();
    return scope?.performanceMode == true ||
        scope?.senior == true ||
        scope?.reduceTransparency == true ||
        MediaQuery.highContrastOf(context);
  }

  static Duration durationOf(BuildContext context, Duration full) =>
      switch (levelOf(context)) {
        AppMotionLevel.full => full,
        AppMotionLevel.reduced => const Duration(milliseconds: 100),
        AppMotionLevel.none => Duration.zero,
      };

  @override
  bool updateShouldNotify(AppMotionScope oldWidget) =>
      performanceMode != oldWidget.performanceMode ||
      senior != oldWidget.senior ||
      reduceTransparency != oldWidget.reduceTransparency;
}

class AppSpringCurve extends Curve {
  AppSpringCurve({required Duration duration, double bounce = .08})
    : seconds = duration.inMicroseconds / Duration.microsecondsPerSecond,
      simulation = SpringSimulation(
        SpringDescription.withDurationAndBounce(
          duration: duration,
          bounce: bounce,
        ),
        0,
        1,
        0,
      );

  final double seconds;
  final SpringSimulation simulation;

  @override
  double transformInternal(double t) => simulation.x(t * seconds);
}

abstract final class AppMotion {
  static const press = Duration(milliseconds: 100);
  static const release = Duration(milliseconds: 260);
  static const navigation = Duration(milliseconds: 360);
  static const page = Duration(milliseconds: 320);
  static const sheet = Duration(milliseconds: 360);
  static const expand = Duration(milliseconds: 280);
  static final spring = AppSpringCurve(duration: navigation);
  static final softSpring = AppSpringCurve(duration: release, bounce: .04);

  static AnimationStyle modalStyle(BuildContext context) => AnimationStyle(
    duration: AppMotionScope.durationOf(context, sheet),
    reverseDuration: AppMotionScope.durationOf(context, release),
    curve: AppMotionScope.levelOf(context) == AppMotionLevel.full
        ? spring
        : Curves.linear,
    reverseCurve: Curves.easeInCubic,
  );

  /// ButtonStyle's own state owns gestures, disabled semantics and focus.
  static Widget buttonLayer(
    BuildContext context,
    Set<WidgetState> states,
    Widget? child,
  ) => MotionFeedback(
    pressed: states.contains(WidgetState.pressed),
    hovered: states.contains(WidgetState.hovered),
    enabled: !states.contains(WidgetState.disabled),
    child: child ?? const SizedBox.shrink(),
  );
}

/// Only the accessory's own extent animates. Keyboard dismissal is immediate,
/// and outgoing controls stop accepting input or accessibility focus at once.
class MotionVisibility extends StatefulWidget {
  const MotionVisibility({
    super.key,
    required this.visible,
    required this.child,
    this.immediate = false,
  });
  final bool visible, immediate;
  final Widget child;
  @override
  State<MotionVisibility> createState() => _MotionVisibilityState();
}

class _MotionVisibilityState extends State<MotionVisibility>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    value: widget.visible ? 1 : 0,
  );

  void sync() {
    final target = widget.visible ? 1.0 : 0.0;
    final level = AppMotionScope.levelOf(context);
    if (widget.immediate || level == AppMotionLevel.none) {
      controller.value = target;
    } else {
      controller.animateTo(
        target,
        duration: AppMotionScope.durationOf(
          context,
          widget.visible ? AppMotion.expand : AppMotion.release,
        ),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    sync();
  }

  @override
  void didUpdateWidget(MotionVisibility oldWidget) {
    super.didUpdateWidget(oldWidget);
    sync();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    child: IgnorePointer(
      ignoring: !widget.visible,
      child: ExcludeSemantics(excluding: !widget.visible, child: widget.child),
    ),
    builder: (context, child) {
      if (controller.value == 0 && !widget.visible) {
        return const SizedBox.shrink();
      }
      if (controller.value == 1 && widget.visible) return child!;
      final fade = FadeTransition(opacity: controller, child: child);
      if (AppMotionScope.levelOf(context) != AppMotionLevel.full) return fade;
      return SizeTransition(
        sizeFactor: controller,
        alignment: Alignment.bottomCenter,
        child: fade,
      );
    },
  );
}

class MotionFeedback extends StatelessWidget {
  const MotionFeedback({
    super.key,
    required this.child,
    this.pressed = false,
    this.hovered = false,
    this.enabled = true,
  });
  final Widget child;
  final bool pressed, hovered, enabled;

  @override
  Widget build(BuildContext context) {
    final full = AppMotionScope.levelOf(context) == AppMotionLevel.full;
    return TweenAnimationBuilder<double>(
      tween: Tween(
        end: !full || !enabled ? 1 : (pressed ? .98 : (hovered ? 1.01 : 1)),
      ),
      duration: full
          ? (pressed ? AppMotion.press : AppMotion.release)
          : Duration.zero,
      curve: pressed ? Curves.easeOut : AppMotion.softSpring,
      child: child,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, transformHitTests: false, child: child),
    );
  }
}

/// Observes pointer feedback without adding a second tap recognizer.
class MotionPress extends StatefulWidget {
  const MotionPress({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;
  @override
  State<MotionPress> createState() => _MotionPressState();
}

class _MotionPressState extends State<MotionPress> {
  bool pressed = false, hovered = false;
  Offset? start;
  void release() {
    start = null;
    if (pressed) setState(() => pressed = false);
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => hovered = true),
    onExit: (_) => setState(() => hovered = false),
    child: Listener(
      onPointerDown: widget.enabled
          ? (event) {
              start = event.position;
              setState(() => pressed = true);
            }
          : null,
      onPointerMove: (event) {
        if (start != null && (event.position - start!).distance > 12) release();
      },
      onPointerUp: (_) => release(),
      onPointerCancel: (_) => release(),
      child: MotionFeedback(
        pressed: pressed,
        hovered: hovered,
        enabled: widget.enabled,
        child: widget.child,
      ),
    ),
  );
}

/// One entrance per widget identity; never replayed by progress/data rebuilds.
class MotionEntrance extends StatefulWidget {
  const MotionEntrance({super.key, required this.child, this.index = 0});
  final Widget child;
  final int index;
  @override
  State<MotionEntrance> createState() => _MotionEntranceState();
}

class _MotionEntranceState extends State<MotionEntrance>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(vsync: this);
  bool started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!started && !TickerMode.valuesOf(context).enabled) return;
    final level = AppMotionScope.levelOf(context);
    final storage = PageStorage.maybeOf(context);
    final seen =
        widget.key != null &&
        storage?.readState(context, identifier: widget.key) == true;
    if (level != AppMotionLevel.full ||
        widget.index >= 6 ||
        (!started && seen)) {
      controller.value = 1;
      started = true;
    } else if (!started) {
      started = true;
      controller.duration = Duration(milliseconds: 240 + widget.index * 24);
      controller.forward();
    }
    if (widget.key != null) {
      storage?.writeState(context, true, identifier: widget.key);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    child: widget.child,
    builder: (context, child) {
      final delay = math.min(widget.index, 5) * 24 / (240 + widget.index * 24);
      final t = Curves.easeOutCubic.transform(
        ((controller.value - delay) / (1 - delay)).clamp(0, 1),
      );
      return Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - t)),
          child: child,
        ),
      );
    },
  );
}

/// Keeps every tab mounted and suspends its ticker while another tab is visible.
class MotionTabPane extends StatefulWidget {
  const MotionTabPane({super.key, required this.active, required this.child});
  final bool active;
  final Widget child;
  @override
  State<MotionTabPane> createState() => _MotionTabPaneState();
}

class _MotionTabPaneState extends State<MotionTabPane>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(vsync: this, value: 1);
  @override
  void didUpdateWidget(MotionTabPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      final level = AppMotionScope.levelOf(context);
      if (level != AppMotionLevel.none) {
        controller.duration = AppMotionScope.durationOf(
          context,
          AppMotion.release,
        );
        controller.forward(from: 0);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotionScope.levelOf(context) == AppMotionLevel.none) {
      controller.value = 1;
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: controller, child: widget.child);
}

class MotionExpand extends StatelessWidget {
  const MotionExpand({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => AnimatedSize(
    duration: AppMotionScope.levelOf(context) == AppMotionLevel.full
        ? AppMotion.expand
        : Duration.zero,
    curve: AppMotionScope.levelOf(context) == AppMotionLevel.full
        ? AppMotion.softSpring
        : Curves.linear,
    alignment: Alignment.topCenter,
    child: child,
  );
}

/// Keep Flutter's predictive-back recognizer mounted. A small content spring
/// supplements ordinary navigation; platform views only use the native fade.
class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  @override
  Duration get transitionDuration => AppMotion.page;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final level = AppMotionScope.levelOf(context);
    if (level == AppMotionLevel.none) return child;
    if (level == AppMotionLevel.reduced) {
      return FadeTransition(
        opacity: animation.drive(CurveTween(curve: const Interval(0, .3))),
        child: child,
      );
    }
    final platformView = const {
      'player',
      'tv',
      'scan',
      'admin',
    }.contains(route.settings.name);
    return const PredictiveBackPageTransitionsBuilder().buildTransitions(
      route,
      context,
      route.popGestureInProgress ? animation : const AlwaysStoppedAnimation(1),
      route.popGestureInProgress
          ? secondaryAnimation
          : const AlwaysStoppedAnimation(0),
      AnimatedBuilder(
        animation: animation,
        child: FadeTransition(
          opacity: route.popGestureInProgress
              ? const AlwaysStoppedAnimation(1)
              : animation.drive(CurveTween(curve: Curves.easeOutCubic)),
          child: child,
        ),
        builder: (context, child) => Transform.translate(
          offset: Offset(
            0,
            platformView || route.popGestureInProgress
                ? 0
                : 12 * (1 - AppMotion.softSpring.transform(animation.value)),
          ),
          child: child,
        ),
      ),
    );
  }
}
