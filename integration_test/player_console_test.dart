import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:singverse_mobile/core/app_state.dart' show UiMode;
import 'package:singverse_mobile/core/models.dart';
import 'package:singverse_mobile/features/player/player_page.dart';
import 'package:singverse_mobile/main.dart' as app;

/// Real NAS transport, Media3, AndroidView, AudioRecord and local AAC rendering.
/// Run only in the isolated .e2e package, against the disposable loopback NAS.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('physical player console media controls and microphone', (
    tester,
  ) async {
    const origin = String.fromEnvironment('TEST_NAS');
    final uri = Uri.parse(origin);
    expect(uri.host, '127.0.0.1');
    expect(uri.port, 18181);
    final checks = <String>[];
    final report = <String, Object?>{
      'source': 'disposable NAS, original generated media, real native engines',
      'checks': checks,
      'scenarios': <String, Object?>{},
    };
    final scenarios = report['scenarios'] as Map<String, Object?>;
    Future<void> frames([int count = 24]) async {
      for (var i = 0; i < count; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    Future<void> wait(bool Function() predicate, String label) async {
      final end = DateTime.now().add(const Duration(seconds: 45));
      while (!predicate() && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(predicate(), isTrue, reason: label);
    }

    Future<void> shot(String name) async {
      await frames(12);
      // ignore: avoid_print
      print('PLAYER_SCREEN:$name');
      await frames(130);
    }

    Future<void> tap(Finder finder) async {
      await tester.ensureVisible(finder);
      await frames(4);
      expect(finder.hitTestable(), findsOneWidget);
      await tester.tap(finder.hitTestable());
      await frames();
    }

    Future<void> text(String label) => tap(find.text(label).last);
    Future<void> slider(String key, double value) async {
      final finder = find.byKey(ValueKey(key));
      await tester.ensureVisible(finder);
      final widget = tester.widget<Slider>(finder);
      expect(widget.onChanged, isNotNull);
      final rect = tester.getRect(finder);
      final theme = SliderTheme.of(tester.element(finder))
          .copyWith(padding: widget.padding);
      final track = (theme.trackShape ?? const RoundedRectSliderTrackShape())
          .getPreferredRect(
            parentBox: tester.renderObject<RenderBox>(finder),
            offset: rect.topLeft,
            sliderTheme: theme,
            isEnabled: true,
            isDiscrete: widget.divisions != null,
          );
      final fraction = (value - widget.min) / (widget.max - widget.min);
      final gesture = await tester.startGesture(
        Offset(track.left + track.width * fraction, track.center.dy),
      );
      await frames(8);
      await gesture.up();
      await frames();
    }

    Future<void> measure(String label) async {
      final previousPolicy = binding.framePolicy;
      // Let the engine schedule real frames. pump-driven frames include the
      // test harness's artificial wait and do not represent normal playback.
      binding.framePolicy =
          LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive;
      await frames(60);
      final samples = <FrameTiming>[];
      final start = developer.Timeline.now;
      void record(List<FrameTiming> batch) => samples.addAll(
        batch.where(
          (frame) =>
              frame.timestampInMicroseconds(FramePhase.vsyncStart) >= start,
        ),
      );
      binding.addTimingsCallback(record);
      try {
        await tester.pump(const Duration(seconds: 20));
      } finally {
        binding.removeTimingsCallback(record);
        binding.framePolicy = previousPolicy;
      }
      expect(samples.length, greaterThan(100));
      double p95(Iterable<Duration> values) {
        final sorted = values.map((d) => d.inMicroseconds / 1000).toList()
          ..sort();
        return sorted[math.max(0, (sorted.length * .95).ceil() - 1)];
      }

      final over = samples
          .where(
            (f) =>
                f.buildDuration.inMicroseconds > 16667 ||
                f.rasterDuration.inMicroseconds > 16667,
          )
          .length;
      scenarios[label] = {
        'framePolicy': 'benchmarkLive',
        'sampleWindowMs': 20000,
        'frames': samples.length,
        'uiP95Ms': p95(samples.map((f) => f.buildDuration)),
        'rasterP95Ms': p95(samples.map((f) => f.rasterDuration)),
        'overBudgetPercent': over * 100 / samples.length,
      };
    }

    await app.main();
    await frames();
    final state = tester
        .widget<app.SingVerseApp>(find.byType(app.SingVerseApp))
        .state;
    await wait(() => state.initialized, 'app initializes');
    expect(state.taking, isFalse, reason: 'never interrupt an existing take');
    await state.connect(origin);
    if (!state.authenticated) await state.login('admin');
    expect(state.authenticated, isTrue);
    await state.setUiMode(UiMode.standard);
    await state.setPerformanceMode(false);
    await state.setTransparency(false);
    final catalog =
        await state.get('/api/v1/mobile/library/songs?size=100') as Json;
    final songs = (catalog['items'] as List).cast<Json>();
    final video = Song(
      songs.firstWhere(
        (s) => s['mediaType'] == 'VIDEO' && s['title'] == '晚风练习',
      ),
    );
    final audio = Song(
      songs.firstWhere(
        (s) => s['mediaType'] == 'AUDIO' && s['title'] == '晨光练习',
      ),
    );
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    Future<void> open(Song song) async {
      navigator.push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'player'),
          builder: (_) => PlayerPage(state: state, song: song),
        ),
      );
      await frames();
      await wait(
        () =>
            state.current?.id == song.id &&
            state.isPlaying &&
            state.tracks.any((t) => t['type'] == 'audio'),
        'native ${song.mediaType} decoder plays',
      );
    }

    try {
      await open(video);
      await wait(() => state.positionMs > 1000, 'native video clock advances');
      if (state.isFavorite(video)) await state.favorite(video);
      expect(find.byType(AndroidView), findsOneWidget);
      checks.add('native-video-initial');
      await shot('01-video-playing');
      if (const bool.fromEnvironment('PLAYER_BASELINE')) {
        await state.command('pause');
        await shot('02-video-paused');
        binding.reportData = report;
        return;
      }
      await tap(find.byTooltip(state.isFavorite(video) ? '取消收藏' : '收藏歌曲'));
      await wait(() => state.isFavorite(video), 'NAS favorite persists');
      checks.add('favorite');
      await tap(find.byKey(const ValueKey('player-play')));
      await wait(() => !state.isPlaying, 'pause');
      await shot('02-video-paused');
      await slider('player-progress', 20000);
      await wait(
        () => (state.positionMs - 20000).abs() < 1500,
        'timeline seeks',
      );
      checks.add('seek-and-pause');
      await tap(find.byKey(const ValueKey('player-play')));
      await wait(() => state.isPlaying, 'play');
      await tap(find.byTooltip('全屏视频'));
      await wait(
        () => find
            .byKey(const ValueKey('player-landscape-surface'))
            .evaluate()
            .isNotEmpty,
        'native fullscreen landscape',
      );
      await shot('03-fullscreen-video');
      final surface = find.byKey(const ValueKey('player-landscape-surface'));
      if (find.byTooltip('退出横屏').hitTestable().evaluate().isEmpty) {
        await tester.tapAt(tester.getTopLeft(surface) + const Offset(8, 8));
        await frames(4);
      }
      await tap(find.byTooltip('退出横屏'));
      await wait(
        () => find
            .byKey(const ValueKey('player-landscape-surface'))
            .evaluate()
            .isEmpty,
        'return from fullscreen',
      );
      checks.add('fullscreen-return');
      await text('调音');
      await slider('pitch-control', 2);
      await slider('speed-control', .9);
      await wait(
        () => state.pitch == 2 && (state.speed - .9).abs() < .01,
        'native tuning',
      );
      await shot('04-tuning');
      await text('音轨与播放设置');
      await text('音轨 1');
      await text('设为原唱');
      await text('确认标记');
      await wait(
        () => state.originalMapped,
        'real original audio role is marked',
      );
      await text('音轨 2');
      await text('设为伴奏');
      await text('确认标记');
      await wait(() => state.backingMapped, 'real audio role is marked');
      await tester.binding.handlePopRoute();
      await frames();
      await tester.binding.handlePopRoute();
      await frames();
      for (final role in ['original', 'backing', 'original', 'backing']) {
        await tap(find.byKey(ValueKey('player-role-$role')));
        await wait(() => state.audioRole == role, 'native role $role');
      }
      checks.addAll(['tuning', 'original-backing-fast-switch']);
      await text('重唱');
      await wait(
        () => state.isPlaying && state.positionMs < 6000,
        'restart plays from beginning',
      );
      checks.add('restart');
      await text('选段');
      await text('当前位置设为起点');
      await text('循环练唱这一段');
      await wait(() => state.rangeB > state.rangeA, 'native range applied');
      await shot('05-selected-range');
      await text('选段');
      await text('恢复整首练唱');
      await wait(() => state.rangeB == 0, 'native range cleared');
      checks.add('range-apply-clear');
      await text('更多');
      await shot('06-more-tools');
      await tester.binding.handlePopRoute();
      await frames();
      checks.add('more-dismiss');
      await measure('default-native-video');
      await state.setPerformanceMode(true);
      await frames();
      await shot('07-performance-mode');
      await measure('performance-native-video');
      await state.setPerformanceMode(false);
      await state.setTransparency(true);
      await shot('08-reduced-transparency');
      await state.setTransparency(false);
      // The host changes and restores the physical phone's system font scale.
      // ignore: avoid_print
      print('PLAYER_LARGE_FONT');
      await wait(
        () =>
            MediaQuery.textScalerOf(tester.element(find.byType(PlayerPage)))
                .scale(16) >
            24,
        'system 200 percent font',
      );
      await shot('09-system-large-type');
      for (final key in ['player-play', 'player-record']) {
        expect(find.byKey(ValueKey(key)).hitTestable(), findsOneWidget);
      }
      // ignore: avoid_print
      print('PLAYER_NORMAL_FONT');
      await wait(
        () =>
            MediaQuery.textScalerOf(tester.element(find.byType(PlayerPage)))
                .scale(16) <
            20,
        'system font restored for standard scene',
      );
      await state.setUiMode(UiMode.senior);
      await shot('10-senior-mode');
      expect(
        find.byKey(const ValueKey('player-record')).hitTestable(),
        findsOneWidget,
      );
      await state.setUiMode(UiMode.standard);
      checks.addAll([
        'performance-toggle',
        'reduced-transparency',
        'system-font-200',
        'senior-safe-area',
      ]);
      await state.command('seek', 0);
      await state.command('play');
      // Grants are scoped to the disposable package, never the daily app.
      // ignore: avoid_print
      print('PLAYER_MIC_GRANT');
      await frames(100);
      await tap(find.byKey(const ValueKey('player-record')));
      await wait(
        () => state.countdown > 0 || state.recording,
        'real native countdown',
      );
      await shot('11-countdown');
      await wait(
        () =>
            state.recording && (state.singing['recordedMs'] as num? ?? 0) > 500,
        'AudioRecord captures actual microphone',
      );
      // ignore: avoid_print
      print('PLAYER_HOST_VOICE');
      var peak = 0.0;
      for (var i = 0; i < 45; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        peak = math.max(peak, (state.singing['level'] as num? ?? 0).toDouble());
      }
      await shot('12-recording');
      final recordedMs = (state.singing['recordedMs'] as num).toInt();
      expect(recordedMs, greaterThan(1000));
      expect(
        peak,
        greaterThan(0),
        reason: 'physical microphone input has a real nonzero level',
      );
      for (final role in ['original', 'backing']) {
        expect(
          tester
              .widget<TextButton>(find.byKey(ValueKey('player-role-$role')))
              .onPressed,
          isNull,
        );
      }
      expect(
        tester
            .widget<Slider>(find.byKey(const ValueKey('player-progress')))
            .onChanged,
        isNull,
      );
      await tap(find.byKey(const ValueKey('player-record')));
      await wait(
        () => state.singingPhase == 'PREVIEW',
        'native take finishes and mixes',
      );
      await wait(
        () => find.byType(PlayerPage).evaluate().isEmpty,
        'retained take opens review',
      );
      final work = await state.sing('get', {'id': state.takeId}) as Json;
      expect(work['hasPreview'], isTrue);
      expect(work['voiceFrames'] as num, greaterThan(48000));
      expect(work['backingFrames'] as num, greaterThan(48000));
      report['recording'] = {
        'recordedMs': recordedMs,
        'microphonePeak': peak,
        for (final key in [
          'id',
          'status',
          'hasPreview',
          'voiceFrames',
          'backingFrames',
          'timestampAligned',
        ])
          key: work[key],
      };
      checks.addAll([
        'microphone-countdown',
        'recording-native-time',
        'recording-source-lock',
        'finish-and-retain-preview',
      ]);
      await shot('13-recording-review');
      await text('播放录音');
      await wait(
        () => state.workId == work['id'] && state.isPlaying,
        'actual AAC preview playback',
      );
      checks.add('local-preview-playback');
      await state.command('pause');
      navigator.popUntil((route) => route.isFirst);
      await frames();
      await open(audio);
      await measure('default-native-audio-lyrics');
      await shot('14-audio-lyrics');
      checks.add('native-audio-and-lyrics-clock');
      expect(tester.takeException(), isNull);
      binding.reportData = report;
      // ignore: avoid_print
      print('PLAYER_CONSOLE_PASS:${checks.length}');
    } finally {
      if (state.recording) await state.endTake();
      if (state.countdown > 0) await state.command('cancelCountdown');
      await state.command('pause');
      await state.setPerformanceMode(false);
      await state.setTransparency(false);
      await state.setUiMode(UiMode.standard);
    }
  });
}
