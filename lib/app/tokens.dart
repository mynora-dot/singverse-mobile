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

  // Luminous atmospheric mesh tints (Apple iOS 26 depth behind Liquid Glass).
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
    this.lightTint = .62,
    this.darkTint = .60,
    this.blur = 20,
    this.highlight = .72,
    this.shadow = .32,
    this.refraction = false,
    this.sampleContent = true,
    this.grouped = false,
    this.lensHeight,
    this.lensAmount,
  }) : assert(lightTint >= 0 && lightTint <= 1),
       assert(darkTint >= 0 && darkTint <= 1),
       assert(blur >= 0),
       assert(highlight >= 0 && highlight <= 1),
       assert(shadow >= 0 && shadow <= 1);

  static const standard = GlassMaterialSpec(
    lightTint: .76,
    darkTint: .46,
    blur: 12,
    highlight: .88,
    shadow: .24,
    refraction: true,
    sampleContent: false,
    grouped: true,
    lensHeight: 12,
    lensAmount: 18,
  );
  static const search = GlassMaterialSpec(
    lightTint: .72,
    darkTint: .38,
    blur: 10,
    highlight: .90,
    shadow: .30,
    refraction: true,
  );
  static const shortcut = GlassMaterialSpec(
    lightTint: .74,
    darkTint: .44,
    blur: 10,
    highlight: .58,
    shadow: .24,
    refraction: true,
    sampleContent: false,
    lensHeight: 12,
    lensAmount: 22,
  );
  static const field = GlassMaterialSpec(
    lightTint: .76,
    darkTint: .50,
    blur: 12,
    highlight: .80,
    shadow: .14,
    refraction: true,
    sampleContent: false,
    lensHeight: 10,
    lensAmount: 16,
  );
  static const onColor = GlassMaterialSpec(
    lightTint: .16,
    darkTint: .20,
    blur: 10,
    highlight: .88,
    shadow: .22,
    refraction: true,
  );
  static const stageControl = GlassMaterialSpec(
    lightTint: .44,
    darkTint: .52,
    blur: 16,
    highlight: .46,
    shadow: .38,
    refraction: true,
    lensHeight: 12,
    lensAmount: 20,
  );
  // Native video cannot be sampled. Its small overlay uses the same optical
  // edge and touch light, with no backdrop filter or displacement.
  static const mediaOverlay = GlassMaterialSpec(
    lightTint: .72,
    darkTint: .72,
    blur: 0,
    highlight: .55,
  );
  static const floating = GlassMaterialSpec(
    lightTint: .68,
    darkTint: .34,
    blur: 10,
    highlight: .94,
    shadow: .56,
    refraction: true,
  );
  // Floating player capsule with luminous specular edge and soft color wash.
  static const player = GlassMaterialSpec(
    lightTint: .72,
    darkTint: .36,
    blur: 12,
    highlight: .96,
    shadow: .60,
    refraction: true,
  );
  static const sheet = GlassMaterialSpec(
    lightTint: .78,
    darkTint: .66,
    blur: 24,
    highlight: .54,
    shadow: .76,
    refraction: true,
    lensHeight: 18,
    lensAmount: 28,
  );
  // Unified zero-blur smoked Liquid Glass for sheets over native routes
  // (TV, scan, admin): high opacity eliminates sharp background ghosting
  // while floating inset geometry and crisp Fresnel rim preserve the look.
  static const sheetNative = GlassMaterialSpec(
    lightTint: .94,
    darkTint: .94,
    blur: 0,
    highlight: .65,
    shadow: .80,
  );

  final double lightTint, darkTint, blur, highlight, shadow;
  final bool refraction, sampleContent, grouped;
  final double? lensHeight, lensAmount;

  GlassMaterialSpec forBackdrop(GlassBackdropContext context) {
    // Zero-blur materials include native video overlays and stable form fields.
    if (context == GlassBackdropContext.plain || blur == 0) return this;
    final content = context == GlassBackdropContext.content;
    final minLight = content ? .42 : .38;
    final minDark = content ? .36 : .30;
    final minBlur = content ? 10.0 : 9.0;
    return GlassMaterialSpec(
      lightTint: lightTint < minLight ? minLight : lightTint,
      darkTint: darkTint < minDark ? minDark : darkTint,
      blur: blur < minBlur ? minBlur : blur,
      highlight: highlight,
      shadow: shadow,
      refraction: refraction,
      sampleContent: sampleContent,
      grouped: grouped,
      lensHeight: lensHeight,
      lensAmount: lensAmount,
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
      background: dark ? const Color(0xFF0C0C0F) : const Color(0xFFF7F8FB),
      group: dark ? const Color(0xFF1C1C23) : const Color(0xFFEEEFF5),
      glass: dark ? const Color(0xFF1B1B22) : Colors.white,
      rim: Colors.white,
      shadow: Colors.black.withValues(alpha: dark ? .46 : .12),
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
