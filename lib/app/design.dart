import 'package:fluid_glass/fluid_glass.dart' as fg;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import 'icons.dart';
import 'motion.dart';
import 'surfaces.dart';

export 'icons.dart';
export 'motion.dart';
export 'surfaces.dart';

const berry = AppPalette.brand;
const coral = Color(0xFFFF8497);
const recordingControl = AppPalette.recording;
const ink = AppPalette.ink;

ThemeData singVerseTheme(
  Brightness brightness, {
  bool senior = false,
  bool compact = false,
  AppMotionLevel motion = AppMotionLevel.full,
}) {
  final dark = brightness == Brightness.dark;
  final compactText = !senior && compact;
  final surfaces = AppSurfaces.forBrightness(brightness);
  final animated = motion == AppMotionLevel.full;
  final scheme = ColorScheme.fromSeed(seedColor: berry, brightness: brightness)
      .copyWith(
        primary: dark ? const Color(0xFFFF526F) : AppPalette.brandText,
        onPrimary: dark ? ink : Colors.white,
        primaryContainer: dark
            ? const Color(0xFF3E1926)
            : const Color(0xFFFFEDF1),
        onPrimaryContainer: dark
            ? const Color(0xFFFF9FB3)
            : AppPalette.brandText,
        secondary: dark ? const Color(0xFFA2A2AE) : const Color(0xFF585862),
        onSecondary: dark ? const Color(0xFF16161C) : Colors.white,
        tertiary: dark ? AppPalette.coral : AppPalette.brandText,
        onTertiary: dark ? ink : Colors.white,
        tertiaryContainer: dark
            ? const Color(0xFF3E1926)
            : const Color(0xFFFFEDF1),
        onTertiaryContainer: dark
            ? const Color(0xFFFF9FB3)
            : AppPalette.brandText,
        surface: dark ? const Color(0xFF16161C) : Colors.white,
        surfaceDim: dark ? const Color(0xFF101016) : const Color(0xFFE7E9F0),
        surfaceBright: dark ? const Color(0xFF24242E) : Colors.white,
        surfaceContainerLowest: dark ? const Color(0xFF09090D) : Colors.white,
        surfaceContainerLow: dark
            ? const Color(0xFF16161C)
            : const Color(0xFFF8F9FC),
        surfaceContainer: dark
            ? const Color(0xFF1B1B23)
            : const Color(0xFFF0F1F6),
        surfaceContainerHigh: dark
            ? const Color(0xFF23232D)
            : const Color(0xFFE9EBF1),
        surfaceContainerHighest: dark
            ? const Color(0xFF2E2E3A)
            : const Color(0xFFE1E3EB),
        surfaceTint: Colors.transparent,
        onSurface: dark ? AppPalette.inkDark : ink,
        onSurfaceVariant: dark
            ? const Color(0xFFBCBCC8)
            : const Color(0xFF54545E),
        secondaryContainer: surfaces.group,
        onSecondaryContainer: dark ? AppPalette.inkDark : ink,
        outline: dark ? const Color(0xFF565664) : const Color(0xFF8E8E98),
        outlineVariant: dark
            ? const Color(0xFF2E2E3A)
            : const Color(0xFFE2E4EC),
        error: dark ? const Color(0xFFFF5C72) : const Color(0xFFD70015),
        onError: Colors.white,
        inverseSurface: dark ? AppPalette.inkDark : const Color(0xFF23232C),
        onInverseSurface: dark ? ink : Colors.white,
        inversePrimary: dark ? AppPalette.brandText : AppPalette.brandDark,
        shadow: Colors.black,
        scrim: Colors.black,
      );
  final background = surfaces.background;
  final target = senior ? AppSizes.seniorTouch : AppSizes.touch;
  final typography = Typography.material2021();
  final textTheme = (dark ? typography.white : typography.black)
      .merge(
        TextTheme(
          headlineLarge: TextStyle(
            fontSize: 34,
            height: 1.18,
            fontWeight: FontWeight.w700,
            letterSpacing: -.8,
          ),
          headlineSmall: TextStyle(
            fontSize: senior ? 26 : (compactText ? 22 : 24),
            height: 1.24,
            fontWeight: FontWeight.w600,
          ),
          titleLarge: TextStyle(
            fontSize: senior ? 23 : 20,
            height: 1.28,
            fontWeight: FontWeight.w600,
            letterSpacing: -.35,
          ),
          titleMedium: TextStyle(
            fontSize: senior ? 20 : 16,
            height: 1.3,
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: TextStyle(fontSize: senior ? 20 : 16, height: 1.4),
          bodyMedium: TextStyle(fontSize: senior ? 18 : 16, height: 1.45),
          bodySmall: TextStyle(
            fontSize: senior ? 14 : 12,
            height: 1.5,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          labelLarge: TextStyle(
            fontSize: senior ? 17 : 16,
            height: 1.25,
            fontWeight: FontWeight.w600,
          ),
          labelMedium: TextStyle(
            fontSize: senior ? 14 : 13,
            fontWeight: FontWeight.w500,
          ),
          labelSmall: TextStyle(
            fontSize: senior ? 14 : 12,
            height: 1.4,
            fontWeight: FontWeight.w400,
          ),
        ),
      )
      .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    textTheme: textTheme,
    extensions: [surfaces],
    visualDensity: VisualDensity.standard,
    splashFactory: NoSplash.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      systemOverlayStyle: dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      toolbarHeight: senior ? 60 : 48,
      titleSpacing: 20,
      titleTextStyle: textTheme.titleMedium?.copyWith(
        fontSize: senior ? 21 : 17,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surface,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.content),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      space: 1,
      thickness: .5,
    ),
    expansionTileTheme: ExpansionTileThemeData(
      expansionAnimationStyle: AnimationStyle(
        duration: animated ? AppMotion.expand : Duration.zero,
        reverseDuration: animated ? AppMotion.release : Duration.zero,
        curve: animated ? AppMotion.softSpring : Curves.linear,
        reverseCurve: Curves.easeInCubic,
      ),
    ),
    listTileTheme: ListTileThemeData(
      minVerticalPadding: senior ? 16 : 12,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      iconColor: scheme.onSurfaceVariant,
      titleTextStyle: textTheme.titleMedium,
      subtitleTextStyle: textTheme.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.secondaryContainer,
      hintStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      prefixIconColor: scheme.onSurfaceVariant,
      suffixIconColor: scheme.onSurfaceVariant,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.control),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.control),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.control),
        borderSide: BorderSide(color: scheme.primary, width: 1.4),
      ),
      contentPadding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: senior ? 20 : 16,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style:
          FilledButton.styleFrom(
            backgroundColor: scheme.primary,
            foregroundColor: scheme.onPrimary,
            minimumSize: Size(target, target),
            padding: const EdgeInsets.symmetric(horizontal: 22),
            textStyle: textTheme.labelLarge,
            shape: const StadiumBorder(),
          ).copyWith(
            animationDuration: animated ? AppMotion.press : Duration.zero,
            foregroundBuilder: AppMotion.buttonLayer,
          ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style:
          OutlinedButton.styleFrom(
            minimumSize: Size(target, target),
            padding: const EdgeInsets.symmetric(horizontal: 22),
            textStyle: textTheme.labelLarge,
            backgroundColor: scheme.secondaryContainer,
            foregroundColor: scheme.onSurface,
            side: BorderSide.none,
            shape: const StadiumBorder(),
          ).copyWith(
            animationDuration: animated ? AppMotion.press : Duration.zero,
            foregroundBuilder: AppMotion.buttonLayer,
          ),
    ),
    textButtonTheme: TextButtonThemeData(
      style:
          TextButton.styleFrom(
            minimumSize: Size(target, target),
            textStyle: textTheme.labelLarge,
            foregroundColor: scheme.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ).copyWith(
            animationDuration: animated ? AppMotion.press : Duration.zero,
            foregroundBuilder: AppMotion.buttonLayer,
          ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style:
          IconButton.styleFrom(
            minimumSize: Size(target, target),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ).copyWith(
            animationDuration: animated ? AppMotion.press : Duration.zero,
            foregroundBuilder: AppMotion.buttonLayer,
          ),
    ),
    chipTheme: ChipThemeData(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: senior ? 12 : 8),
      labelStyle: textTheme.labelLarge,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      selectedColor: scheme.primaryContainer,
      checkmarkColor: scheme.onPrimaryContainer,
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 3,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: senior ? 9 : 7),
      overlayShape: RoundSliderOverlayShape(overlayRadius: senior ? 20 : 16),
      activeTrackColor: scheme.primary,
      thumbColor: scheme.primary,
      inactiveTrackColor: scheme.outlineVariant,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.outlineVariant,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: !senior,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: textTheme.titleLarge,
      contentTextStyle: textTheme.bodyMedium,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFFF5F5F7) : const Color(0xFF2C2C2E),
      contentTextStyle: textTheme.bodyMedium?.copyWith(
        color: dark ? ink : Colors.white,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: AppPageTransitionsBuilder()},
    ),
  );
}

