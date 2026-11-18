import 'package:flutter/material.dart';

abstract final class AppPalette {
  static const brand = Color(0xFFFA2D55);
  static const brandText = Color(0xFFD8103C);
  static const recording = Color(0xFFD8103C);
  static const ink = Color(0xFF1D1D1F);
  // Compatibility names; the environment is neutral rather than blue/violet.
  static const lightEnvironmentBlue = Color(0xFFE5E5EA);
  static const darkEnvironmentBlue = Color(0xFF2C2C2E);
  static const lightEnvironmentViolet = Color(0xFFF2F2F7);
  static const darkEnvironmentViolet = Color(0xFF1C1C1E);
  static const stage = Color(0xFF131315);
  static const stageAccent = Color(0xFFFF526F);
  static const stageOnAccent = Colors.white;
  static const stageText = Color(0xFFF5F5F7);
  static const stageMuted = Color(0xFF98989D);
  static const stageTrack = Color(0xFF353537);
}

/// Geometry shared by content, standard controls and floating glass.
abstract final class AppSpace {
  static const double xxs = 4, xs = 8, sm = 12, md = 16;
  static const double page = 20, section = 24, large = 32;
}

abstract final class AppRadii {
  static const double artwork = 8, control = 14, content = 14, floating = 24;
  static const double featured = 16;
}

abstract final class AppSizes {
  static const double touch = 44, seniorTouch = 56, field = 52;
  static const double songArtwork = 48, contentWidth = 720;
}

/// Semantic context supplied by layout, without reading screen pixels.
enum GlassBackdropContext { plain, content, media }

/// Optical treatment is independent of geometry and business state. Content
/// has no material; standard controls scatter light; floating controls lens it.
@immutable
class GlassMaterialSpec {
  const GlassMaterialSpec({
    this.lightTint = .82,
    this.darkTint = .84,
    this.blur = 18,
    this.highlight = .22,
    this.shadow = 0,
    this.refraction = false,
    this.grouped = false,
  }) : assert(lightTint >= 0 && lightTint <= 1),
       assert(darkTint >= 0 && darkTint <= 1),
       assert(blur >= 0),
       assert(highlight >= 0 && highlight <= 1),
       assert(shadow >= 0 && shadow <= 1);

  static const standard = GlassMaterialSpec(grouped: true);
  static const search = GlassMaterialSpec(
    lightTint: .88,
    darkTint: .90,
    blur: 24,
    highlight: .20,
  );
  static const shortcut = GlassMaterialSpec(
    lightTint: 1,
    darkTint: 1,
    blur: 0,
    highlight: 0,
  );
  static const field = GlassMaterialSpec(
    lightTint: .98,
    darkTint: .98,
    blur: 0,
    highlight: .12,
  );
  static const onColor = GlassMaterialSpec(
    lightTint: .18,
    darkTint: .18,
    blur: 12,
    highlight: .30,
  );
  static const stageControl = GlassMaterialSpec(
    lightTint: .72,
    darkTint: .76,
    blur: 24,
    highlight: .18,
  );
  // Native video cannot be sampled. Its small overlay uses the same optical
  // edge and touch light, with no backdrop filter or displacement.
  static const mediaOverlay = GlassMaterialSpec(
    lightTint: .76,
    darkTint: .76,
    blur: 0,
    highlight: .22,
  );
  static const floating = GlassMaterialSpec(
    lightTint: .55,
    darkTint: .55,
    blur: 18,
    highlight: .30,
    shadow: .40,
    refraction: true,
  );
  // A little more diffusion behind song metadata; the navigation stays clearer.
  static const player = GlassMaterialSpec(
    lightTint: .90,
    darkTint: .92,
    blur: 32,
    highlight: .24,
    shadow: .40,
  );
  static const sheet = GlassMaterialSpec(
    lightTint: .98,
    darkTint: .98,
    blur: 18,
    highlight: .12,
    shadow: .70,
  );

  final double lightTint, darkTint, blur, highlight, shadow;
  final bool refraction, grouped;

  GlassMaterialSpec forBackdrop(GlassBackdropContext context) {
    // Zero-blur materials include native video overlays and stable form fields.
    if (context == GlassBackdropContext.plain || blur == 0) return this;
    final content = context == GlassBackdropContext.content;
    final minLight = content ? .90 : .76;
    final minDark = content ? .92 : .80;
    final minBlur = content ? 32.0 : 28.0;
    return GlassMaterialSpec(
      lightTint: lightTint < minLight ? minLight : lightTint,
      darkTint: darkTint < minDark ? minDark : darkTint,
      blur: blur < minBlur ? minBlur : blur,
      highlight: highlight,
      shadow: shadow,
      refraction: refraction,
      grouped: grouped,
    );
  }
}

/// Shared optical values; content surfaces remain quiet and readable.
@immutable
class AppSurfaces extends ThemeExtension<AppSurfaces> {
  const AppSurfaces({
    required this.background,
    required this.group,
    required this.glass,
    required this.rim,
    required this.shadow,
    required this.spotlight,
    required this.onSpotlight,
    required this.spotlightMuted,
  });

  factory AppSurfaces.forBrightness(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return AppSurfaces(
      background: dark ? Colors.black : Colors.white,
      group: dark ? const Color(0xFF2C2C2E) : const Color(0xFFECECEF),
      glass: dark ? const Color(0xFF1C1C1E) : Colors.white,
      rim: Colors.white,
      shadow: Colors.black.withValues(alpha: dark ? .26 : .08),
      spotlight: dark ? const Color(0xFF1C1C1E) : const Color(0xFF26262A),
      onSpotlight: const Color(0xFFFFFFFF),
      spotlightMuted: const Color(0xFFD1D1D6),
    );
  }

  final Color background, group, glass, rim, shadow;
  final Color spotlight, onSpotlight, spotlightMuted;

  static AppSurfaces of(BuildContext context) =>
      Theme.of(context).extension<AppSurfaces>() ??
      AppSurfaces.forBrightness(Theme.of(context).brightness);

  @override
  AppSurfaces copyWith({
    Color? background,
    Color? group,
    Color? glass,
    Color? rim,
    Color? shadow,
    Color? spotlight,
    Color? onSpotlight,
    Color? spotlightMuted,
  }) => AppSurfaces(
    background: background ?? this.background,
    group: group ?? this.group,
    glass: glass ?? this.glass,
    rim: rim ?? this.rim,
    shadow: shadow ?? this.shadow,
    spotlight: spotlight ?? this.spotlight,
    onSpotlight: onSpotlight ?? this.onSpotlight,
    spotlightMuted: spotlightMuted ?? this.spotlightMuted,
  );

  @override
  AppSurfaces lerp(covariant AppSurfaces? other, double t) => other == null
      ? this
      : AppSurfaces(
          background: Color.lerp(background, other.background, t)!,
          group: Color.lerp(group, other.group, t)!,
          glass: Color.lerp(glass, other.glass, t)!,
          rim: Color.lerp(rim, other.rim, t)!,
          shadow: Color.lerp(shadow, other.shadow, t)!,
          spotlight: Color.lerp(spotlight, other.spotlight, t)!,
          onSpotlight: Color.lerp(onSpotlight, other.onSpotlight, t)!,
          spotlightMuted: Color.lerp(spotlightMuted, other.spotlightMuted, t)!,
        );
}
