import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'motion.dart';
import 'tokens.dart';

/// An environment shared by the form and its floating player. Static light
/// fields provide something for the lenses to refract, without an idle ticker.
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
    final blue = dark
        ? AppPalette.darkEnvironmentBlue
        : AppPalette.lightEnvironmentBlue;
    final violet = dark
        ? AppPalette.darkEnvironmentViolet
        : AppPalette.lightEnvironmentViolet;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(.95, -.82),
          radius: 1.12,
          colors: [
            blue.withValues(alpha: dark ? .42 : .64),
            blue.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-1, .85),
          radius: 1.05,
          colors: [
            violet.withValues(alpha: dark ? .46 : .56),
            violet.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );
    // A broad, quiet fold of environmental light, rather than floating blobs.
    final fold = Path()
      ..moveTo(-size.width * .25, size.height * .91)
      ..cubicTo(
        size.width * .16,
        size.height * .67,
        size.width * .63,
        size.height * 1.05,
        size.width * 1.18,
        size.height * .76,
      )
      ..lineTo(size.width * 1.18, size.height * .88)
      ..cubicTo(
        size.width * .58,
        size.height * 1.10,
        size.width * .12,
        size.height * .74,
        -size.width * .25,
        size.height * 1.02,
      )
      ..close();
    canvas.drawPath(
      fold,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            blue.withValues(alpha: .10),
            violet.withValues(alpha: .30),
            blue.withValues(alpha: .22),
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

/// Real backdrop displacement on Impeller; bounded blur and the same optical
/// rim on other renderers. Foreground text never enters the filter input.
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
  bool get field => !material.refraction;

  @override
  State<OpticalGlassSurface> createState() => _OpticalGlassSurfaceState();
}