class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    heightFactor: 1,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: AppSizes.contentWidth),
      child: child,
    ),
  );
}

/// Only the trailing space depends on the shell's changing dock inset.
class SliverBottomSpace extends StatelessWidget {
  const SliverBottomSpace({super.key, this.embedded = true});
  final bool embedded;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: SizedBox(
      height: AppSpace.large + MediaQuery.paddingOf(context).bottom,
    ),
  );
}

/// Stable toolbar material, including camera and WebView containers.
class AppToolbar extends StatelessWidget implements PreferredSizeWidget {
  const AppToolbar({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.bottom,
    this.automaticallyImplyLeading = true,
    this.foregroundColor,
    this.backgroundColor,
  });

  final Widget? title, leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final bool automaticallyImplyLeading;
  final Color? foregroundColor, backgroundColor;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final routeName = ModalRoute.of(context)?.settings.name;
    final nativeRoute = const {'tv', 'scan', 'admin'}.contains(routeName);
    final canPop = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    final effectiveLeading =
        leading ??
        (automaticallyImplyLeading &&
                canPop &&
                backgroundColor == null &&
                !nativeRoute
            ? Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Center(
                  child: SizedBox.square(
                    dimension: 44,
                    child: GlassSurface(
                      radius: 999,
                      material: GlassMaterialSpec.shortcut,
                      child: BackButton(
                        style: IconButton.styleFrom(
                          minimumSize: const Size.square(44),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ),
                ),
              )
            : null);
    final bar = AppBar(
      title: title,
      leading: effectiveLeading,
      leadingWidth: leading == null && effectiveLeading != null ? 60 : null,
      actions: actions,
      bottom: bottom,
      automaticallyImplyLeading: automaticallyImplyLeading,
      foregroundColor: foregroundColor,
      backgroundColor: backgroundColor ?? Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: backgroundColor == null
          ? null
          : ThemeData.estimateBrightnessForColor(backgroundColor!) ==
                Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      flexibleSpace: backgroundColor == null
          ? null
          : ColoredBox(color: backgroundColor!),
    );
    if (backgroundColor != null || nativeRoute) return bar;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Positioned(
          left: 0,
          right: 0,
          top: 0,
          bottom: -22,
          child: IgnorePointer(child: _ToolbarBackground()),
        ),
        bar,
      ],
    );
  }
}

