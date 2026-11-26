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

typedef BackdropPair = ({
  fg.LayerBackdrop? environment,
  fg.LayerBackdrop? content,
});

/// Provides the captured [fg.LayerBackdrop] layers (`environment` for in-scroll
/// cards/fields and `content` for floating chrome/sheets) to descendants without
/// ever placing a consumer inside the layer it samples.
class AppBackdropScope extends InheritedWidget {
  const AppBackdropScope({
    super.key,
    fg.LayerBackdrop? backdrop,
    fg.LayerBackdrop? environment,
    fg.LayerBackdrop? content,
    required super.child,
  }) : environment = environment ?? backdrop,
       content = content ?? backdrop;

  final fg.LayerBackdrop? environment;
  final fg.LayerBackdrop? content;

  static final Expando<BackdropPair> _routeBackdrops = Expando<BackdropPair>(
    'AppBackdropScope.routeBackdrops',
  );

  static fg.LayerBackdrop? maybeOf(
    BuildContext context, {
    bool sampleContent = true,
  }) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppBackdropScope>();
    if (scope == null) return null;
    return sampleContent
        ? (scope.content ?? scope.environment)
        : scope.environment;
  }

  static void bindRoute(
    BuildContext context, {
    fg.LayerBackdrop? environment,
    fg.LayerBackdrop? content,
  }) {
    final route = ModalRoute.of(context);
    if (route == null) return;
    _routeBackdrops[route] = (environment: environment, content: content);
  }

  static BackdropPair resolveForSheet(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppBackdropScope>();
    if (scope != null && (scope.environment != null || scope.content != null)) {
      return (environment: scope.environment, content: scope.content);
    }
    final route = ModalRoute.of(context);
    if (route != null) {
      final bound = _routeBackdrops[route];
      if (bound != null) return bound;
    }
    return (environment: null, content: null);
  }

  @override
  bool updateShouldNotify(AppBackdropScope oldWidget) =>
      environment != oldWidget.environment || content != oldWidget.content;
}

/// Binds the nearest [ModalRoute] to [environment] and [content] backdrops so
/// `showAppSheet(context: ...)` called from `State.context` can still sample
/// the underlying route cleanly without self-recursion.
class AppBackdropRouteBinding extends StatelessWidget {
  const AppBackdropRouteBinding({
    super.key,
    this.environment,
    this.content,
    required this.child,
  });