class _OpticalGlassSurfaceState extends State<OpticalGlassSurface> {
  static Future<ui.FragmentProgram>? _program;
  ui.FragmentShader? shader;
  bool loading = false, failed = false, pressed = false, hovered = false;
  Alignment light = const Alignment(-.65, -.9);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    prepareLens();
  }

  @override
  void didUpdateWidget(OpticalGlassSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    prepareLens();
  }

  void prepareLens() {
    if (loading ||
        failed ||
        shader != null ||
        widget.solid ||
        widget.field ||
        !ui.ImageFilter.isShaderFilterSupported) {
      return;
    }
    loading = true;
    (_program ??= ui.FragmentProgram.fromAsset(
      'shaders/liquid_lens.frag',
    )).then(
      (program) {
        if (!mounted) return;
        setState(() {
          shader = program.fragmentShader();
          loading = false;
        });
      },
      onError: (Object error, StackTrace stack) {
        // Drivers that cannot compile the effect retain a usable blur material.
        debugPrint('Liquid lens unavailable; using bounded blur: $error');
        if (mounted) {
          setState(() {
            loading = false;
            failed = true;
          });
        }
      },
    );
  }

  void point(Offset local) {
    final size = context.size;
    if (size == null || size.isEmpty) return;
    light = Alignment(
      (local.dx / size.width * 2 - 1).clamp(-1, 1),
      (local.dy / size.height * 2 - 1).clamp(-1, 1),
    );
  }

  @override
  void dispose() {
    shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final full =
        widget.enabled &&
        AppMotionScope.levelOf(context) == AppMotionLevel.full;
    final solid = widget.solid || AppMotionScope.solidOf(context);
    final radius = BorderRadius.circular(widget.radius);
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
            builder: (context, touch, child) => DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                boxShadow: [
                  if (widget.material.shadow > 0 && !solid)
                    BoxShadow(
                      color: const Color(0xFF1C3155).withValues(
                        alpha: (dark ? .20 : .07) * widget.material.shadow,
                      ),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  if (focus > 0)
                    BoxShadow(
                      color: primary.withValues(alpha: .12 * focus),
                      blurRadius: 9,
                      spreadRadius: .3,
                    ),
                ],
              ),
              child: ClipRRect(
                borderRadius: radius,
                child: Builder(
                  builder: (context) {
                    final refracting =
                        !solid && !widget.field && shader != null;
                    final tint = widget.base.withValues(
                      alpha: solid
                          ? 1
                          : (dark
                                ? widget.material.darkTint *
                                      (refracting ? .095 : 1)
                                : (refracting
                                      ? widget.material.lightTint * .345
                                      : widget.material.lightTint)),
                    );
                    final surface = CustomPaint(
                      foregroundPainter: _LensRimPainter(
                        radius: widget.radius,
                        dark: dark,
                        solid: solid,
                        field: widget.field,
                        rim: widget.rim,
                        primary: primary,
                        outline: Theme.of(context).colorScheme.onSurfaceVariant
                            .withValues(alpha: .65),
                        focus: focus,
                        touch: touch,
                        light: light,
                        highlight: widget.material.highlight,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: tint,
                          gradient: solid
                              ? null
                              : LinearGradient(
                                  begin: light,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color.alphaBlend(
                                      widget.rim.withValues(
                                        alpha: dark
                                            ? .025
                                            : (widget.field
                                                  ? .10 + touch * .04
                                                  : .24 + touch * .10),
                                      ),
                                      tint,
                                    ),
                                    tint,
                                    Color.alphaBlend(
                                      widget.rim.withValues(
                                        alpha: dark ? .015 : .09,
                                      ),
                                      tint,
                                    ),
                                  ],
                                  stops: const [0, .5, 1],
                                ),
                        ),
                        child: child,
                      ),
                    );
                    if (solid) return surface;
                    if (refracting) {
                      return _BackdropLens(
                        shader: shader!,
                        radius: widget.radius,
                        dark: dark,
                        scale: View.of(context).devicePixelRatio,
                        blur: widget.material.blur,
                        child: surface,
                      );
                    }
                    final filter = ui.ImageFilter.blur(
                      sigmaX: widget.material.blur,
                      sigmaY: widget.material.blur,
                    );
                    return widget.material.grouped
                        ? BackdropFilter.grouped(filter: filter, child: surface)
                        : BackdropFilter(filter: filter, child: surface);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BackdropLens extends SingleChildRenderObjectWidget {
  const _BackdropLens({
    required this.shader,
    required this.radius,
    required this.dark,
    required this.scale,
    required this.blur,
    required super.child,
  });
  final ui.FragmentShader shader;
  final double radius, scale, blur;
  final bool dark;

  @override
  RenderBackdropFilter createRenderObject(BuildContext context) =>
      RenderLiquidLens(
        shader: shader,
        radius: radius,
        dark: dark,
        scale: scale,
        blur: blur,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderLiquidLens renderObject,
  ) => renderObject.configure(shader, radius, dark, scale, blur);
}

class RenderLiquidLens extends RenderBackdropFilter {
  RenderLiquidLens({
    required this.shader,
    required this.radius,
    required this.dark,
    required this.scale,
    required this.blur,
  }) : super(filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6));
  ui.FragmentShader shader;
  double radius, scale, blur;
  bool dark;
  (Size, Offset, double, double, bool, double)? geometry;
  ui.ImageFilter? lensFilter;

  void configure(
    ui.FragmentShader nextShader,
    double nextRadius,
    bool nextDark,
    double nextScale,
    double nextBlur,
  ) {
    if (shader == nextShader &&
        radius == nextRadius &&
        dark == nextDark &&
        scale == nextScale &&
        blur == nextBlur) {
      return;
    }
    shader = nextShader;
    radius = nextRadius;
    dark = nextDark;
    scale = nextScale;
    blur = nextBlur;
    geometry = null;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final origin = localToGlobal(Offset.zero);
    final next = (size, origin, radius, scale, dark, blur);
    if (!size.isEmpty && geometry != next) {
      geometry = next;
      shader
        ..setFloat(2, size.width)
        ..setFloat(3, size.height)
        ..setFloat(4, radius)
        ..setFloat(5, dark ? 1 : 0)
        ..setFloat(6, origin.dx)
        ..setFloat(7, origin.dy)
        ..setFloat(8, scale);
      lensFilter = ui.ImageFilter.compose(
        outer: ui.ImageFilter.shader(shader),
        inner: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      );
    }
    if (child == null || lensFilter == null) return;
    // Update the retained layer directly during paint. Setting a render
    // object's filter here would call markNeedsPaint during the paint phase.
    layer ??= BackdropFilterLayer();
    layer!.filter = lensFilter;
    context.pushLayer(
      layer!,
      (context, offset) => context.paintChild(child!, offset),
      offset,
    );
  }
}

class _LensRimPainter extends CustomPainter {
  const _LensRimPainter({
    required this.radius,
    required this.dark,
    required this.solid,
    required this.field,
    required this.rim,
    required this.primary,
    required this.outline,
    required this.focus,
    required this.touch,
    required this.light,
    required this.highlight,
  });
  final double radius, focus, touch, highlight;
  final bool dark, solid, field;
  final Color rim, primary, outline;
  final Alignment light;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = (Offset.zero & size).deflate(.6);
    final shape = RRect.fromRectAndRadius(
      rect,
      Radius.circular(math.max(0, radius - .6)),
    );
    final paint = Paint()..style = PaintingStyle.stroke;
    Color reflection(double alpha) =>
        rim.withValues(alpha: (alpha * highlight).clamp(0, 1));
    if (solid) {
      canvas.drawRRect(
        shape,
        paint
          ..strokeWidth = focus > 0 ? 1.5 : .8
          ..color = focus > 0 ? primary : outline,
      );
      return;
    }
    // Opposing highlights and a darker mid-rim describe a convex meniscus.
    paint
      ..strokeWidth = field ? .9 : 1.15
      ..shader = LinearGradient(
        begin: light,
        end: Alignment.bottomRight,
        colors: [
          reflection(
            field
                ? (dark ? .20 : .72)
                : (dark ? .40 + touch * .12 : .94 + touch * .06),
          ),
          reflection(.12),
          primary.withValues(alpha: field ? .035 : (dark ? .18 : .12)),
          reflection(field ? (dark ? .12 : .50) : (dark ? .30 : .78)),
        ],
        stops: const [0, .32, .68, 1],
      ).createShader(rect);
    canvas.drawRRect(shape, paint);
    final inner = shape.deflate(field ? 1 : 1.8);
    paint
      ..strokeWidth = field ? .5 : .7
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: dark ? .08 : .48),
          Colors.white.withValues(alpha: 0),
          primary.withValues(alpha: dark ? .10 : .09),
        ],
      ).createShader(rect);
    canvas.drawRRect(inner, paint);
    if (!field) {
      paint
        ..strokeWidth = 2.8
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            rim.withValues(alpha: dark ? .035 : .11),
            rim.withValues(alpha: 0),
            rim.withValues(alpha: dark ? .025 : .08),
          ],
          stops: const [0, .30, 1],
        ).createShader(rect);
      canvas.drawRRect(shape.deflate(3.4), paint);
    }
    if (focus > 0) {
      paint
        ..strokeWidth = 1.4
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primary.withValues(alpha: .72 * focus),
            primary.withValues(alpha: .20 * focus),
            primary.withValues(alpha: .58 * focus),
          ],
        ).createShader(rect);
      canvas.drawRRect(shape, paint);
    }
  }

  @override
  bool shouldRepaint(_LensRimPainter old) =>
      radius != old.radius ||
      dark != old.dark ||
      solid != old.solid ||
      field != old.field ||
      rim != old.rim ||
      primary != old.primary ||
      outline != old.outline ||
      focus != old.focus ||
      touch != old.touch ||
      highlight != old.highlight ||
      light != old.light;
}