class _ToolbarBackground extends StatefulWidget {
  const _ToolbarBackground();

  @override
  State<_ToolbarBackground> createState() => _ToolbarBackgroundState();
}

class _ToolbarBackgroundState extends State<_ToolbarBackground> {
  ScrollNotificationObserverState? _observer;
  double _scrollOffset = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = ScrollNotificationObserver.maybeOf(context);
    if (!identical(_observer, next)) {
      _observer?.removeListener(_onScrollNotification);
      _observer = next;
      _observer?.addListener(_onScrollNotification);
    }
  }

  @override
  void dispose() {
    _observer?.removeListener(_onScrollNotification);
    super.dispose();
  }

  void _onScrollNotification(ScrollNotification notification) {
    if (!mounted ||
        notification.depth != 0 ||
        notification.metrics.axis != Axis.vertical) {
      return;
    }
    final next = notification.metrics.pixels.clamp(0.0, 48.0);
    if ((next - _scrollOffset).abs() < 0.5 &&
        !(next == 0 && _scrollOffset > 0)) {
      return;
    }
    setState(() => _scrollOffset = next);
  }

  @override
  Widget build(BuildContext context) {
    final amount = (_scrollOffset / 32).clamp(0.0, 1.0);
    if (amount <= 0) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = Theme.of(context).scaffoldBackgroundColor;
    final solid = AppMotionScope.solidOf(context);
    final tint = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0.0, 0.30, 0.54, 0.72, 0.85, 0.94, 1.0],
          colors: [
            color.withValues(alpha: (dark ? .88 : .88) * amount),
            color.withValues(alpha: (dark ? .76 : .74) * amount),
            color.withValues(alpha: (dark ? .52 : .48) * amount),
            color.withValues(alpha: (dark ? .26 : .22) * amount),
            color.withValues(alpha: (dark ? .09 : .07) * amount),
            color.withValues(alpha: (dark ? .02 : .015) * amount),
            color.withValues(alpha: 0),
          ],
        ),
      ),
    );
    if (solid) return tint;
    return fg.ProgressiveBlur(
      maxBlurRadius: 16 * amount,
      direction: fg.ProgressiveBlurDirection.blurredTopClearBottom,
      startOffset: 0.44,
      bands: 6,
      child: tint,
    );
  }
}

