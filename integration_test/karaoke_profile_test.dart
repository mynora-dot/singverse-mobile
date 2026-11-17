import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:singverse_mobile/core/app_state.dart';
import 'package:singverse_mobile/core/models.dart';
import 'package:singverse_mobile/features/player/player_page.dart';
import 'package:singverse_mobile/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Liquid Glass profile navigation scroll sheets and native lyrics', (
    tester,
  ) async {
    await app.main();
    Future<void> frames([int count = 26]) async {
      for (var i = 0; i < count; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    Future<void> wait(bool Function() condition, String reason) async {
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (!condition() && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(condition(), isTrue, reason: reason);
    }

    Future<void> tap(Finder finder) async {
      expect(finder.hitTestable(), findsOneWidget);
      await tester.tap(finder.hitTestable());
      await frames();
    }

    Future<void> shot(String name) async {
      // ignore: avoid_print
      print('KARAOKE_SCREEN:$name');
      await frames(140); // Leave time for the host's real device screenshot.
    }

    await frames();
    final state = tester
        .widget<app.SingVerseApp>(find.byType(app.SingVerseApp))
        .state;
    await wait(() => state.initialized, 'application initializes');
    expect(
      state.taking,
      isFalse,
      reason: 'profile must not interrupt an active recording',
    );
    const origin = String.fromEnvironment(
      'TEST_NAS',
      defaultValue: 'http://10.0.2.2:18181',
    );
    final uri = Uri.parse(origin);
    expect(
      uri.host,
      '10.0.2.2',
      reason: 'use only the disposable emulator NAS',
    );
    expect(uri.port, 18181);
    await state.connect(origin);
    if (!state.authenticated) await state.login('admin');
    expect(state.authenticated, isTrue);
    await state.setUiMode(UiMode.standard);
    await state.setTransparency(false);
    await state.setTheme(ThemeMode.light);
    final library =
        await state.get('/api/v1/mobile/library/songs?size=100') as Json;
    final songs = (library['items'] as List).cast<Json>();
    final audio = Song(
      songs.firstWhere(
        (song) => song['mediaType'] == 'AUDIO' && song['title'] == '晨光练习',
      ),
    );
    final video = Song(
      songs.firstWhere(
        (song) => song['mediaType'] == 'VIDEO' && song['title'] == '晚风练习',
      ),
    );
    Future<void> openFixture(Song song) async {
      // Set up a real player scene outside the frame sampling window.
      // Search/debounce behavior is covered by the existing UI flow suite.
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      navigator.push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'player'),
          builder: (_) => PlayerPage(state: state, song: song),
        ),
      );
      await frames();
    }

    final report = <String, Object?>{
      'mode': 'profile',
      'frameBudgetMs': 16.667,
      'scenarios': <String, Object?>{},
    };
    final scenarios = report['scenarios'] as Map<String, Object?>;
    Future<void> measure(String key, Future<void> Function() action) async {
      await frames(20);
      final samples = <FrameTiming>[];
      final start = developer.Timeline.now;
      void record(List<FrameTiming> timings) {
        samples.addAll(
          timings.where(
            (frame) =>
                frame.timestampInMicroseconds(FramePhase.vsyncStart) >= start,
          ),
        );
      }

      binding.addTimingsCallback(record);
      try {
        await action();
        await frames(40); // Allow Flutter's batched timing callback to arrive.
      } finally {
        binding.removeTimingsCallback(record);
      }
      expect(samples, isNotEmpty, reason: '$key receives real frame timings');
      double p95(Iterable<Duration> values) {
        final sorted = values.map((d) => d.inMicroseconds / 1000).toList()
          ..sort();
        return sorted[math.max(0, (sorted.length * .95).ceil() - 1)];
      }

      final over = samples
          .where(
            (frame) =>
                frame.buildDuration.inMicroseconds > 16667 ||
                frame.rasterDuration.inMicroseconds > 16667,
          )
          .length;
      scenarios[key] = {
        'frames': samples.length,
        'uiP95Ms': p95(samples.map((f) => f.buildDuration)),
        'rasterP95Ms': p95(samples.map((f) => f.rasterDuration)),
        'overBudgetFrames': over,
        'overBudgetPercent': 100 * over / samples.length,
      };
      // ignore: avoid_print
      print(
        'LIQUID_GLASS_PROFILE:${jsonEncode({'scenario': key, 'timings': scenarios[key]})}',
      );
    }

    try {
      for (final performance in [false, true]) {
        await state.setPerformanceMode(performance);
        await frames(60);
        final mode = performance ? 'performance' : 'default';
        for (final tab in ['frequent', 'works', 'songs']) {
          await tap(find.byKey(Key('nav-$tab')));
        }
        await shot('glass-$mode-library');
        await measure('$mode-navigation', () async {
          for (var repeat = 0; repeat < 4; repeat++) {
            for (final tab in ['frequent', 'works', 'songs']) {
              await tap(find.byKey(Key('nav-$tab')));
            }
          }
        });
        await measure('$mode-scroll', () async {
          final list = find.byType(CustomScrollView).first;
          final position = tester
              .state<ScrollableState>(
                find
                    .descendant(of: list, matching: find.byType(Scrollable))
                    .first,
              )
              .position;
          expect(position.maxScrollExtent, greaterThan(0));
          for (var repeat = 0; repeat < 3; repeat++) {
            await tester.fling(list, const Offset(0, -540), 1000);
            await frames(40);
            await tester.fling(list, const Offset(0, 540), 1000);
            await frames(40);
          }
        });
        await tester.drag(
          find.byType(CustomScrollView).first,
          const Offset(0, 3000),
        );
        await frames();
        await tap(find.byTooltip('筛选歌曲'));
        await shot('glass-$mode-sheet');
        await tap(find.text('取消').last);
        await measure('$mode-sheet', () async {
          for (var repeat = 0; repeat < 3; repeat++) {
            await tap(find.byTooltip('筛选歌曲'));
            await tap(find.text('取消').last);
          }
        });
        // Exercise pointer feedback without involving network or recording.
        await measure('$mode-glass-press', () async {
          final button = find.byKey(const Key('open-settings'));
          for (var repeat = 0; repeat < 5; repeat++) {
            final gesture = await tester.startGesture(tester.getCenter(button));
            await frames(7);
            await gesture.cancel();
            await frames(15);
          }
        });
        await openFixture(audio);
        await wait(
          () =>
              find.byType(PlayerPage).evaluate().isNotEmpty &&
              state.current?.mediaType == 'AUDIO' &&
              state.isPlaying &&
              state.positionMs > 1000,
          'native audio and lyric clock play',
        );
        expect(find.byType(LyricsView), findsOneWidget);
        await shot('glass-$mode-lyrics');
        await measure('$mode-lyrics', () => frames(240));
        await state.command('pause');
        await tap(find.byTooltip('收起演唱'));
        await frames(40);
        expect(tester.takeException(), isNull);
      }
      await state.setPerformanceMode(false);
      await openFixture(video);
      await wait(
        () =>
            state.current?.mediaType == 'VIDEO' &&
            state.isPlaying &&
            state.positionMs > 1000,
        'native Android video plays',
      );
      expect(find.byType(AndroidView), findsOneWidget);
      await shot('glass-native-video');
      await state.command('pause');
      await tap(find.byTooltip('收起演唱'));
      await frames(40);
      await state.setTheme(ThemeMode.dark);
      await shot('glass-dark-library');
      binding.reportData = report;
      // ignore: avoid_print
      print('LIQUID_GLASS_PROFILE_DONE:${scenarios.length}');
      // ignore: avoid_print
      print('KARAOKE_UI_FLOW_PASS:Liquid Glass profile and native video');
    } finally {
      await state.setPerformanceMode(false);
      await state.setUiMode(UiMode.standard);
    }
  });
}
