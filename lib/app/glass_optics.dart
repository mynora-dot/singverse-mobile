import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fluid_glass/fluid_glass.dart' as fg;
import 'package:flutter/material.dart';

import 'motion.dart';
import 'tokens.dart';

/// A luminous neutral environment shared by content and floating Liquid Glass.
class AppEnvironment extends StatelessWidget {
  const AppEnvironment({
    super.key,
    required this.child,
    this.enabled = true,
    this.solid = false,
  });
  final Widget child;
  final bool enabled, solid;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final parent = context
        .dependOnInheritedWidgetOfExactType<_AppEnvironmentScope>();
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = parent?.size ?? constraints.biggest;
        return _AppEnvironmentScope(
          size: size,
          child: Stack(
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _EnvironmentPainter(
                      dark: Theme.of(context).brightness == Brightness.dark,
                      solid: solid || AppMotionScope.solidOf(context),
                      base: Theme.of(context).scaffoldBackgroundColor,
                      environmentSize: size,
                    ),
                  ),
                ),
              ),
              child,
            ],
          ),
        );
      },
    );
  }
}

/// Compatibility name for existing route integrations.
class NasEnvironment extends AppEnvironment {
  const NasEnvironment({
    super.key,
    required super.child,
    super.enabled,
    super.solid,
  });
}

/// Provides the captured [fg.LayerBackdrop] to floating glass overlays above
/// a [AppBackdropSource] without ever placing the consumer inside the source.
class AppBackdropScope extends InheritedWidget {
  const AppBackdropScope({
    super.key,
    required this.backdrop,
    required super.child,
  });

  final fg.LayerBackdrop? backdrop;

  static fg.LayerBackdrop? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppBackdropScope>()?.backdrop;

  @override
  bool updateShouldNotify(AppBackdropScope oldWidget) =>
      backdrop != oldWidget.backdrop;
}

/// Owns a [fg.LayerBackdrop] lifecycle and exposes it to [builder].
class AppBackdropCapture extends StatefulWidget {
  const AppBackdropCapture({
    super.key,
    required this.builder,
    this.solid = false,
  });

  final Widget Function(BuildContext context, fg.LayerBackdrop? backdrop)
  builder;
  final bool solid;

  @override
  State<AppBackdropCapture> createState() => _AppBackdropCaptureState();
}

class _AppBackdropCaptureState extends State<AppBackdropCapture> {
  final fg.LayerBackdrop _backdrop = fg.LayerBackdrop();

  @override
  void dispose() {
    _backdrop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = !(widget.solid || AppMotionScope.solidOf(context));
    return widget.builder(context, active ? _backdrop : null);
  }
}

/// Wraps background content so floating [OpticalGlassSurface] overlays above
/// it can sample and refract it via [fg.BackdropLayer].
class AppBackdropSource extends StatelessWidget {
  const AppBackdropSource({
    super.key,
    required this.backdrop,
    required this.child,
  });

  final fg.LayerBackdrop? backdrop;
  final Widget child;

  @override
  Widget build(BuildContext context) => backdrop == null
      ? child
      : fg.BackdropLayer(backdrop: backdrop!, child: child);
}

class _AppEnvironmentScope extends InheritedWidget {
  const _AppEnvironmentScope({required this.size, required super.child});
  final Size size;
  @override
  bool updateShouldNotify(_AppEnvironmentScope oldWidget) =>
      size != oldWidget.size;
}

class _EnvironmentPainter extends CustomPainter {
  const _EnvironmentPainter({
    required this.dark,
    required this.solid,
    required this.base,
    required this.environmentSize,
  });
  final bool dark, solid;
  final Color base;
  final Size environmentSize;

  @override
  void paint(Canvas canvas, Size localSize) {
    final size = environmentSize;
    canvas.save();
    canvas.clipRect(Offset.zero & localSize);
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = base);
    if (solid) {
      canvas.restore();
      return;
    }
    final rose = dark ? const Color(0xFFD94862) : const Color(0xFFFA2D55);
    final sky = dark ? const Color(0xFF4A6FA5) : const Color(0xFF5CA4FF);
    final warm = dark ? const Color(0xFFB87D56) : const Color(0xFFFFA880);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.72, -.98),
          radius: 1.30,
          colors: [
            rose.withValues(alpha: dark ? .06 : .12),
            rose.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(.86, -.80),
          radius: 1.22,
          colors: [
            sky.withValues(alpha: dark ? .05 : .14),
            sky.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, 1.05),
          radius: 1.15,
          colors: [
            warm.withValues(alpha: dark ? .045 : .11),
            warm.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EnvironmentPainter oldDelegate) =>
      dark != oldDelegate.dark ||
      solid != oldDelegate.solid ||
      base != oldDelegate.base ||
      environmentSize != oldDelegate.environmentSize;
}

