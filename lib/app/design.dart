import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import 'motion.dart';
import 'surfaces.dart';

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
            ? const Color(0xFF3C1E28)
            : const Color(0xFFFFF0F3),
        onPrimaryContainer: dark
            ? const Color(0xFFFF9AAE)
            : AppPalette.brandText,
        secondary: dark ? const Color(0xFFAEAEB2) : const Color(0xFF636366),
        onSecondary: dark ? const Color(0xFF1C1C1E) : Colors.white,
        tertiary: dark ? const Color(0xFFFF526F) : AppPalette.brandText,
        onTertiary: dark ? ink : Colors.white,
        tertiaryContainer: dark
            ? const Color(0xFF3C1E28)
            : const Color(0xFFFFF0F3),
        onTertiaryContainer: dark
            ? const Color(0xFFFF9AAE)
            : AppPalette.brandText,
        surface: dark ? const Color(0xFF1C1C1E) : Colors.white,
        surfaceDim: dark ? const Color(0xFF141416) : const Color(0xFFE5E5EA),
        surfaceBright: dark ? const Color(0xFF2C2C2E) : Colors.white,
        surfaceContainerLowest: dark ? Colors.black : Colors.white,
        surfaceContainerLow: dark
            ? const Color(0xFF1C1C1E)
            : const Color(0xFFF9F9FB),
        surfaceContainer: dark
            ? const Color(0xFF1C1C1E)
            : const Color(0xFFF2F2F7),
        surfaceContainerHigh: dark
            ? const Color(0xFF2C2C2E)
            : const Color(0xFFECECEF),
        surfaceContainerHighest: dark
            ? const Color(0xFF353537)
            : const Color(0xFFE5E5EA),
        surfaceTint: Colors.transparent,
        onSurface: dark ? const Color(0xFFF5F5F7) : ink,
        onSurfaceVariant: dark
            ? const Color(0xFFAEAEB2)
            : const Color(0xFF636366),
        secondaryContainer: surfaces.group,
        onSecondaryContainer: dark ? const Color(0xFFF5F5F7) : ink,
        outline: dark ? const Color(0xFF5A5A60) : const Color(0xFF8E8E93),
        outlineVariant: dark
            ? const Color(0xFF353537)
            : const Color(0xFFE5E5EA),
        error: dark ? const Color(0xFFFF6961) : const Color(0xFFD70015),
        onError: Colors.white,
        inverseSurface: dark
            ? const Color(0xFFF5F5F7)
            : const Color(0xFF2C2C2E),
        onInverseSurface: dark ? ink : Colors.white,
        inversePrimary: dark ? AppPalette.brandText : const Color(0xFFFF526F),
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
            padding: const EdgeInsets.symmetric(horizontal: 20),
            textStyle: textTheme.labelLarge,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.control),
            ),
          ).copyWith(
            animationDuration: animated ? AppMotion.press : Duration.zero,
            foregroundBuilder: AppMotion.buttonLayer,
          ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style:
          OutlinedButton.styleFrom(
            minimumSize: Size(target, target),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            textStyle: textTheme.labelLarge,
            backgroundColor: scheme.secondaryContainer,
            foregroundColor: scheme.onSurface,
            side: BorderSide.none,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.control),
            ),
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
      height:
          AppSpace.large +
          (embedded ? MediaQuery.paddingOf(context).bottom : 0),
    ),
  );
}

/// Stable toolbar material, including camera and WebView containers.
class AppToolbar extends AppBar {
  AppToolbar({
    super.key,
    super.title,
    super.leading,
    super.actions,
    super.bottom,
    super.automaticallyImplyLeading,
    super.foregroundColor,
    Color? backgroundColor,
  }) : super(
         backgroundColor: backgroundColor ?? Colors.transparent,
         systemOverlayStyle: backgroundColor == null
             ? null
             : ThemeData.estimateBrightnessForColor(backgroundColor) ==
                   Brightness.dark
             ? SystemUiOverlayStyle.light
             : SystemUiOverlayStyle.dark,
         flexibleSpace: backgroundColor == null
             ? const _ToolbarBackground()
             : ColoredBox(color: backgroundColor),
       );
}

class _ToolbarBackground extends StatelessWidget {
  const _ToolbarBackground();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).scaffoldBackgroundColor;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color, color.withValues(alpha: 0)],
          stops: const [.82, 1],
        ),
      ),
      child: const SizedBox.expand(),
    );
  }
}

