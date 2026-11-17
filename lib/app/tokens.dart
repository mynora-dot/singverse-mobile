import 'package:flutter/material.dart';

abstract final class AppPalette {
  static const brand = Color(0xFF2463DE);
  static const recording = Color(0xFFC92547);
  static const ink = Color(0xFF181D26);
  static const lightEnvironmentBlue = Color(0xFFC4D8F4);
  static const darkEnvironmentBlue = Color(0xFF244777);
  static const lightEnvironmentViolet = Color(0xFFDEDDF1);
  static const darkEnvironmentViolet = Color(0xFF302D54);
}

/// Geometry shared by content, standard controls and floating glass.
abstract final class AppSpace {
  static const double xxs = 4, xs = 8, sm = 12, md = 16;
  static const double page = 24, section = 28, large = 32;
}

abstract final class AppRadii {
  static const double artwork = 12, control = 18, content = 24, floating = 28;
}

abstract final class AppSizes {
  static const double touch = 48, seniorTouch = 56, field = 60;
  static const double songArtwork = 52, contentWidth = 720;
}

/// Optical treatment is independent of geometry and business state. Content
/// has no material; standard controls scatter light; floating controls lens it.
@immutable
class GlassMaterialSpec {
  const GlassMaterialSpec({
    this.lightTint = .44,
    this.darkTint = .78,
    this.blur = 6,
    this.highlight = 1,
    this.shadow = 0,
    this.refraction = false,
    this.grouped = false,
  }) : assert(lightTint >= 0 && lightTint <= 1),
       assert(darkTint >= 0 && darkTint <= 1),
       assert(blur >= 0),
       assert(highlight >= 0 && highlight <= 1),
       assert(shadow >= 0 && shadow <= 1);

  static const standard = GlassMaterialSpec(grouped: true);
  static const field = GlassMaterialSpec(
    lightTint: .40,
    darkTint: .80,
    grouped: true,
  );
  static const onColor = GlassMaterialSpec(
    lightTint: .03,
    darkTint: .03,
    blur: 4,
    highlight: .65,
  );
  static const floating = GlassMaterialSpec(
    lightTint: .58,
    darkTint: .84,
    blur: 10,
    shadow: 1,
    refraction: true,
  );
  static const sheet = GlassMaterialSpec(
    lightTint: .76,
    darkTint: .91,
    blur: 12,
    shadow: 1,
    refraction: true,
  );

  final double lightTint, darkTint, blur, highlight, shadow;
  final bool refraction, grouped;
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
      background: dark ? const Color(0xFF0D1119) : const Color(0xFFF6F7F9),
      group: dark ? const Color(0xFF222935) : const Color(0xFFEBEEF3),
      glass: dark ? const Color(0xFF202630) : const Color(0xFFFDFEFF),
      rim: dark ? const Color(0xFFBCCBDD) : Colors.white,
      shadow: Colors.black.withValues(alpha: dark ? .24 : .07),
      spotlight: dark ? const Color(0xFF162D50) : const Color(0xFF203F68),
      onSpotlight: const Color(0xFFFFFFFF),
      spotlightMuted: const Color(0xFFD1DFF2),
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
