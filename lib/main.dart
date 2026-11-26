import 'features/updates/update_page.dart';

import 'package:fluid_glass/fluid_glass.dart' show FluidGlass;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/design.dart';
import 'app/mini_player.dart';
import 'app/shell.dart';
import 'core/api.dart';
import 'core/app_state.dart';
import 'core/local_store.dart';
import 'features/library/widgets.dart';
import 'features/player/player_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerThirdPartyLicenses();
  try {
    await FluidGlass.ensureInitialized();
  } catch (_) {}
  try {
    final state = AppState(
      api: NativeNasApi(),
      store: await LocalStore.open(),
      preferences: await SharedPreferences.getInstance(),
    );
    runApp(SingVerseApp(state: state));
    await state.initialize();
  } catch (_) {
    runApp(
      MaterialApp(
        theme: singVerseTheme(Brightness.light),
        home: const Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('无法打开本机数据。请检查手机存储空间后重新启动 SingVerse。'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

bool _licensesRegistered = false;

void _registerThirdPartyLicenses() {
  if (_licensesRegistered) return;
  _licensesRegistered = true;
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['fluid_glass'],
      'FluidGlass (Copyright 2026 Tianli, Apache-2.0)\n'
      'Portions derived from Kyant0/AndroidLiquidGlass ("backdrop", '
      'Copyright 2025 Kyant, Apache-2.0) and Kyant0/Shapes '
      '(Copyright 2025 Kyant, Apache-2.0).',
    );
  });
}

class SingVerseApp extends StatefulWidget {
  const SingVerseApp({super.key, required this.state});
  final AppState state;
  @override
  State<SingVerseApp> createState() => _SingVerseAppState();
}

class _SingVerseAppState extends State<SingVerseApp> {
  final navigator = GlobalKey<NavigatorState>();
  final pages = PageTracker();
  int stageRequest = 0;
  @override
  void initState() {
    super.initState();
    widget.state.addListener(openRequestedStage);
    openRequestedStage();
  }

  void openRequestedStage() {
    if (widget.state.stageRequests == stageRequest) return;
    stageRequest = widget.state.stageRequests;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final page = pages.current.value;
      final recordingBehindReview = page == 'review' && widget.state.taking;
      if (mounted &&
          page != 'player' &&
          (page != 'review' || recordingBehindReview)) {
        navigator.currentState?.push(
          playerStageRoute<void>(
            settings: const RouteSettings(name: 'player'),
            builder: (_) => performancePage(widget.state),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    widget.state.removeListener(openRequestedStage);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.state, widget.state.updates]),
    builder: (context, _) {
      final state = widget.state;
      final compact = MediaQuery.sizeOf(context).width < 375;
      final motion = state.performanceMode
          ? AppMotionLevel.none
          : state.senior ||
                MediaQuery.disableAnimationsOf(context) ||
                MediaQuery.accessibleNavigationOf(context)
          ? AppMotionLevel.reduced
          : AppMotionLevel.full;
      return MaterialApp(
        title: 'SingVerse',
        debugShowCheckedModeBanner: false,
        navigatorKey: navigator,
        navigatorObservers: [pages],
        theme: singVerseTheme(
          Brightness.light,
          senior: state.senior,
          compact: compact,
          motion: motion,
        ),
        darkTheme: singVerseTheme(
          Brightness.dark,
          senior: state.senior,
          compact: compact,
          motion: motion,
        ),
        themeMode: state.themeMode,
        themeAnimationDuration: switch (motion) {
          AppMotionLevel.full => AppMotion.release,
          AppMotionLevel.reduced => const Duration(milliseconds: 100),
          AppMotionLevel.none => Duration.zero,
        },
        themeAnimationCurve: Curves.easeOutCubic,
        builder: (context, child) {
          final baseMedia = MediaQuery.of(context);
          return AppMotionScope(
            performanceMode: state.performanceMode,
            senior: state.senior,
            reduceTransparency: state.reduceTransparency,
            child: MediaQuery(
              data: baseMedia.copyWith(
                disableAnimations:
                    state.performanceMode || baseMedia.disableAnimations,
              ),
              child: ValueListenableBuilder<String>(
                valueListenable: pages.current,
                builder: (context, page, _) {
                  final nativePage = const {
                    'player',
                    'tv',
                    'scan',
                    'admin',
                  }.contains(page);
                  final showGlobalMini =
                      state.current != null &&
                      !const {
                        '/',
                        'player',
                        'review',
                        'tv',
                        'scan',
                      }.contains(page) &&
                      baseMedia.viewInsets.bottom == 0;
                  final miniInset = showGlobalMini
                      ? MiniPlayer.heightOf(context, state) + 16
                      : 0.0;
                  final routeMedia = baseMedia.copyWith(
                    disableAnimations:
                        state.performanceMode || baseMedia.disableAnimations,
                    padding: baseMedia.padding.copyWith(
                      bottom: baseMedia.padding.bottom + miniInset,
                    ),
                    viewPadding: baseMedia.viewPadding.copyWith(
                      bottom: baseMedia.viewPadding.bottom + miniInset,
                    ),
                  );
                  return Overlay.wrap(
                    child: AppBackdropCapture(
                      solid: nativePage,
                      builder: (context, rootEnvBackdrop) => AppBackdropCapture(
                        solid: nativePage,
                        builder: (context, rootNavBackdrop) => Stack(
                          fit: StackFit.expand,
                          children: [
                            Positioned.fill(
                              child: AppBackdropSource(
                                backdrop: rootNavBackdrop,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Positioned.fill(
                                      child: AppBackdropSource(
                                        backdrop: rootEnvBackdrop,
                                        child: AppEnvironment(
                                          child: nativePage
                                              ? const SizedBox.shrink()
                                              : ShellAmbientGlow(state: state),
                                        ),
                                      ),
                                    ),
                                    AppBackdropScope(
                                      environment: nativePage
                                          ? null
                                          : rootEnvBackdrop,
                                      content: null,
                                      child: Column(
                                        children: [
                                          if (state.updates.prompt &&
                                              !state.taking &&
                                              state.singingPhase !=
                                                  'RENDERING' &&
                                              ![
                                                'player',
                                                'review',
                                                'tv',
                                                'scan',
                                                'updates',
                                              ].contains(page))
                                            Material(
                                              color: Colors.transparent,
                                              child: SafeArea(
                                                bottom: false,
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.fromLTRB(
                                                        12,
                                                        6,
                                                        12,
                                                        4,
                                                      ),
                                                  child: GlassSurface(
                                                    radius: 20,
                                                    material: GlassMaterialSpec
                                                        .standard,
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 14,
                                                            vertical: 8,
                                                          ),
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .stretch,
                                                        children: [
                                                          Text(
                                                            '手机有新版本 ${state.updates.release!['versionName']}',
                                                          ),
                                                          Wrap(
                                                            spacing: 8,
                                                            children: [
                                                              TextButton(
                                                                onPressed: () => navigator.currentState?.push(
                                                                  MaterialPageRoute<
                                                                    void
                                                                  >(
                                                                    settings:
                                                                        const RouteSettings(
                                                                          name: 'updates',
                                                                        ),
                                                                    builder: (_) =>
                                                                        UpdatePage(
                                                                          updates:
                                                                              state.updates,
                                                                        ),
                                                                  ),
                                                                ),
                                                                child:
                                                                    const Text(
                                                                      '查看更新',
                                                                    ),
                                                              ),
                                                              TextButton(
                                                                onPressed: state
                                                                    .updates
                                                                    .skip,
                                                                child:
                                                                    const Text(
                                                                      '跳过此版本',
                                                                    ),
                                                              ),
                                                              TextButton(
                                                                onPressed: state
                                                                    .updates
                                                                    .later,
                                                                child:
                                                                    const Text(
                                                                      '稍后',
                                                                    ),
                                                              ),
                                                            ],
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          Expanded(
                                            child: MediaQuery(
                                              data: routeMedia,
                                              child: child!,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: AppBackdropScope(
                                environment: nativePage
                                    ? null
                                    : rootEnvBackdrop,
                                content: nativePage ? null : rootNavBackdrop,
                                child: MotionVisibility(
                                  immediate: baseMedia.viewInsets.bottom > 0,
                                  visible: showGlobalMini,
                                  child: Material(
                                    color: Colors.transparent,
                                    child: SafeArea(
                                      top: false,
                                      child: ValueListenableBuilder<bool>(
                                        valueListenable: pages.modalOpen,
                                        builder: (context, modal, _) =>
                                            IgnorePointer(
                                              ignoring: modal,
                                              child: ExcludeSemantics(
                                                excluding: modal,
                                                child: ContentWidth(
                                                  child: Padding(
                                                    padding:
                                                        EdgeInsets.symmetric(
                                                          horizontal:
                                                              page ==
                                                                  'connection'
                                                              ? 12
                                                              : 0,
                                                        ),
                                                    child: MiniPlayer(
                                                      state: state,
                                                      navigator: navigator
                                                          .currentState,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
        home: state.initialized
            ? AppShell(state: state)
            : const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    },
  );
}
