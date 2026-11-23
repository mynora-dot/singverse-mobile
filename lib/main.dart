import 'features/updates/update_page.dart';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/design.dart';
import 'app/mini_player.dart';
import 'app/shell.dart';
import 'core/api.dart';
import 'core/app_state.dart';
import 'core/local_store.dart';
import 'features/player/player_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
        builder: (context, child) => AppMotionScope(
          performanceMode: state.performanceMode,
          senior: state.senior,
          reduceTransparency: state.reduceTransparency,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations:
                  state.performanceMode ||
                  MediaQuery.disableAnimationsOf(context),
            ),
            child: ValueListenableBuilder<String>(
              valueListenable: pages.current,
              builder: (context, page, _) => Overlay.wrap(
                child: AppEnvironment(
                  child: Column(
                    children: [
                      if (state.updates.prompt &&
                          !state.taking &&
                          state.singingPhase != 'RENDERING' &&
                          ![
                            'player',
                            'review',
                            'tv',
                            'scan',
                            'updates',
                          ].contains(page))
                        Material(
                          child: SafeArea(
                            bottom: false,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    '手机有新版本 ${state.updates.release!['versionName']}',
                                  ),
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      TextButton(
                                        onPressed: () =>
                                            navigator.currentState?.push(
                                              MaterialPageRoute<void>(
                                                settings: const RouteSettings(
                                                  name: 'updates',
                                                ),
                                                builder: (_) => UpdatePage(
                                                  updates: state.updates,
                                                ),
                                              ),
                                            ),
                                        child: const Text('查看更新'),
                                      ),
                                      TextButton(
                                        onPressed: state.updates.skip,
                                        child: const Text('跳过此版本'),
                                      ),
                                      TextButton(
                                        onPressed: state.updates.later,
                                        child: const Text('稍后'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      Expanded(child: child!),
                      MotionVisibility(
                        immediate: MediaQuery.viewInsetsOf(context).bottom > 0,
                        visible:
                            state.current != null &&
                            ![
                              '/',
                              'player',
                              'review',
                              'tv',
                              'scan',
                            ].contains(page) &&
                            MediaQuery.viewInsetsOf(context).bottom == 0,
                        child: Material(
                          color: Colors.transparent,
                          child: SafeArea(
                            top: false,
                            child: ValueListenableBuilder<bool>(
                              valueListenable: pages.modalOpen,
                              builder: (context, modal, _) => IgnorePointer(
                                ignoring: modal,
                                child: ExcludeSemantics(
                                  excluding: modal,
                                  child: ContentWidth(
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: page == 'connection'
                                            ? 12
                                            : 0,
                                      ),
                                      child: MiniPlayer(
                                        state: state,
                                        navigator: navigator.currentState,
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
            ),
          ),
        ),
        home: state.initialized
            ? AppShell(state: state)
            : const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    },
  );
}