class AppSegments<T> extends StatelessWidget {
  const AppSegments({
    super.key,
    required this.values,
    required this.selected,
    required this.onChanged,
    this.senior = false,
    this.enabled = true,
    this.disabled = const {},
    this.keyFor,
    this.labelBuilder,
    this.textStyle,
    this.glass = false,
    this.accent = false,
    this.liquid = false,
    this.material,
  });
  final List<(T, String)> values;
  final T selected;
  final ValueChanged<T> onChanged;
  final bool senior, enabled, glass, accent, liquid;
  final Set<T> disabled;
  final Key Function(T)? keyFor;
  final Widget Function(T, String)? labelBuilder;
  final TextStyle? textStyle;
  final GlassMaterialSpec? material;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final index = values.indexWhere((value) => value.$1 == selected);
    final content = Padding(
      padding: const EdgeInsets.all(2),
      child: Stack(
        children: [
          if (index >= 0)
            Positioned.fill(
              child: AnimatedAlign(
                duration: AppMotionScope.levelOf(context) == AppMotionLevel.full
                    ? AppMotion.navigation
                    : Duration.zero,
                curve: AppMotionScope.levelOf(context) == AppMotionLevel.full
                    ? AppMotion.spring
                    : Curves.linear,
                alignment: Alignment(
                  values.length < 2 ? 0 : 2 * index / (values.length - 1) - 1,
                  0,
                ),
                child: FractionallySizedBox(
                  widthFactor: 1 / values.length,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: accent ? scheme.primary : scheme.surface,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: AppSurfaces.of(context).shadow,
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
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
                          minimumSize: Size(
                            AppSizes.touch,
                            senior ? AppSizes.seniorTouch : AppSizes.touch,
                          ),
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: senior ? 12 : 8,
                          ),
                          foregroundColor: value.$1 == selected
                              ? (accent
                                    ? scheme.onPrimary
                                    : liquid
                                    ? scheme.primary
                                    : scheme.onSurface)
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
          color: AppMotionScope.solidOf(context)
              ? scheme.secondaryContainer
              : scheme.secondaryContainer.withValues(alpha: .74),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: .30),
            width: .5,
          ),
        ),
        child: content,
      );
    }
    return glass
        ? GlassSurface(
            radius: material == null ? 22 : AppRadii.control,
            material: material,
            enabled: enabled,
            child: content,
          )
        : DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
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
  const SheetHeader(this.title, {super.key, this.done = '完成'});
  final String title, done;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
      IconButton.filled(
        tooltip: done,
        style: IconButton.styleFrom(
          backgroundColor: done == '完成'
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.secondaryContainer,
          foregroundColor: done == '完成'
              ? Theme.of(context).colorScheme.onPrimary
              : Theme.of(context).colorScheme.onSurface,
        ),
        onPressed: () => Navigator.pop(context),
        icon: Icon(done == '完成' ? Icons.check_rounded : Icons.close_rounded),
      ),
    ],
  );
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
    this.material,
    this.backdropContext = GlassBackdropContext.plain,
  });
  final AppState state;
  final Widget child;
  final bool enabled;
  final GlassMaterialSpec? material;
  final GlassBackdropContext backdropContext;
  @override
  State<GlassField> createState() => _GlassFieldState();
}

class _GlassFieldState extends State<GlassField> {
  bool focused = false;
  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onFocusChange: (value) => setState(() => focused = value),
    child: Glass(
      state: widget.state,
      radius: AppRadii.control,
      variant: GlassVariant.field,
      material: widget.material,
      focused: focused && widget.enabled,
      enabled: widget.enabled,
      backdropContext: widget.backdropContext,
      child: widget.child,
    ),
  );
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
    radius: 22,
    variant: GlassVariant.liquid,
    backdropContext: backdropContext,
    child: Row(mainAxisSize: MainAxisSize.min, children: children),
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
    material: GlassMaterialSpec.search,
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
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
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
          minHeight: state.senior ? AppSizes.seniorTouch : AppSizes.touch,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpace.sm,
          vertical: 12,
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
  // Native video, camera and WebView layers cannot be sampled reliably.
  final nativeSurface = const {
    'player',
    'tv',
    'scan',
    'admin',
  }.contains(ModalRoute.of(context)?.settings.name);
  final full = AppMotionScope.levelOf(context) == AppMotionLevel.full;
  final controller = AnimationController(
    vsync: Navigator.of(context),
    duration: full ? AppMotion.sheet : Duration.zero,
    reverseDuration: full ? AppMotion.release : Duration.zero,
  );
  final navigator = Navigator.of(context);
  final localizations = MaterialLocalizations.of(context);
  final route = ModalBottomSheetRoute<T>(
    capturedThemes: InheritedTheme.capture(
      from: context,
      to: navigator.context,
    ),
    barrierLabel: localizations.scrimLabel,
    barrierOnTapHint: localizations.scrimOnTapHint(
      localizations.bottomSheetLabel,
    ),
    modalBarrierColor: Theme.of(context).bottomSheetTheme.modalBarrierColor,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    transitionAnimationController: controller,
    sheetAnimationStyle: AppMotion.modalStyle(context),
    builder: (context) => _SheetMotionGate(
      controller: controller,
      child: GlassSurface(
        variant: GlassVariant.sheet,
        solid: nativeSurface,
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
