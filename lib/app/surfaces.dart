import 'package:flutter/material.dart';

import 'glass_optics.dart';
import 'motion.dart';
import 'tokens.dart';

export 'glass_optics.dart'
    show
        AppBackdropCapture,
        AppBackdropRouteBinding,
        AppBackdropScope,
        AppBackdropSource,
        AppEnvironment,
        LiquidDropletBox,
        NasEnvironment;
export 'tokens.dart';

enum GlassVariant { regular, sheet, liquid, field }

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
    this.backdropContext = GlassBackdropContext.plain,
  });
  final Widget child;
  final double radius;
  final bool solid, focused, enabled;
  final GlassVariant variant;
  final GlassMaterialSpec? material;
  final Color? tint;
  final GlassBackdropContext backdropContext;

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
      material: treatment.forBackdrop(backdropContext),
      focused: focused,
      enabled: enabled,
      base: tint ?? tokens.glass,
      rim: tokens.rim,
      child: child,
    );
  }
}