  final fg.LayerBackdrop? environment;
  final fg.LayerBackdrop? content;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    AppBackdropScope.bindRoute(
      context,
      environment: environment,
      content: content,
    );
    return child;
  }
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
  Widget build(BuildContext context) {
    final source = backdrop;
    if (source == null) return child;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification ||
            notification is OverscrollNotification) {
          source.invalidateSource();
        }
        return false;
      },
      child: fg.BackdropLayer(backdrop: source, child: child),
    );
  }
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
    final topWarm = dark ? const Color(0xFFE05268) : const Color(0xFFFF5E7E);
    final topCool = dark ? const Color(0xFF4378DB) : const Color(0xFF569BFF);
    final bottomWarm = dark ? const Color(0xFFE06D44) : const Color(0xFFFF8E66);
    final bottomCool = dark ? const Color(0xFF3E6EC9) : const Color(0xFF6AA6FF);
    final midAccent = dark ? const Color(0xFF7B4AC9) : const Color(0xFFB5CCFF);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.74, -.94),
          radius: 1.25,
          colors: [
            topWarm.withValues(alpha: dark ? .15 : .18),
            topWarm.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(.82, -.82),
          radius: 1.20,
          colors: [
            topCool.withValues(alpha: dark ? .13 : .17),
            topCool.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.12, -0.05),
          radius: 1.05,
          colors: [
            midAccent.withValues(alpha: dark ? .07 : .08),
            midAccent.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.62, .96),
          radius: 1.05,
          colors: [
            bottomWarm.withValues(alpha: dark ? .16 : .19),
            bottomWarm.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(.68, .98),
          radius: 1.05,
          colors: [
            bottomCool.withValues(alpha: dark ? .14 : .18),
            bottomCool.withValues(alpha: 0),
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
    final scopeBackdrop = AppBackdropScope.maybeOf(
      context,
      sampleContent: widget.material.sampleContent,
    );
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
                  isolateSurface: false,
                  shape: () => shape,
                  effects: (scope) {
                    scope.vibrancy();
                    if (widget.material.blur > 0) {
                      scope.blur(widget.material.blur);
                    }
                    final maxSide = scope.size.shortestSide;
                    final rawHeight =
                        widget.material.lensHeight ??
                        math.min(20.0, math.max(10.0, maxSide * .34));
                    final height = math.min(rawHeight, maxSide * .42);
                    final amount =
                        widget.material.lensAmount ?? (height * 1.85);
                    scope.lens(
                      height,
                      amount,
                      depthEffect: true,
                      chromaticAberration: true,
                    );
                  },
                  highlight: () => highlightAlpha <= 0
                      ? null
                      : fg.Highlight(
                          width: 1.0,
                          blurRadius: .45,
                          alpha: highlightAlpha,
                          style: dark
                              ? const fg.DefaultHighlightStyle(
                                  color: Color(0xCCFFFFFF),
                                  angle: 45,
                                  falloff: 1.0,
                                )
                              : const fg.AmbientHighlightStyle(intensity: .28),
                        ),
                  shadow: () => widget.material.shadow <= 0
                      ? null
                      : fg.GlassShadow(
                          radius: 22,
                          offset: const Offset(0, 6),
                          color: dark
                              ? const Color(0x66000000)
                              : const Color(0x22000000),
                          alpha: widget.material.shadow,
                        ),
                  innerShadow: () => widget.material.highlight <= 0
                      ? null
                      : fg.GlassInnerShadow(
                          radius: 5,
                          offset: Offset(0, dark ? 2.0 : -2.0),
                          color: dark
                              ? const Color(0x22FFFFFF)
                              : const Color(0x14000000),
                          alpha: widget.material.highlight,
                        ),
                  onDrawSurface: (canvas, size) {
                    final rect = Offset.zero & size;
                    canvas.drawRect(
                      rect,
                      Paint()..color = widget.base.withValues(alpha: tintAlpha),
                    );
                    canvas.drawRect(
                      rect,
                      Paint()
                        ..shader = LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: const [0, .42],
                          colors: [
                            Colors.white.withValues(
                              alpha:
                                  (dark ? .07 : .34) *
                                  widget.material.highlight,
                            ),
                            Colors.white.withValues(alpha: 0),
                          ],
                        ).createShader(rect),
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

/// Luminous convex droplet surface for active tabs, segment thumbs, and toggle
/// selections, giving dark and light glass selectors a crisp 45-degree specular
/// Fresnel edge and subtle drop shadow.
class LiquidDropletBox extends StatelessWidget {
  const LiquidDropletBox({
    super.key,
    this.radius = 999,
    this.solid = false,
    this.accent = false,
    this.compact = false,
    this.child,
  });

  final double radius;
  final bool solid, accent, compact;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final borderRadius = BorderRadius.circular(radius);
    if (solid) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: accent
              ? AppPalette.brand.withValues(alpha: dark ? .24 : .14)
              : scheme.primaryContainer,
          borderRadius: borderRadius,
          border: accent
              ? Border.all(
                  color: AppPalette.brand.withValues(alpha: .62),
                  width: 1,
                )
              : null,
        ),
        child: child,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: accent
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppPalette.brand.withValues(alpha: dark ? .26 : .15),
                  AppPalette.brand.withValues(alpha: dark ? .14 : .08),
                ],
              )
            : dark
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0x3DFFFFFF),
                  Color(0x26FFFFFF),
                  Color(0x1CFFFFFF),
                ],
              )
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFAFFFFFF),
                  Color(0xEBFFFFFF),
                  Color(0xE0F4F6FC),
                ],
              ),
        border: Border.all(
          color: accent
              ? AppPalette.brand.withValues(alpha: dark ? .68 : .52)
              : dark
              ? Colors.white.withValues(alpha: .26)
              : Colors.black.withValues(alpha: .05),
          width: accent ? 1.0 : .75,
        ),
        boxShadow: [
          BoxShadow(
            color: accent
                ? AppPalette.brand.withValues(alpha: dark ? .24 : .14)
                : Colors.black.withValues(alpha: dark ? .26 : .10),
            blurRadius: compact ? 6 : 12,
            offset: Offset(0, compact ? 1.5 : 3),
          ),
        ],
      ),
      child: child,
    );
  }
}