/// Shared two-layer Liquid Glass scaffold wrapper (`envBackdrop` for in-scroll
/// cards/inputs and `contentBackdrop` for floating toolbars, MiniPlayer, and
/// modal sheets) so pages never suffer from BackdropLayer self-recursion.
class AppBackdropPage extends StatelessWidget {
  const AppBackdropPage({
    super.key,
    required this.body,
    this.appBar,
    this.glow,
    this.ambient,
    this.bottomNavigationBar,
    this.extendBody = false,
    this.extendBodyBehindAppBar = true,
    this.solid = false,
  });

  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? glow, ambient, bottomNavigationBar;
  final bool extendBody, extendBodyBehindAppBar, solid;

  @override
  Widget build(BuildContext context) => AppBackdropCapture(
    solid: solid,
    builder: (context, envBackdrop) => AppBackdropCapture(
      solid: solid,
      builder: (context, contentBackdrop) => AppBackdropRouteBinding(
        environment: envBackdrop,
        content: contentBackdrop,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: extendBody,
          extendBodyBehindAppBar: extendBodyBehindAppBar,
          appBar: appBar == null
              ? null
              : PreferredSize(
                  preferredSize: appBar!.preferredSize,
                  child: AppBackdropScope(
                    environment: envBackdrop,
                    content: contentBackdrop,
                    child: appBar!,
                  ),
                ),
          body: AppBackdropSource(
            backdrop: contentBackdrop,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: AppBackdropSource(
                    backdrop: envBackdrop,
                    child: AppEnvironment(
                      solid: solid,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [?glow, ?ambient],
                      ),
                    ),
                  ),
                ),
                AppBackdropScope(
                  environment: envBackdrop,
                  content: contentBackdrop,
                  child: body,
                ),
              ],
            ),
          ),
          bottomNavigationBar: bottomNavigationBar == null
              ? null
              : AppBackdropScope(
                  environment: envBackdrop,
                  content: contentBackdrop,
                  child: bottomNavigationBar!,
                ),
        ),
      ),
    ),
  );
}