/// Real spherical-lens Liquid Glass via `fluid_glass` for floating overlays;
/// clean, mist-free surface or bounded blur for static cards and fallbacks.
class OpticalGlassSurface extends StatefulWidget {
  const OpticalGlassSurface({
    super.key,
    required this.child,
    required this.base,
    required this.rim,
    required this.radius,
    required this.solid,
    this.material = GlassMaterialSpec.floating,
    this.focused = false,
    this.enabled = true,
  });
  final Widget child;
  final Color base, rim;
  final double radius;
  final bool solid, focused, enabled;
  final GlassMaterialSpec material;

  @override
  State<OpticalGlassSurface> createState() => _OpticalGlassSurfaceState();
}

class _OpticalGlassSurfaceState extends State<OpticalGlassSurface> {
  static final _lightTone = _lensTone(false);
  static final _darkTone = _lensTone(true);
  bool pressed = false, hovered = false;
  Alignment light = const Alignment(-.55, -1.0);

  void point(Offset local) {
    final size = context.size;
    if (size == null || size.isEmpty) return;
    light = Alignment(
      (local.dx / size.width * 2 - 1).clamp(-1, 1),
      (local.dy / size.height * 2 - 1).clamp(-1, 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final outline = MediaQuery.highContrastOf(context)
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : Theme.of(context).colorScheme.outlineVariant;
    final full =
        widget.enabled &&
        AppMotionScope.levelOf(context) == AppMotionLevel.full;
    final solid = widget.solid || AppMotionScope.solidOf(context);
    final scopeBackdrop = AppBackdropScope.maybeOf(context);
    final useFluidLens =
        !solid && widget.material.refraction && scopeBackdrop != null;
    final radius = BorderRadius.circular(widget.radius);
    final textDirection = Directionality.of(context);

    return MouseRegion(
      onEnter: full ? (_) => setState(() => hovered = true) : null,
      onExit: (_) {
        if (hovered) setState(() => hovered = false);
      },
      onHover: full
          ? (event) => setState(() => point(event.localPosition))
          : null,
      child: Listener(
        onPointerDown: full
            ? (event) => setState(() {
                point(event.localPosition);
                pressed = true;
              })
            : null,
        onPointerMove: full
            ? (event) {
                if (pressed) setState(() => point(event.localPosition));
              }
            : null,
        onPointerUp: (_) {
          if (pressed) setState(() => pressed = false);
        },
        onPointerCancel: (_) {
          if (pressed) setState(() => pressed = false);
        },
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: widget.enabled && widget.focused ? 1 : 0),
          duration: AppMotionScope.durationOf(context, AppMotion.release),
          builder: (context, focus, _) => TweenAnimationBuilder<double>(
            tween: Tween(end: full && (pressed || hovered) ? 1 : 0),
            duration: full
                ? (pressed ? AppMotion.press : AppMotion.release)
                : Duration.zero,
            curve: Curves.easeOutCubic,
            child: RepaintBoundary(
              child: Material(
                type: MaterialType.transparency,
                child: widget.child,
              ),
            ),
            builder: (context, touch, child) {
              if (useFluidLens) {
                final shape = widget.radius >= 99
                    ? const fg.Capsule()
                    : fg.RoundedRectangle(widget.radius);
                final tintAlpha = dark
                    ? widget.material.darkTint
                    : widget.material.lightTint;
                final highlightAlpha =
                    (widget.material.highlight * .85 + touch * .12).clamp(
                      0.0,
                      1.0,
                    );
                return fg.DrawBackdrop(
                  backdrop: scopeBackdrop,
                  shape: () => shape,
                  effects: (scope) {
                    scope.vibrancy();
                    if (widget.material.blur > 0) {
                      scope.blur(widget.material.blur);
                    }
                    final height = math.min(
                      14.0,
                      math.max(8.0, scope.size.shortestSide * .24),
                    );
                    scope.lens(
                      height,
                      height * 1.85,
                      chromaticAberration: true,
                    );
                  },
                  highlight: () => highlightAlpha <= 0
                      ? null
                      : fg.Highlight(
                          width: .65,
                          alpha: highlightAlpha,
                          style: fg.HighlightStyle.standard,
                        ),
                  shadow: () => widget.material.shadow <= 0
                      ? null
                      : fg.GlassShadow(
                          radius: 24,
                          alpha: (dark ? .55 : .28) * widget.material.shadow,
                        ),
                  innerShadow: null,
                  onDrawSurface: (canvas, size) {
                    final rect = Offset.zero & size;
                    canvas.drawRect(
                      rect,
                      Paint()..color = widget.base.withValues(alpha: tintAlpha),
                    );
                    if (focus > 0) {
                      shape
                          .createOutline(size, textDirection)
                          .draw(
                            canvas,
                            Paint()
                              ..style = PaintingStyle.stroke
                              ..strokeWidth = 1.4
                              ..color = primary.withValues(alpha: .65 * focus),
                          );
                    }
                  },
                  child: child,
                );
              }

              final tint = widget.base.withValues(
                alpha: solid
                    ? 1.0
                    : dark
                    ? widget.material.darkTint
                    : widget.material.lightTint,
              );
              final surface = CustomPaint(
                foregroundPainter: _CleanRimPainter(
                  radius: widget.radius,
                  dark: dark,
                  solid: solid,
                  rim: widget.rim,
                  primary: primary,
                  outline: outline,
                  focus: focus,
                  touch: touch,
                  light: light,
                  highlight: widget.material.highlight,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: tint,
                    gradient: solid || !dark && widget.material.blur == 0
                        ? null
                        : LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color.alphaBlend(
                                widget.rim.withValues(
                                  alpha:
                                      ((dark ? .035 : .14) + touch * .04) *
                                      widget.material.highlight,
                                ),
                                tint,
                              ),
                              tint,
                            ],
                          ),
                  ),
                  child: child,
                ),
              );

              final clipped = ClipRRect(
                borderRadius: radius,
                child: solid || widget.material.blur == 0
                    ? surface
                    : () {
                        final blur = ui.ImageFilter.blur(
                          sigmaX: widget.material.blur,
                          sigmaY: widget.material.blur,
                        );
                        final filter = widget.material.refraction
                            ? ui.ImageFilter.compose(
                                outer: dark ? _darkTone : _lightTone,
                                inner: blur,
                              )
                            : blur;
                        return widget.material.grouped
                            ? BackdropFilter.grouped(
                                filter: filter,
                                child: surface,
                              )
                            : BackdropFilter(filter: filter, child: surface);
                      }(),
              );

              if (widget.material.shadow <= 0 && focus <= 0) {
                return clipped;
              }
              return DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  boxShadow: [
                    if (widget.material.shadow > 0 && !solid) ...[
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: (dark ? .40 : .10) * widget.material.shadow,
                        ),
                        blurRadius: 24,
                        spreadRadius: -4,
                        offset: const Offset(0, 10),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: (dark ? .20 : .04) * widget.material.shadow,
                        ),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                    if (focus > 0)
                      BoxShadow(
                        color: primary.withValues(alpha: .10 * focus),
                        blurRadius: 12,
                        spreadRadius: .5,
                      ),
                  ],
                ),
                child: clipped,
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Linear counterpart of monotonic luminance compression for fallback surfaces.
ui.ColorFilter _lensTone(bool dark) {
  const luminance = [.2126, .7152, .0722];
  final chroma = dark ? .96 : .86;
  final range = dark ? .13 : .24;
  final base = dark ? [.15, .15, .155] : [.71, .71, .71];
  return ui.ColorFilter.matrix([
    for (var row = 0; row < 3; row++) ...[
      for (var column = 0; column < 3; column++)
        (row == column ? chroma : 0) + (range - chroma) * luminance[column],
      0,
      base[row] * 255,
    ],
    0,
    0,
    0,
    1,
    0,
  ]);
}

class _CleanRimPainter extends CustomPainter {
  const _CleanRimPainter({
    required this.radius,
    required this.dark,
    required this.solid,
    required this.rim,
    required this.primary,
    required this.outline,
    required this.focus,
    required this.touch,
    required this.light,
    required this.highlight,
  });
  final double radius, focus, touch, highlight;
  final bool dark, solid;
  final Color rim, primary, outline;
  final Alignment light;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = (Offset.zero & size).deflate(.5);
    final shape = RRect.fromRectAndRadius(
      rect,
      Radius.circular(math.max(0, radius - .5)),
    );
    final paint = Paint()..style = PaintingStyle.stroke;
    if (solid) {
      canvas.drawRRect(
        shape,
        paint
          ..strokeWidth = focus > 0 ? 1.5 : .8
          ..color = focus > 0 ? primary : outline,
      );
      return;
    }

    paint
      ..strokeWidth = .6
      ..color = dark
          ? rim.withValues(alpha: (.10 * highlight).clamp(0, 1))
          : Colors.black.withValues(alpha: .05);
    canvas.drawRRect(shape, paint);

    if (touch > 0) {
      paint
        ..strokeWidth = .9
        ..shader = RadialGradient(
          center: light,
          radius: .9,
          colors: [
            rim.withValues(
              alpha: ((dark ? .32 : .64) * touch * highlight).clamp(0, 1),
            ),
            rim.withValues(alpha: 0),
          ],
          stops: const [0, .72],
        ).createShader(rect);
      canvas.drawRRect(shape, paint);
    }

    if (focus > 0) {
      paint
        ..strokeWidth = 1.1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primary.withValues(alpha: .46 * focus),
            primary.withValues(alpha: .18 * focus),
            primary.withValues(alpha: .38 * focus),
          ],
        ).createShader(rect);
      canvas.drawRRect(shape, paint);
    }
  }

  @override
  bool shouldRepaint(_CleanRimPainter old) =>
      radius != old.radius ||
      dark != old.dark ||
      solid != old.solid ||
      rim != old.rim ||
      primary != old.primary ||
      outline != old.outline ||
      focus != old.focus ||
      touch != old.touch ||
      highlight != old.highlight ||
      light != old.light;
}
