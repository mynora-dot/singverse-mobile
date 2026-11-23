import 'package:flutter/material.dart';

abstract final class AppPalette {
  static const brand = Color(0xFFFA2D55);
  static const brandDark = Color(0xFFFF375F);
  static const brandDeep = Color(0xFFD8103C);
  static const brandText = Color(0xFFD8103C);
  static const coral = Color(0xFFFF6B4A);
  static const recording = Color(0xFFD8103C);
  static const ink = Color(0xFF111114);
  static const inkDark = Color(0xFFF5F5F7);

  // Subtle atmospheric mesh tints (Apple iOS 26 luminous backdrop depth).
  static const lightEnvironmentBlue = Color(0xFFC8DDFC);
  static const darkEnvironmentBlue = Color(0xFF243B6E);
  static const lightEnvironmentViolet = Color(0xFFFA2D55);
  static const darkEnvironmentViolet = Color(0xFF8C1D3A);
  static const lightEnvironmentWarm = Color(0xFFFFC5A8);
  static const darkEnvironmentWarm = Color(0xFF4A2574);

  // Deep atmospheric stage for practice & recording.
  static const stage = Color(0xFF101016);
  static const stageSurface = Color(0xFF1C1C24);
  static const stageAccent = Color(0xFFFF4D72);
  static const stageOnAccent = Colors.white;
  static const stageText = Color(0xFFF5F5F7);
  static const stageMuted = Color(0xFFA4A4B0);
  static const stageTrack = Color(0xFF34343E);
}

/// Geometry shared by content, standard controls and floating glass.
abstract final class AppSpace {
  static const double xxs = 4, xs = 8, sm = 12, md = 16;
  static const double page = 20, section = 24, large = 32;
}

abstract final class AppRadii {
  static const double artwork = 12, control = 18, content = 22, floating = 28;
  static const double featured = 26, pill = 999;
}

abstract final class AppSizes {
  static const double touch = 44, seniorTouch = 56, field = 52;
  static const double songArtwork = 50, contentWidth = 720;
}

/// Semantic context supplied by layout, without reading screen pixels.
enum GlassBackdropContext { plain, content, media }

/// Optical treatment is independent of geometry and business state. Content
/// has no material; standard controls scatter light; floating controls lens it.
@immutable
class GlassMaterialSpec {
  const GlassMaterialSpec({
    this.lightTint = .72,
    this.darkTint = .74,
    this.blur = 20,
    this.highlight = .52,
    this.shadow = .22,
    this.refraction = false,
    this.grouped = false,
  }) : assert(lightTint >= 0 && lightTint <= 1),
       assert(darkTint >= 0 && darkTint <= 1),
       assert(blur >= 0),
       assert(highlight >= 0 && highlight <= 1),
       assert(shadow >= 0 && shadow <= 1);

  static const standard = GlassMaterialSpec(grouped: true);
  static const search = GlassMaterialSpec(
    lightTint: .74,
    darkTint: .70,
    blur: 24,
    highlight: .58,
    shadow: .26,
  );
  static const shortcut = GlassMaterialSpec(
    lightTint: .72,
    darkTint: .64,
    blur: 18,
    highlight: .48,
    shadow: .18,
    grouped: true,
  );
  static const field = GlassMaterialSpec(
    lightTint: .90,
    darkTint: .86,
    blur: 0,
    highlight: .35,
    shadow: .10,
  );
  static const onColor = GlassMaterialSpec(
    lightTint: .22,
    darkTint: .22,
    blur: 16,
    highlight: .55,
  );
  static const stageControl = GlassMaterialSpec(
    lightTint: .16,
    darkTint: .16,
    blur: 24,
    highlight: .42,
    shadow: .24,
  );
  // Native video cannot be sampled. Its small overlay uses the same optical
  // edge and touch light, with no backdrop filter or displacement.
  static const mediaOverlay = GlassMaterialSpec(
    lightTint: .72,
    darkTint: .72,
    blur: 0,
    highlight: .36,
  );
  static const floating = GlassMaterialSpec(
    lightTint: .60,
    darkTint: .58,
    blur: 24,
    highlight: .72,
    shadow: .52,
    refraction: true,
  );
  // Floating player capsule with luminous specular edge and soft diffusion.
  static const player = GlassMaterialSpec(
    lightTint: .76,
    darkTint: .72,
    blur: 28,
    highlight: .68,
    shadow: .54,
    refraction: true,
  );
  static const sheet = GlassMaterialSpec(
    lightTint: .92,
    darkTint: .90,
    blur: 28,
    highlight: .42,
    shadow: .72,
  );

  final double lightTint, darkTint, blur, highlight, shadow;
  final bool refraction, grouped;

  GlassMaterialSpec forBackdrop(GlassBackdropContext context) {
    // Zero-blur materials include native video overlays and stable form fields.
    if (context == GlassBackdropContext.plain || blur == 0) return this;
    final content = context == GlassBackdropContext.content;
    final minLight = content ? .78 : .70;
    final minDark = content ? .74 : .68;
    final minBlur = content ? 28.0 : 24.0;
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
      background: dark ? const Color(0xFF09090D) : const Color(0xFFF3F4F8),
      group: dark ? const Color(0xFF1F1F27) : const Color(0xFFE9EBF1),
      glass: dark ? const Color(0xFF22222B) : Colors.white,
      rim: Colors.white,
      shadow: Colors.black.withValues(alpha: dark ? .42 : .10),
      spotlight: dark ? const Color(0xFF1D1B2A) : const Color(0xFF1F1D2C),
      onSpotlight: const Color(0xFFFFFFFF),
      spotlightMuted: const Color(0xFFD6D6DE),
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
