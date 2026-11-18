import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:singverse_mobile/app/design.dart';
import 'package:singverse_mobile/app/glass_optics.dart' show RenderLiquidLens;
import 'package:singverse_mobile/core/app_state.dart';
import 'package:singverse_mobile/core/local_store.dart';
import 'package:singverse_mobile/core/login_store.dart';
import 'package:singverse_mobile/core/models.dart';
import 'package:singverse_mobile/features/library/connection.dart';
import 'package:singverse_mobile/features/library/widgets.dart';
import 'package:singverse_mobile/features/player/player_page.dart';
import 'package:singverse_mobile/main.dart';

import '../test/widget_test.dart' show FakeApi;

import 'phone_failure_reporter.dart';

/// Only this isolated test owns catalog fixtures and playback method mocks.
/// Production continues to use the NAS API, original covers and native audio.
class _Catalog extends FakeApi {
  _Catalog(this.cover);
  final Uint8List cover;
  @override
  Future<Uint8List> bytes(String path) async => cover;
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Object? body,
  }) async {
    final uri = Uri.parse(path);
    if (uri.path == '/api/v1/mobile/library/songs') {
      requests.add(path);
      final query = uri.queryParameters['q'] ?? '';
      final filtered = rows
          .where(
            (row) =>
                (query.isEmpty || row['title'].toString().contains(query)) &&
                (!uri.queryParameters.containsKey('tagIds') ||
                    int.parse(row['id'] as String).isEven),
          )
          .toList();
      return {'items': filtered, 'totalElements': filtered.length};
    }
    return super.request(path, method: method, body: body);
  }
}

