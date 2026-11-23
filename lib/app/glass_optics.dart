import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

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
    // Whisper-soft multi-point ambient mesh gives Liquid Glass edges real
    // luminous depth to refract without ever reducing content contrast.
    final rose = dark
        ? AppPalette.darkEnvironmentViolet
        : AppPalette.lightEnvironmentViolet;
    final sky = dark
        ? AppPalette.darkEnvironmentBlue
        : AppPalette.lightEnvironmentBlue;
    final warm = dark
        ? AppPalette.darkEnvironmentWarm
        : AppPalette.lightEnvironmentWarm;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.72, -1.05),
          radius: 1.25,
          colors: [
            rose.withValues(alpha: dark ? .26 : .075),
            rose.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(.86, -.85),
          radius: 1.15,
          colors: [
            sky.withValues(alpha: dark ? .28 : .28),
            sky.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, 1.08),
          radius: 1.05,
          colors: [
            warm.withValues(alpha: dark ? .18 : .16),
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

/// Real backdrop displacement on Impeller; bounded blur and Fresnel specular
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
  static final _lightTone = _lensTone(false);
  static final _darkTone = _lensTone(true);
  ui.FragmentShader? shader;
  bool loading = false, failed = false, pressed = false, hovered = false;
  Alignment light = const Alignment(-.55, -1.0);

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
            builder: (context, touch, child) => DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                boxShadow: [
                  if (widget.material.shadow > 0 && !solid) ...[
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: (dark ? .44 : .12) * widget.material.shadow,
                      ),
                      blurRadius: 28,
                      spreadRadius: -4,
                      offset: const Offset(0, 12),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: (dark ? .24 : .05) * widget.material.shadow,
                      ),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                  if (focus > 0)
                    BoxShadow(
                      color: primary.withValues(alpha: .16 * focus),
                      blurRadius: 12,
                      spreadRadius: 1.0,
                    ),
                ],
              ),
              child: ClipRRect(
                borderRadius: radius,
                child: Builder(
                  builder: (context) {
                    final refracting =
                        !solid && !widget.field && shader != null;
                    final floating = !widget.field;
                    final tint = widget.base.withValues(
                      alpha: solid
                          ? 1
                          : dark
                          ? widget.material.darkTint
                          : widget.material.lightTint,
                    );
                    final surface = CustomPaint(
                      foregroundPainter: _LensRimPainter(
                        radius: widget.radius,
                        dark: dark,
                        solid: solid,
                        field: widget.field,
                        rim: widget.rim,
                        primary: primary,
                        outline: MediaQuery.highContrastOf(context)
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : Theme.of(context).colorScheme.outlineVariant,
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
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color.alphaBlend(
                                      widget.rim.withValues(
                                        alpha:
                                            ((dark ? .08 : .22) + touch * .06) *
                                            widget.material.highlight,
                                      ),
                                      tint,
                                    ),
                                    tint,
                                    Color.alphaBlend(
                                      widget.rim.withValues(
                                        alpha:
                                            (dark ? .02 : .06) *
                                            widget.material.highlight,
                                      ),
                                      tint,
                                    ),
                                  ],
                                  stops: const [0, .42, 1],
                                ),
                        ),
                        child: child,
                      ),
                    );
                    if (solid || widget.material.blur == 0) {
                      return surface;
                    }
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
                    final blur = ui.ImageFilter.blur(
                      sigmaX: widget.material.blur,
                      sigmaY: widget.material.blur,
                    );
                    // Match the shader's neutral contrast compression when
                    // image-filter shaders are unavailable.
                    final filter = floating
                        ? ui.ImageFilter.compose(
                            outer: dark ? _darkTone : _lightTone,
                            inner: blur,
                          )
                        : blur;
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

/// Linear counterpart of the shader's monotonic luminance compression.
/// Color-filter offsets use 0–255; alpha and foreground content stay unchanged.
ui.ColorFilter _lensTone(bool dark) {
  const luminance = [.2126, .7152, .0722];
  final chroma = dark ? .14 : .12;
  final range = dark ? .15 : .26;
  final base = dark ? [.06, .06, .06] : [.69, .69, .69];
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
    final rect = (Offset.zero & size).deflate(.55);
    final shape = RRect.fromRectAndRadius(
      rect,
      Radius.circular(math.max(0, radius - .55)),
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
    // Apple Liquid Glass Fresnel rim: bright top-edge specular catching light
    // fading smoothly to a delicate bottom glass edge.
    paint
      ..strokeWidth = field ? .8 : 1.0
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          reflection(dark ? .46 : .94),
          reflection(dark ? .14 : .42),
          reflection(dark ? .26 : .62),
        ],
        stops: const [0, .5, 1],
      ).createShader(rect);
    canvas.drawRRect(shape, paint);

    // Subtle pointer-following specular bloom on touch/hover.
    if (touch > 0) {
      paint
        ..strokeWidth = 1.15
        ..shader = RadialGradient(
          center: light,
          radius: .9,
          colors: [reflection((dark ? .55 : .95) * touch), reflection(0)],
          stops: const [0, .72],
        ).createShader(rect);
      canvas.drawRRect(shape, paint);
    }

    if (focus > 0) {
      paint
        ..strokeWidth = 1.5
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primary.withValues(alpha: .82 * focus),
            primary.withValues(alpha: .28 * focus),
            primary.withValues(alpha: .66 * focus),
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