class AppSegments<T> extends StatelessWidget {
  const AppSegments({
    super.key,
    required this.values,
    required this.selected,
    required this.onChanged,
    this.senior = false,
    this.compact = false,
    this.enabled = true,
    this.disabled = const {},
    this.keyFor,
    this.labelBuilder,
    this.textStyle,
    this.glass = false,
    this.accent = false,
    this.liquid = false,
    this.plain = false,
    this.material,
    this.selectedColor,
    this.trackColor,
  });
  final List<(T, String)> values;
  final T selected;
  final ValueChanged<T> onChanged;
  final bool senior, compact, enabled, glass, accent, liquid, plain;
  final Set<T> disabled;
  final Key Function(T)? keyFor;
  final Widget Function(T, String)? labelBuilder;
  final TextStyle? textStyle;
  final GlassMaterialSpec? material;
  final Color? selectedColor, trackColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (plain) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < values.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  '/',
                  style: textStyle?.copyWith(
                    fontWeight: FontWeight.w400,
                    color: scheme.onSurfaceVariant.withValues(alpha: .35),
                  ),
                ),
              ),
            MergeSemantics(
              child: Semantics(
                selected: values[i].$1 == selected,
                button: true,
                child: InkWell(
                  key: keyFor?.call(values[i].$1),
                  borderRadius: BorderRadius.circular(8),
                  onTap: enabled && !disabled.contains(values[i].$1)
                      ? () => onChanged(values[i].$1)
                      : null,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: senior ? 8 : 6,
                      vertical: senior ? 6 : 4,
                    ),
                    child:
                        labelBuilder?.call(values[i].$1, values[i].$2) ??
                        Text(
                          values[i].$2,
                          style: textStyle?.copyWith(
                            fontWeight: values[i].$1 == selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: values[i].$1 == selected
                                ? scheme.primary
                                : scheme.onSurfaceVariant.withValues(
                                    alpha: .60,
                                  ),
                          ),
                        ),
                  ),
                ),
              ),
            ),
          ],
        ],
      );
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    final solid = AppMotionScope.solidOf(context);
    final index = values.indexWhere((value) => value.$1 == selected);
    final pillRadius = BorderRadius.circular(999);
    final thumbColor = accent
        ? scheme.primary
        : glass && !solid
        ? Colors.white.withValues(alpha: dark ? .20 : .86)
        : dark
        ? const Color(0xFF2E2E3A)
        : Colors.white;
    final content = Padding(
      padding: EdgeInsets.all(compact && !senior ? 3 : 4),
      child: Stack(
        children: [
          if (index >= 0)
            Positioned.fill(
              child: AnimatedAlign(
                duration: AppMotionScope.levelOf(context) == AppMotionLevel.full
                    ? AppMotion.navigation
                    : Duration.zero,
                curve: AppMotionScope.levelOf(context) == AppMotionLevel.full
                    ? AppMotion.bouncySpring
                    : Curves.linear,
                alignment: Alignment(
                  values.length < 2 ? 0 : 2 * index / (values.length - 1) - 1,
                  0,
                ),
                child: FractionallySizedBox(
                  widthFactor: 1 / values.length,
                  heightFactor: 1,
                  child: accent || !(glass || liquid)
                      ? DecoratedBox(
                          decoration: BoxDecoration(
                            color: thumbColor,
                            borderRadius: pillRadius,
                            boxShadow: [
                              if (!solid)
                                BoxShadow(
                                  color: Colors.black.withValues(
                                    alpha: dark ? .18 : .10,
                                  ),
                                  blurRadius: compact ? 5 : 10,
                                  offset: Offset(0, compact ? 1.5 : 2.5),
                                ),
                            ],
                          ),
                        )
                      : LiquidDropletBox(
                          radius: 999,
                          solid: solid,
                          compact: compact,
                        ),
                ),
              ),
            ),
          Row(
            children: [
              for (final value in values)
                Expanded(
                  child: MergeSemantics(
                    child: Semantics(
                      selected: value.$1 == selected,
                      child: TextButton(
                        key: keyFor?.call(value.$1),
                        style: TextButton.styleFrom(
                          textStyle: textStyle,
                          shape: const StadiumBorder(),
                          tapTargetSize: compact && !senior
                              ? MaterialTapTargetSize.shrinkWrap
                              : MaterialTapTargetSize.padded,
                          minimumSize: Size(
                            AppSizes.touch,
                            senior
                                ? AppSizes.seniorTouch
                                : compact
                                ? 28
                                : AppSizes.touch,
                          ),
                          padding: EdgeInsets.symmetric(
                            horizontal: compact && !senior ? 6 : 8,
                            vertical: senior
                                ? 12
                                : compact
                                ? 4
                                : 8,
                          ),
                          foregroundColor: value.$1 == selected
                              ? (selectedColor ??
                                    (accent
                                        ? scheme.onPrimary
                                        : liquid
                                        ? scheme.primary
                                        : scheme.onSurface))
                              : scheme.onSurfaceVariant,
                        ),
                        onPressed: enabled && !disabled.contains(value.$1)
                            ? () => onChanged(value.$1)
                            : null,
                        child:
                            labelBuilder?.call(value.$1, value.$2) ??
                            Text(value.$2, textAlign: TextAlign.center),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
    if (liquid) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color:
              trackColor ??
              (solid
                  ? scheme.secondaryContainer
                  : scheme.onSurface.withValues(alpha: dark ? .10 : .055)),
          borderRadius: pillRadius,
        ),
        child: content,
      );
    }
    return glass
        ? GlassSurface(
            radius: 26,
            material: material,
            enabled: enabled,
            child: content,
          )
        : DecoratedBox(
            decoration: BoxDecoration(
              color: compact && !solid
                  ? scheme.onSurface.withValues(alpha: dark ? .10 : .055)
                  : scheme.secondaryContainer,
              borderRadius: pillRadius,
            ),
            child: content,
          );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Semantics(
          header: true,
          child: Text(text, style: Theme.of(context).textTheme.titleLarge),
        ),
      ),
      ?trailing,
    ],
  );
}

class SheetHeader extends StatelessWidget {
  const SheetHeader(this.title, {super.key, this.done = '完成', this.trailing});
  final String title, done;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Row(
      children: [
        Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
        if (trailing != null) ...[trailing!, const SizedBox(width: 6)],
        SizedBox(
          width: 44,
          height: 44,
          child: IconButton(
            tooltip: done,
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.pop(context),
            icon: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.onSurface.withValues(
                      alpha: dark ? .18 : .09,
                    ),
                    theme.colorScheme.onSurface.withValues(
                      alpha: dark ? .08 : .04,
                    ),
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: dark ? .20 : .65),
                  width: .7,
                ),
              ),
              child: Icon(
                Icons.close_rounded,
                size: 19,
                color: theme.colorScheme.onSurface.withValues(alpha: .88),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.state,
    required this.child,
    this.radius = AppRadii.control,
    this.variant = GlassVariant.regular,
    this.focused = false,
    this.material,
    this.tint,
    this.enabled = true,
    this.backdropContext = GlassBackdropContext.plain,
  });
  final AppState state;
  final Widget child;
  final double radius;
  final GlassVariant variant;
  final bool focused;
  final bool enabled;
  final GlassMaterialSpec? material;
  final Color? tint;
  final GlassBackdropContext backdropContext;
  @override
  Widget build(BuildContext context) {
    final solid =
        state.reduceTransparency ||
        state.senior ||
        state.performanceMode ||
        MediaQuery.highContrastOf(context);
    return GlassSurface(
      radius: radius,
      solid: solid,
      variant: variant,
      focused: focused,
      material: material,
      tint: tint,
      enabled: enabled,
      backdropContext: backdropContext,
      child: child,
    );
  }
}

/// Descendant focus is observed without changing TextField controllers,
/// traversal, autofill, validation, or the field's own keyboard behavior.
class GlassField extends StatefulWidget {
  const GlassField({
    super.key,
    required this.state,
    required this.child,
    this.enabled = true,
    this.radius = AppRadii.control,
    this.material,
    this.focusNode,
    this.backdropContext = GlassBackdropContext.plain,
  });
  final AppState state;
  final Widget child;
  final bool enabled;
  final double radius;
  final GlassMaterialSpec? material;
  final FocusNode? focusNode;
  final GlassBackdropContext backdropContext;
  @override
  State<GlassField> createState() => _GlassFieldState();
}

class _GlassFieldState extends State<GlassField> {
  bool focused = false;
  @override
  Widget build(BuildContext context) {
    if (widget.focusNode != null) {
      return ListenableBuilder(
        listenable: widget.focusNode!,
        builder: (context, _) => Glass(
          state: widget.state,
          radius: widget.radius,
          variant: GlassVariant.field,
          material: widget.material,
          focused: widget.focusNode!.hasFocus && widget.enabled,
          enabled: widget.enabled,
          backdropContext: widget.backdropContext,
          child: widget.child,
        ),
      );
    }
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (value) => setState(() => focused = value),
      child: Glass(
        state: widget.state,
        radius: widget.radius,
        variant: GlassVariant.field,
        material: widget.material,
        focused: focused && widget.enabled,
        enabled: widget.enabled,
        backdropContext: widget.backdropContext,
        child: widget.child,
      ),
    );
  }
}

/// A shared functional layer; the content underneath stays unfiltered.
class GlassToolbar extends StatelessWidget {
  const GlassToolbar({
    super.key,
    required this.state,
    required this.children,
    this.backdropContext = GlassBackdropContext.plain,
  });
  final AppState state;
  final List<Widget> children;
  final GlassBackdropContext backdropContext;

  @override
  Widget build(BuildContext context) => Glass(
    state: state,
    radius: 999,
    variant: GlassVariant.liquid,
    backdropContext: backdropContext,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    ),
  );
}

