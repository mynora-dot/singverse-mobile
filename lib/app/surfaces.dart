import 'package:flutter/material.dart';

import 'motion.dart';
import 'glass_optics.dart';
import 'tokens.dart';

export 'glass_optics.dart' show AppEnvironment, NasEnvironment;
export 'tokens.dart';

enum GlassVariant { regular, control, sheet, toolbar, liquid, field }

/// Keeps the primary action blue and legible; only its sheen responds to touch.
Widget glossyActionLayer(
  BuildContext context,
  Set<WidgetState> states,
  Widget? child,
) {
  final scheme = Theme.of(context).colorScheme;
  if (states.contains(WidgetState.disabled)) {
    return child ?? const SizedBox.shrink();
  }
  return TweenAnimationBuilder<double>(
    tween: Tween(end: states.contains(WidgetState.pressed) ? 1 : 0),
    duration: AppMotionScope.durationOf(context, AppMotion.press),
    builder: (context, press, _) => DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.control),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(scheme.primary, Colors.white, .025 + press * .035)!,
            scheme.primary,
            Color.lerp(scheme.primary, Colors.black, .065)!,
          ],
        ),
        border: Border.all(
          color: scheme.onPrimary.withValues(alpha: .13),
          width: .7,
        ),
      ),
      child: child,
    ),
  );
}

/// One material implementation for every page. The variant selects a shared
/// treatment; callers can tune an exceptional surface without copying effects.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = AppRadii.floating,
    this.solid = false,
    this.variant = GlassVariant.regular,
    this.focused = false,
    this.material,
    this.tint,
    this.enabled = true,
  });
  final Widget child;
  final double radius;
  final bool solid, focused, enabled;
  final GlassVariant variant;
  final GlassMaterialSpec? material;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final tokens = AppSurfaces.of(context);
    final treatment =
        material ??
        switch (variant) {
          GlassVariant.liquid => GlassMaterialSpec.floating,
          GlassVariant.sheet => GlassMaterialSpec.sheet,
          GlassVariant.field => GlassMaterialSpec.field,
          _ => GlassMaterialSpec.standard,
        };
    return OpticalGlassSurface(
      radius: radius,
      solid: solid || AppMotionScope.solidOf(context),
      material: treatment,
      focused: focused,
      enabled: enabled,
      base: tint ?? tokens.glass,
      rim: tokens.rim,
      child: child,
    );
  }
}