class _NoSecrets implements LoginStore {
  @override
  Future<List<LoginRecord>> load() async => [];
  @override
  Future<String?> password(LoginRecord record) async => null;
  @override
  Future<void> save(LoginRecord record, {String? password}) async {}
  @override
  Future<void> remove(LoginRecord record) async {}
  @override
  Future<void> forgetPassword(LoginRecord record) async {}
  @override
  Future<void> forgetServerPasswords(String instanceId) async {}
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  installPhoneFailureReporter(binding);
  testWidgets(
    'shared glass catalog preserves search filters playback and navigation',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open(path: ':memory:');
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 256, 256),
        Paint()
          ..shader = ui.Gradient.linear(Offset.zero, const Offset(256, 256), [
            const Color(0xFF18235A),
            const Color(0xFF6C85FF),
          ]),
      );
      canvas.drawCircle(
        const Offset(180, 76),
        46,
        Paint()..color = const Color(0xFFFFC9A8),
      );
      canvas.drawPath(
        Path()
          ..moveTo(0, 176)
          ..quadraticBezierTo(140, 88, 256, 178)
          ..lineTo(256, 256)
          ..lineTo(0, 256)
          ..close(),
        Paint()..color = const Color(0xFF14214B),
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(256, 256);
      final cover = (await image.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List();
      image.dispose();
      picture.dispose();
      final api = _Catalog(cover)..loggedIn = true;
      api.rows = List.generate(
        12,
        (i) => {
          'id': '${i + 1}',
          'title': i == 0 ? '晴天' : '练唱曲目 ${i + 1}',
          'artists': ['样本歌手'],
          'mediaType': 'AUDIO',
          'version': 'ACCOMPANIMENT',
          'coverPath': '/api/v1/test-artwork/$i',
        },
      );
      api.tags = [
        {
          'id': 'lang',
          'name': '国语',
          'dimension': 'LANGUAGE',
          'active': true,
          'count': 6,
        },
        {
          'id': 'mood',
          'name': '轻松',
          'dimension': 'MOOD',
          'active': true,
          'count': 6,
        },
        for (var i = 0; i < 18; i++)
          {
            'id': 'scene-$i',
            'name': '适合家庭一起练唱的场景 ${i + 1}',
            'dimension': 'CUSTOM',
            'active': true,
            'count': 6,
          },
      ];
      final state =
          AppState(
              api: api,
              store: store,
              preferences: await SharedPreferences.getInstance(),
              loginStore: _NoSecrets(),
              listenPlayer: false,
            )
            ..initialized = true
            ..authenticated = true
            ..instanceId = 'nas-a'
            ..origin = 'http://nas.local:18080'
            ..themeMode = ThemeMode.light
            ..current = Song({...api.rows.first, 'title': 'All Night'})
            ..playbackState = 'PAUSED'
            ..positionMs = 30000
            ..durationMs = 240000;
      final commands = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(AppState.player, (call) async {
        if (call.method == 'command') {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          commands.add(args['action'] as String);
          if (args['action'] == 'play' || args['action'] == 'pause') {
            state.isPlaying = args['action'] == 'play';
            state.playbackState = state.isPlaying ? 'PLAYING' : 'PAUSED';
          }
          state.notifyListeners();
        }
        if (call.method == 'open') {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          commands.add('open');
          state.current = Song(jsonDecode(args['song'] as String) as Json);
          state.isPlaying = args['autoplay'] == true;
          state.playbackState = state.isPlaying ? 'PLAYING' : 'PAUSED';
          state.notifyListeners();
        }
        if (call.method == 'snapshot') {
          return {
            'song': jsonEncode(state.current!.data),
            'instanceId': state.instanceId,
            'isPlaying': state.isPlaying,
            'state': state.playbackState,
            'positionMs': state.positionMs,
            'durationMs': state.durationMs,
          };
        }
        return null;
      });
      messenger.setMockMethodCallHandler(
        AppState.karaoke,
        (call) async => call.method == 'works' ? '[]' : null,
      );
      addTearDown(() async {
        messenger.setMockMethodCallHandler(AppState.player, null);
        messenger.setMockMethodCallHandler(AppState.karaoke, null);
        state.dispose();
        await store.close();
      });
      await tester.pumpWidget(SingVerseApp(state: state));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();
      expect(ui.ImageFilter.isShaderFilterSupported, isTrue);
      final lenses = find
          .byWidgetPredicate(
            (widget) => widget is SingleChildRenderObjectWidget,
          )
          .evaluate()
          .map((e) => e.renderObject)
          .whereType<RenderLiquidLens>()
          .toSet()
          .length;
      expect(
        lenses,
        1,
        reason:
            'Only the floating home toolbar refracts; search, mini player '
            'and navigation use regular diffusion.',
      );
      Future<void> capture(String name) async {
        await tester.pumpAndSettle();
        debugPrint('LIBRARY_GLASS_SCREEN:$name');
        for (var i = 0; i < 65; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(tester.takeException(), isNull, reason: name);
      }

      Future<void> tap(Finder target) async {
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      final search = find.byKey(const ValueKey('song-search'));
      final mini = find.byKey(const Key('mini-player'));
      final songsTab = find.byKey(const Key('nav-songs'));
      Finder glassOf(Finder child) =>
          find.ancestor(of: child, matching: find.byType(Glass)).first;
      final navigation = glassOf(songsTab);
      final expandedNavigationWidth = tester.getSize(navigation).width;
      final searchTop = tester.getTopLeft(search).dy;
      expect(tester.getSize(search).height, closeTo(44, .1));
      expect(tester.getSize(mini).height, closeTo(56, .1));
      expect(tester.getSize(navigation).height, closeTo(56, .1));
      for (final target in [
        find.byTooltip('筛选歌曲'),
        find.byKey(const Key('open-tv')),
        find.byKey(const Key('open-settings')),
      ]) {
        expect(tester.getSize(target).width, greaterThanOrEqualTo(44));
        expect(tester.getSize(target).height, greaterThanOrEqualTo(44));
      }
      expect(tester.widget<Glass>(navigation).variant, GlassVariant.regular);
      expect(tester.widget<Glass>(glassOf(mini)).material?.refraction, isFalse);
      expect(
        find.descendant(of: songsTab, matching: find.text('点歌')),
        findsOneWidget,
      );
      await capture('01-library-light');
      await state.setTheme(ThemeMode.dark);
      await capture('02-library-dark');
      expect(Theme.of(tester.element(search)).brightness, Brightness.dark);
      await state.setTheme(ThemeMode.light);
      await tester.pumpAndSettle();
      final scroll = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(CustomScrollView).first,
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      expect(scroll.pixels, greaterThan(120));
      expect(tester.getSize(navigation).width, closeTo(144, .1));
      expect(tester.getSize(mini).height, closeTo(56, .1));
      expect(
        tester.getRect(mini).bottom,
        closeTo(tester.getRect(navigation).bottom, .1),
      );
      expect(
        find.descendant(of: songsTab, matching: find.text('点歌')),
        findsNothing,
      );
      expect(
        tester.getTopLeft(search).dy,
        closeTo(searchTop, .1),
        reason: 'Home search remains available while the feed scrolls.',
      );
      await capture('03-library-scroll');
      scroll.jumpTo(scroll.maxScrollExtent);
      await tester.pumpAndSettle();
      final last = find.byWidgetPredicate(
        (widget) => widget is SongRow && widget.song.id == '12',
      );
      expect(
        tester.getRect(last).bottom,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(const Key('mini-player'))).top,
        ),
      );
      await capture('03-library-last-song');
      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, 3000),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(navigation).width,
        closeTo(expandedNavigationWidth, .1),
      );
      expect(
        find.descendant(of: songsTab, matching: find.text('点歌')),
        findsOneWidget,
      );
      await tap(search);
      for (
        var i = 0;
        i < 30 && View.of(tester.element(search)).viewInsets.bottom == 0;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(View.of(tester.element(search)).viewInsets.bottom, greaterThan(0));
      expect(mini, findsNothing);
      expect(
        find.byKey(const Key('nav-songs')),
        findsNothing,
        reason: 'Keyboard entry hides the complete dock immediately.',
      );
      await capture('04-library-keyboard');
      // Profile mode rejects the debug-only client ID -1. Register the test
      // IME for this edit so it records the actual client, after capturing the
      // real Android keyboard; restore the real input channel immediately.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      binding.testTextInput.register();
      await tester.enterText(search, '晴天');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      binding.testTextInput.unregister();
      expect(
        api.requests.any((p) => Uri.parse(p).queryParameters['q'] == '晴天'),
        isTrue,
        reason: api.requests.join('\n'),
      );
      expect(find.text('1 首'), findsOneWidget);
      await capture('05-library-search');
      await tap(find.byTooltip('清除搜索'));
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tap(find.byTooltip('筛选歌曲'));
      await capture('06-library-filter-sheet');
      final songRequestsBeforeDraft = api.requests
          .where(
            (path) => Uri.parse(path).path == '/api/v1/mobile/library/songs',
          )
          .length;
      final language = find.byKey(const ValueKey('song-filter:lang'));
      final distant = find.byKey(const ValueKey('song-filter:scene-17'));
      await tap(language);
      final filterScrollable = find
          .descendant(
            of: find.byKey(const PageStorageKey('song-filter-options')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        distant,
        250,
        scrollable: filterScrollable,
      );
      await tester.ensureVisible(distant);
      await tester.pumpAndSettle();
      final filterScroll = tester
          .state<ScrollableState>(filterScrollable)
          .position;
      expect(filterScroll.pixels, greaterThan(0));
      final draftOffset = filterScroll.pixels;
      final distantElement = tester.element(distant);
      final chipFocus = Focus.of(
        tester.element(
          find.descendant(of: distant, matching: find.byType(Text)).first,
        ),
      );
      chipFocus.requestFocus();
      await tester.pumpAndSettle();
      await tester.tap(distant);
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(distant).selected, isTrue);
      expect(identical(tester.element(distant), distantElement), isTrue);
      expect(chipFocus.hasFocus, isTrue);
      expect(filterScroll.pixels, closeTo(draftOffset, .1));
      expect(find.text('应用筛选 (2)'), findsOneWidget);
      await capture('06-library-filter-draft-scrolled');
      await tap(find.text('取消'));
      expect(find.byType(InputChip), findsNothing);
      expect(find.text('12 首'), findsOneWidget);
      expect(
        api.requests
            .where(
              (path) => Uri.parse(path).path == '/api/v1/mobile/library/songs',
            )
            .length,
        songRequestsBeforeDraft,
        reason: 'Cancelling a draft must not submit a catalog query.',
      );
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == '筛选歌曲',
              ),
            )
            .focusNode
            ?.hasFocus,
        isTrue,
      );
      await tap(find.byTooltip('筛选歌曲'));
      expect(tester.widget<FilterChip>(language).selected, isFalse);
      await tester.scrollUntilVisible(
        distant,
        250,
        scrollable: filterScrollable,
      );
      expect(tester.widget<FilterChip>(distant).selected, isFalse);
      await tester.scrollUntilVisible(
        language,
        -250,
        scrollable: filterScrollable,
      );
      await tap(language);
      await tap(find.byKey(const ValueKey('song-filter:mood')));
      await tap(find.text('应用筛选 (2)'));
      expect(find.byType(InputChip), findsNWidgets(2));
      expect(find.text('6 首'), findsOneWidget);
      final appliedRequest = Uri.parse(
        api.requests.lastWhere(
          (path) => Uri.parse(path).path == '/api/v1/mobile/library/songs',
        ),
      );
      expect(
        appliedRequest.queryParametersAll['tagIds'],
        unorderedEquals(['lang', 'mood']),
      );
      await capture('07-library-filtered');
      await tap(find.byTooltip('筛选歌曲'));
      await tap(find.text('清除全部'));
      expect(find.text('应用筛选 (0)'), findsOneWidget);
      await tap(find.text('取消'));
      expect(find.byType(InputChip), findsNWidgets(2));
      expect(
        find.text('6 首'),
        findsOneWidget,
        reason: 'Cancelling a clear keeps the previously applied filters.',
      );
      await tap(find.text('清除筛选'));
      await tap(find.byTooltip('收藏 晴天').first);
      expect(state.isFavorite(Song(api.rows.first)), isTrue);
      await tap(find.byTooltip('继续播放'));
      expect(state.isPlaying, isTrue);
      await capture('08-library-playing');
      await tap(find.byTooltip('暂停播放'));
      expect(state.isPlaying, isFalse);
      await capture('08-library-paused');
      await tap(find.byKey(const Key('mini-player')));
      expect(find.byType(PlayerPage), findsOneWidget);
      navigator.pop();
      await tester.pumpAndSettle();
      for (final tab in ['frequent', 'works', 'songs']) {
        await tap(find.byKey(Key('nav-$tab')));
        expect(
          find.byKey(const Key('mini-player')).hitTestable(),
          findsOneWidget,
        );
        await capture('12-tab-$tab');
      }
      await tap(find.byKey(const Key('open-settings')));
      expect(find.text('设置').first, findsOneWidget);
      final performanceSwitch = find.byKey(const Key('performance-mode'));
      final transparencySwitch = find.byKey(const Key('reduce-transparency'));
      expect(tester.widget<SwitchListTile>(transparencySwitch).value, isFalse);
      expect(find.text('已关闭，使用常规透明效果'), findsOneWidget);
      await tap(transparencySwitch);
      expect(state.reduceTransparency, isTrue);
      expect(state.preferences.getBool('reduceTransparency'), isTrue);
      expect(state.performanceMode, isFalse);
      expect(tester.widget<SwitchListTile>(transparencySwitch).value, isTrue);
      expect(find.text('已开启，使用清晰的不透明背景'), findsOneWidget);
      expect(
        AppMotionScope.solidOf(tester.element(transparencySwitch)),
        isTrue,
      );
      expect(
        AppMotionScope.levelOf(tester.element(transparencySwitch)),
        isNot(AppMotionLevel.none),
        reason: 'Reducing transparency does not enable performance mode.',
      );
      await capture('16-transparency-switch-on');
      navigator.pop();
      await tester.pumpAndSettle();
      expect(
        tester.allRenderObjects.whereType<RenderBackdropFilter>(),
        isEmpty,
      );
      await tap(find.byKey(const Key('open-settings')));
      expect(tester.widget<SwitchListTile>(transparencySwitch).value, isTrue);
      await tap(transparencySwitch);
      expect(state.reduceTransparency, isFalse);
      expect(state.preferences.getBool('reduceTransparency'), isFalse);
      expect(state.performanceMode, isFalse);
      expect(tester.widget<SwitchListTile>(transparencySwitch).value, isFalse);
      expect(find.text('已关闭，使用常规透明效果'), findsOneWidget);
      await capture('17-transparency-switch-off');
      navigator.pop();
      await tester.pumpAndSettle();
      expect(
        tester.allRenderObjects.whereType<RenderBackdropFilter>(),
        isNotEmpty,
      );
      await tap(find.byKey(const Key('open-settings')));
      expect(tester.widget<SwitchListTile>(performanceSwitch).value, isFalse);
      expect(find.text('已关闭，界面效果遵循外观设置'), findsOneWidget);
      await tap(performanceSwitch);
      expect(state.performanceMode, isTrue);
      expect(state.preferences.getBool('performanceMode'), isTrue);
      expect(tester.widget<SwitchListTile>(performanceSwitch).value, isTrue);
      expect(find.text('已开启，停用动效与实时模糊'), findsOneWidget);
      expect(
        AppMotionScope.levelOf(tester.element(performanceSwitch)),
        AppMotionLevel.none,
      );
      expect(AppMotionScope.solidOf(tester.element(performanceSwitch)), isTrue);
      await capture('14-performance-switch-on');
      navigator.pop();
      await tester.pumpAndSettle();
      expect(
        tester.allRenderObjects.whereType<RenderBackdropFilter>(),
        isEmpty,
        reason: 'Turning the switch on enables the performance policy.',
      );
      await tap(find.byKey(const Key('open-settings')));
      expect(tester.widget<SwitchListTile>(performanceSwitch).value, isTrue);
      expect(find.text('已关闭，性能模式仍使用实底'), findsOneWidget);
      await tap(transparencySwitch);
      await tap(transparencySwitch);
      expect(state.reduceTransparency, isFalse);
      expect(state.preferences.getBool('reduceTransparency'), isFalse);
      expect(state.performanceMode, isTrue);
      expect(
        AppMotionScope.solidOf(tester.element(transparencySwitch)),
        isTrue,
      );
      await tap(performanceSwitch);
      expect(state.performanceMode, isFalse);
      expect(state.preferences.getBool('performanceMode'), isFalse);
      expect(tester.widget<SwitchListTile>(performanceSwitch).value, isFalse);
      expect(find.text('已关闭，界面效果遵循外观设置'), findsOneWidget);
      expect(
        AppMotionScope.levelOf(tester.element(performanceSwitch)),
        isNot(AppMotionLevel.none),
      );
      await capture('15-performance-switch-off');
      navigator.pop();
      await tester.pumpAndSettle();
      expect(
        tester.allRenderObjects.whereType<RenderBackdropFilter>(),
        isNotEmpty,
        reason: 'Turning the switch off restores the chosen appearance.',
      );
      expect(find.byKey(const Key('open-tv')).hitTestable(), findsOneWidget);

      // Warm before measuring. Recording and mirroring are stopped by the host
      // on this marker; captures are kept outside the measurement interval.
      Future<Map<String, Object>> sample(bool performance) async {
        debugPrint(
          'LIBRARY_GLASS_SAMPLE:${performance ? 'performance' : 'default'}',
        );
        await state.setPerformanceMode(performance);
        await tester.pumpAndSettle();
        final previousPolicy = binding.framePolicy;
        final arrivals = <ui.FrameTiming>[];
        final gestures = <Map<String, Object>>[];
        final clock = Stopwatch();
        final scrollView = find.byType(CustomScrollView).first;
        final scrollable = tester.state<ScrollableState>(
          find
              .descendant(of: scrollView, matching: find.byType(Scrollable))
              .first,
        );
        var started = 0;
        var finished = 0;
        var callbackInstalled = false;
        var callbackDrainComplete = false;
        void timing(List<ui.FrameTiming> values) => arrivals.addAll(values);

        Future<void> waitUntil(Duration deadline) async {
          final remaining = deadline - clock.elapsed;
          if (remaining > Duration.zero) {
            await Future<void>.delayed(remaining);
          }
        }

        Future<void> swipe(int index, {required bool record}) async {
          final gesture = await tester.createGesture();
          final downAt = clock.elapsed;
          final offsetBefore = scrollable.position.pixels;
          final moves = <int>[];
          final direction = index.isEven ? -1 : 1;
          var active = false;
          try {
            await gesture.down(tester.getCenter(scrollView), timeStamp: downAt);
            active = true;
            for (var step = 1; step <= 24; step++) {
              await waitUntil(downAt + Duration(milliseconds: step * 16));
              final eventTime = clock.elapsed;
              await gesture.moveBy(
                Offset(0, direction * 12.0),
                timeStamp: eventTime,
              );
              moves.add(eventTime.inMicroseconds);
            }
            await waitUntil(downAt + const Duration(milliseconds: 400));
            final upAt = clock.elapsed;
            await gesture.up(timeStamp: upAt);
            active = false;
            // A fixed real-time tail includes ballistic scrolling and dock
            // animation. No pump or pumpAndSettle requests measurement frames.
            await Future<void>.delayed(const Duration(milliseconds: 500));
            if (record) {
              gestures.add({
                'direction': direction,
                'downUs': downAt.inMicroseconds,
                'moveUs': moves,
                'upUs': upAt.inMicroseconds,
                'scrollBeforePx': offsetBefore,
                'scrollAfterPx': scrollable.position.pixels,
              });
            }
          } finally {
            if (active) await gesture.cancel(timeStamp: clock.elapsed);
          }
        }

        try {
          binding.framePolicy =
              LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive;
          clock.start();
          for (var i = 0; i < 4; i++) {
            await swipe(i, record: false);
          }
          scrollable.position.jumpTo(scrollable.position.minScrollExtent);
          await Future<void>.delayed(const Duration(milliseconds: 500));
          binding.addTimingsCallback(timing);
          callbackInstalled = true;
          // Frame timestamps use Timeline's monotonic clock; input timestamps
          // use elapsed real time from the same measurement's zero-based t0.
          started = developer.Timeline.now;
          clock.reset();
          for (var i = 0; i < 8; i++) {
            await swipe(i, record: true);
          }
          finished = developer.Timeline.now;
          // Profile timings arrive in batches (normally about 100ms). Keep
          // collecting until a later frame confirms the window was drained.
          final drainDeadline = clock.elapsed + const Duration(seconds: 2);
          do {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            callbackDrainComplete = arrivals.any(
              (frame) =>
                  frame.timestampInMicroseconds(ui.FramePhase.vsyncStart) >=
                  finished,
            );
          } while (!callbackDrainComplete && clock.elapsed < drainDeadline);
        } finally {
          if (callbackInstalled) binding.removeTimingsCallback(timing);
          binding.framePolicy = previousPolicy;
          clock.stop();
        }
        // Select only by the explicit time window, never by frame duration.
        // Every selected frame, including every slow frame, is saved below.
        final frames = arrivals.where((frame) {
          final vsync = frame.timestampInMicroseconds(ui.FramePhase.vsyncStart);
          return vsync >= started && vsync < finished;
        }).toList();
        expect(
          callbackDrainComplete,
          isTrue,
          reason: 'A later timing batch must confirm the whole window arrived.',
        );
        expect(frames.length, greaterThanOrEqualTo(100));
        double p95(List<double> values) {
          values.sort();
          return values[((values.length - 1) * .95).ceil()];
        }

        final overBudget = frames
            .where(
              (frame) =>
                  frame.buildDuration.inMicroseconds > 16667 ||
                  frame.rasterDuration.inMicroseconds > 16667,
            )
            .length;
        return {
          'mode': performance ? 'performance' : 'default',
          'method': 'wall-clock-gesture-v2',
          'framePolicy': 'benchmarkLive',
          'sampleWindowUs': finished - started,
          'frameSelection':
              'all vsync starts in the window; no duration filter',
          'referenceFrameBudgetUs': 16667,
          'displayRefreshRateHz': tester.view.display.refreshRate,
          'callbackDrainComplete': callbackDrainComplete,
          'gesturePlan': {
            'warmupSwipes': 4,
            'measuredSwipes': 8,
            'moveEventsPerSwipe': 24,
            'moveIntervalMs': 16,
            'distancePerSwipePx': 288,
            'upAtMs': 400,
            'settleAfterUpMs': 500,
          },
          'gestures': gestures,
          'frames': frames.length,
          'uiP95Ms': p95(
            frames.map((f) => f.buildDuration.inMicroseconds / 1000).toList(),
          ),
          'rasterP95Ms': p95(
            frames.map((f) => f.rasterDuration.inMicroseconds / 1000).toList(),
          ),
          'uiMaxMs': frames
              .map((f) => f.buildDuration.inMicroseconds / 1000)
              .reduce((a, b) => a > b ? a : b),
          'rasterMaxMs': frames
              .map((f) => f.rasterDuration.inMicroseconds / 1000)
              .reduce((a, b) => a > b ? a : b),
          'overBudgetFrames': overBudget,
          'overBudgetPercent': overBudget / frames.length * 100,
          'frameTimings': [
            for (final frame in frames)
              {
                for (final phase in [
                  ui.FramePhase.vsyncStart,
                  ui.FramePhase.buildStart,
                  ui.FramePhase.buildFinish,
                  ui.FramePhase.rasterStart,
                  ui.FramePhase.rasterFinish,
                ])
                  phase.name: frame.timestampInMicroseconds(phase) - started,
                'uiUs': frame.buildDuration.inMicroseconds,
                'rasterUs': frame.rasterDuration.inMicroseconds,
                'totalSpanUs': frame.totalSpan.inMicroseconds,
              },
          ],
        };
      }

      final timings = [await sample(false), await sample(true)];
      expect(
        tester.allRenderObjects.whereType<RenderBackdropFilter>(),
        isEmpty,
      );
      await capture('09-library-performance');
      await state.setPerformanceMode(false);
      await state.setTransparency(true);
      await tester.pumpAndSettle();
      expect(
        tester.allRenderObjects.whereType<RenderBackdropFilter>(),
        isEmpty,
      );
      await capture('10-library-opaque');
      expect(tester.getSize(search).height, closeTo(44, .1));
      await state.setTransparency(false);
      await state.setUiMode(UiMode.senior);
      await tester.pumpAndSettle();
      expect(find.byType(SongSpotlight), findsNothing);
      expect(tester.getSize(mini).height, greaterThanOrEqualTo(72));
      expect(tester.getSize(navigation).height, greaterThanOrEqualTo(72));
      final seniorNavigationWidth = tester.getSize(navigation).width;
      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, -250),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(navigation).width,
        closeTo(seniorNavigationWidth, .1),
      );
      expect(
        find.descendant(of: songsTab, matching: find.text('点歌')),
        findsOneWidget,
      );
      expect(
        tester.allRenderObjects.whereType<RenderBackdropFilter>(),
        isEmpty,
      );
      await capture('13-library-senior');
      await state.setUiMode(UiMode.standard);
      await tester.pumpAndSettle();
      state.authenticated = false;
      navigator.push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'connection'),
          builder: (_) => ConnectionPage(state: state),
        ),
      );
      await capture('11-shared-nas');
      expect(find.byKey(const ValueKey('nas-address-field')), findsOneWidget);
      expect(state.positionMs, 30000);
      expect(commands.where((c) => c == 'play').length, 1);
      expect(commands.where((c) => c == 'pause').length, 1);
      binding.reportData = {
        'renderer': 'Impeller',
        'shaderLenses': lenses,
        'materialPolicy':
            'one floating toolbar lens; regular search, navigation '
            'and mini player; solid transparency/performance/senior modes',
        'behaviorChecks': [
          '44px search and actions; 56px mini player and navigation',
          'real scrolling collapses and expands the dock; pinned search stays visible',
          'real Android keyboard hides mini player and navigation',
          'filter draft preserves scroll, focus and element identity',
          'filter cancel and cancelled clear do not change applied criteria',
          'performance switch on enables and saves the policy; off restores appearance',
          'transparency switch on makes materials solid without disabling motion; performance still overrides off',
          'light, dark, opaque, performance and senior modes',
        ],
        'data': 'isolated catalog and method-channel fixtures; no real NAS, microphone or audio calls',
        'commands': commands,
        'timings': timings,
      };
    },
  );
}