/// The same focus lighting as NAS inputs, without changing search timing,
/// editing state or focus ownership.
class GlassSearchField extends StatelessWidget {
  const GlassSearchField({
    super.key,
    required this.state,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    this.suffix,
    this.fieldKey,
    this.hintText = '搜索歌名、歌手或拼音',
    this.backdropContext = GlassBackdropContext.content,
  });
  final AppState state;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged, onSubmitted;
  final Widget? suffix;
  final Key? fieldKey;
  final String hintText;
  final GlassBackdropContext backdropContext;

  @override
  Widget build(BuildContext context) => GlassField(
    state: state,
    radius: 999,
    material: GlassMaterialSpec.search,
    focusNode: focusNode,
    backdropContext: backdropContext,
    child: TextField(
      key: fieldKey,
      controller: controller,
      focusNode: focusNode,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(fontSize: state.senior ? 18 : 16, height: 1.25),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(
          fontSize: state.senior ? 18 : 16,
          height: 1.25,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        prefixIconColor: Theme.of(context).colorScheme.onSurfaceVariant,
        prefixIcon: Center(
          widthFactor: 1,
          child: AppVectorIcon(
            AppGlyph.search,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: AppSizes.touch,
          minHeight: AppSizes.touch,
        ),
        suffixIconConstraints: const BoxConstraints(
          minWidth: AppSizes.touch,
          minHeight: AppSizes.touch,
        ),
        suffixIcon: suffix,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        constraints: BoxConstraints(
          minHeight: state.senior ? AppSizes.seniorTouch : 48,
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppSpace.sm,
          vertical: state.senior ? 15 : 13,
        ),
      ),
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    ),
  );
}

Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useSafeArea = false,
}) {
  // Native camera and WebView layers cannot be sampled reliably. On the
  // singing stage ('player'), only sample its environment backdrop (never any
  // AndroidView video layer).
  final routeName = ModalRoute.of(context)?.settings.name;
  final nativeRoute = const {'tv', 'scan', 'admin'}.contains(routeName);
  final playerRoute = routeName == 'player';
  final resolved = nativeRoute
      ? (environment: null, content: null)
      : AppBackdropScope.resolveForSheet(context);
  final sheetBackdrop = playerRoute
      ? resolved.environment
      : (resolved.content ?? resolved.environment);
  final avoidBackdrop = nativeRoute || (playerRoute && sheetBackdrop == null);
  final full = AppMotionScope.levelOf(context) == AppMotionLevel.full;
  final controller = AnimationController(
    vsync: Navigator.of(context),
    duration: full ? AppMotion.sheet : Duration.zero,
    reverseDuration: full ? AppMotion.release : Duration.zero,
  );
  final navigator = Navigator.of(context);
  final localizations = MaterialLocalizations.of(context);
  final dark = Theme.of(context).brightness == Brightness.dark;
  final route = ModalBottomSheetRoute<T>(
    capturedThemes: InheritedTheme.capture(
      from: context,
      to: navigator.context,
    ),
    barrierLabel: localizations.scrimLabel,
    barrierOnTapHint: localizations.scrimOnTapHint(
      localizations.bottomSheetLabel,
    ),
    modalBarrierColor: avoidBackdrop
        ? Colors.black.withValues(alpha: dark ? .64 : .36)
        : Colors.black.withValues(alpha: dark ? .52 : .22),
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    transitionAnimationController: controller,
    sheetAnimationStyle: AppMotion.modalStyle(context),
    builder: (context) {
      final sheet = SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: GlassSurface(
            radius: 32,
            variant: GlassVariant.sheet,
            material: avoidBackdrop
                ? GlassMaterialSpec.sheetNative
                : GlassMaterialSpec.sheet,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 64,
                  height: AppSizes.touch,
                  child: TextButton(
                    onPressed: () => Navigator.maybePop(context),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(AppSizes.touch, AppSizes.touch),
                    ),
                    child: Semantics(
                      label: '关闭面板',
                      child: Container(
                        width: 36,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.onSurfaceVariant
                              .withValues(alpha: .55),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
                Flexible(child: builder(context)),
              ],
            ),
          ),
        ),
      );
      return _SheetMotionGate(
        controller: controller,
        child: avoidBackdrop
            ? sheet
            : AppBackdropRouteBinding(
                environment: resolved.environment,
                content: sheetBackdrop,
                child: AppBackdropScope(
                  environment: resolved.environment,
                  content: sheetBackdrop,
                  child: sheet,
                ),
              ),
      );
    },
  );
  // A pop result arrives before the reverse animation has left the overlay.
  // Keep its controller alive until the route itself has finished disposal.
  final result = navigator.push(route);
  route.completed.whenComplete(controller.dispose);
  return result;
}

