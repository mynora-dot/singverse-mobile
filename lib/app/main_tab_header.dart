import 'package:fluid_glass/fluid_glass.dart' as fg;
import 'package:flutter/material.dart';

import 'design.dart';

class MainTabHeader extends StatelessWidget {
  const MainTabHeader({
    super.key,
    required this.senior,
    required this.actions,
    this.search,
  });

  final bool senior;
  final Widget actions;
  final Widget? search;

  static double insetOf(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 375 ? AppSpace.md : AppSpace.page;

  static double actionSize(bool senior) => senior ? AppSizes.seniorTouch : 48;

  // Pull-to-refresh settles below the controls even when the header has two rows.
  static double refreshEdgeOffsetOf(BuildContext context) =>
      MediaQuery.paddingOf(context).top +
      AppSizes.seniorTouch +
      AppSpace.md +
      MediaQuery.textScalerOf(context).scale(18);

  @override
  Widget build(BuildContext context) {
    final solid = AppMotionScope.solidOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = Theme.of(context).scaffoldBackgroundColor;
    final search = this.search;
    final inset = insetOf(context);
    // Keep the safe-area padding in the header so content can scroll under it.
    final controls = Padding(
      padding: EdgeInsets.fromLTRB(
        inset,
        MediaQuery.paddingOf(context).top + AppSpace.xs,
        inset,
        AppSpace.xs,
      ),
      // Sample the page gradient so the controls never capture their own glass.
      child: AppBackdropScope(
        environment: AppBackdropScope.maybeOf(context, sampleContent: false),
        child: search == null
            ? Align(alignment: AlignmentDirectional.centerEnd, child: actions)
            : LayoutBuilder(
                builder: (context, constraints) {
                  // Reserve room for the search icon, filter and search hint.
                  final touch = actionSize(senior);
                  final scaledText = MediaQuery.textScalerOf(context)
                      .scale(senior ? 18 : 16);
                  final inlineWidth = touch * 4 + AppSpace.sm + scaledText * 7;
                  if (constraints.maxWidth < inlineWidth) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        actions,
                        const SizedBox(height: AppSpace.xxs),
                        search,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: search),
                      const SizedBox(width: AppSpace.xs),
                      actions,
                    ],
                  );
                },
              ),
      ),
    );
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final amount = (constraints.scrollOffset / 40).clamp(0.0, 1.0);
        const feather = 24.0;
        Widget? surface;
        if (amount > 0) {
          final tint = DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.28, 0.50, 0.68, 0.82, 0.92, 1.0],
                colors: [
                  background.withValues(alpha: (dark ? .84 : .82) * amount),
                  background.withValues(alpha: (dark ? .72 : .68) * amount),
                  background.withValues(alpha: (dark ? .50 : .44) * amount),
                  background.withValues(alpha: (dark ? .24 : .20) * amount),
                  background.withValues(alpha: (dark ? .08 : .06) * amount),
                  background.withValues(alpha: (dark ? .02 : .015) * amount),
                  background.withValues(alpha: 0),
                ],
              ),
            ),
          );
          surface = solid
              ? tint
              : fg.ProgressiveBlur(
                  maxBlurRadius: 14 * amount,
                  direction: fg.ProgressiveBlurDirection.blurredTopClearBottom,
                  startOffset: 0.34,
                  bands: 6,
                  child: tint,
                );
        }
        return PinnedHeaderSliver(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Positioned.fill(
                child: Listener(behavior: HitTestBehavior.opaque),
              ),
              if (surface != null)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  bottom: -feather,
                  child: IgnorePointer(child: surface),
                ),
              controls,
            ],
          ),
        );
      },
    );
  }
}