/// A running sheet settles immediately when the user disables motion.
class _SheetMotionGate extends StatefulWidget {
  const _SheetMotionGate({required this.controller, required this.child});
  final AnimationController controller;
  final Widget child;
  @override
  State<_SheetMotionGate> createState() => _SheetMotionGateState();
}

class _SheetMotionGateState extends State<_SheetMotionGate> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotionScope.levelOf(context) != AppMotionLevel.full) {
      widget.controller.duration = Duration.zero;
      widget.controller.reverseDuration = Duration.zero;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !widget.controller.isAnimating) return;
        widget.controller.value =
            widget.controller.status == AnimationStatus.reverse ? 0 : 1;
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final themes = InheritedTheme.capture(
    from: context,
    to: Navigator.of(context, rootNavigator: true).context,
  );
  return Navigator.of(context, rootNavigator: true).push(
    _AppDialogRoute<T>(
      initialMotion: AppMotionScope.levelOf(context),
      barrierDismissible: barrierDismissible,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black54,
      transitionDuration: AppMotionScope.durationOf(context, AppMotion.sheet),
      pageBuilder: (context, _, _) =>
          themes.wrap(SafeArea(child: Builder(builder: builder))),
      transitionBuilder: (context, animation, _, child) {
        final level = AppMotionScope.levelOf(context);
        if (level == AppMotionLevel.none) return child;
        final fade = FadeTransition(opacity: animation, child: child);
        if (level == AppMotionLevel.reduced) return fade;
        return ScaleTransition(
          scale: animation.drive(
            Tween(
              begin: .96,
              end: 1.0,
            ).chain(CurveTween(curve: AppMotion.spring)),
          ),
          child: fade,
        );
      },
    ),
  );
}

/// Also settle the route barrier when the motion policy changes mid-flight.
class _AppDialogRoute<T> extends RawDialogRoute<T> {
  _AppDialogRoute({
    required this.initialMotion,
    required super.pageBuilder,
    required super.barrierDismissible,
    required super.barrierLabel,
    required super.barrierColor,
    required super.transitionDuration,
    required super.transitionBuilder,
  });
  final AppMotionLevel initialMotion;
  AppMotionLevel? previousMotion;

  @override
  Duration get reverseTransitionDuration => switch (initialMotion) {
    AppMotionLevel.full => AppMotion.release,
    AppMotionLevel.reduced => const Duration(milliseconds: 100),
    AppMotionLevel.none => Duration.zero,
  };

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final motion = AppMotionScope.levelOf(context);
    if (previousMotion != motion) {
      previousMotion = motion;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (navigator == null) return;
        final current = controller;
        if (current == null) return;
        current.duration = switch (motion) {
          AppMotionLevel.full => AppMotion.sheet,
          AppMotionLevel.reduced => const Duration(milliseconds: 100),
          AppMotionLevel.none => Duration.zero,
        };
        current.reverseDuration = switch (motion) {
          AppMotionLevel.full => AppMotion.release,
          AppMotionLevel.reduced => const Duration(milliseconds: 100),
          AppMotionLevel.none => Duration.zero,
        };
        if (motion != AppMotionLevel.full && current.isAnimating) {
          current.value = current.status == AnimationStatus.reverse ? 0 : 1;
        }
      });
    }
    return super.buildTransitions(
      context,
      animation,
      secondaryAnimation,
      child,
    );
  }
}

Future<void> uiTask(BuildContext context, Future<void> Function() task) async {
  try {
    await task();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is PlatformException
                ? e.message ?? '操作未完成，请重试。'
                : e is FormatException
                ? e.message
                : e.toString(),
          ),
        ),
      );
    }
  }
}

class Notice extends StatelessWidget {
  const Notice(this.text, {super.key, this.action, this.label = '重试'});
  final String text, label;
  final VoidCallback? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.music_note_rounded,
          size: 30,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 12),
        Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        if (action != null) ...[
          const SizedBox(height: 8),
          TextButton(onPressed: action, child: Text(label)),
        ],
      ],
    ),
  );
}

class PageTracker extends NavigatorObserver {
  final current = ValueNotifier<String>('/');
  final modalOpen = ValueNotifier<bool>(false);
  final popups = <Route<dynamic>>[];
  void popup(Route<dynamic> route, bool open) {
    if (route is! PopupRoute) return;
    open ? popups.add(route) : popups.remove(route);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      modalOpen.value = popups.isNotEmpty;
    });
  }

  void update(Route<dynamic>? route) {
    if (route is! PageRoute) return;
    final name = route.settings.name ?? 'page';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      current.value = name;
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popup(route, true);
    update(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popup(route, false);
    update(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      update(newRoute);
}
