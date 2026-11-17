import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
      expect(lenses, greaterThanOrEqualTo(3));
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
      await capture('01-library-light');
      await state.setTheme(ThemeMode.dark);
      await capture('02-library-dark');
      await state.setTheme(ThemeMode.light);
      await tester.pumpAndSettle();
      final scroll = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      scroll.jumpTo(scroll.maxScrollExtent * .45);
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
      final search = find.byKey(const ValueKey('song-search'));
      await tap(search);
      for (
        var i = 0;
        i < 30 && View.of(tester.element(search)).viewInsets.bottom == 0;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(View.of(tester.element(search)).viewInsets.bottom, greaterThan(0));
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
      expect(find.text('1 首歌曲'), findsOneWidget);
      await capture('05-library-search');
      await tap(find.byTooltip('清除搜索'));
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tap(find.byTooltip('筛选歌曲'));
      await capture('06-library-filter-sheet');
      await tap(find.text('国语 · 6'));
      await tap(find.text('应用筛选 (1)'));
      expect(find.text('6 首歌曲'), findsOneWidget);
      await capture('07-library-filtered');
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
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('open-tv')).hitTestable(), findsOneWidget);

      // Warm before measuring. Recording and mirroring are stopped by the host
      // on this marker; captures are kept outside the measurement interval.
      debugPrint('LIBRARY_GLASS_SAMPLE:default');
      Future<Map<String, Object>> sample(bool performance) async {
        await state.setPerformanceMode(performance);
        await tester.pumpAndSettle();
        for (var i = 0; i < 4; i++) {
          await tester.drag(
            find.byType(CustomScrollView).first,
            Offset(0, i.isEven ? -250 : 250),
          );
          await tester.pumpAndSettle();
        }
        final frames = <ui.FrameTiming>[];
        final started = developer.Timeline.now;
        void timing(List<ui.FrameTiming> values) => frames.addAll(
          values.where(
            (f) =>
                f.timestampInMicroseconds(ui.FramePhase.buildStart) >= started,
          ),
        );
        binding.addTimingsCallback(timing);
        try {
          for (var i = 0; i < 8; i++) {
            final gesture = await tester.startGesture(
              tester.getCenter(find.byType(CustomScrollView).first),
            );
            for (var step = 0; step < 24; step++) {
              await gesture.moveBy(Offset(0, i.isEven ? -12 : 12));
              await tester.pump(const Duration(milliseconds: 16));
            }
            await gesture.up();
            await tester.pumpAndSettle();
          }
          await tester.runAsync(
            () async => Future<void>.delayed(const Duration(milliseconds: 250)),
          );
        } finally {
          binding.removeTimingsCallback(timing);
        }
        expect(frames.length, greaterThanOrEqualTo(100));
        double p95(List<double> values) {
          values.sort();
          return values[((values.length - 1) * .95).ceil()];
        }

        return {
          'mode': performance ? 'performance' : 'default',
          'frames': frames.length,
          'uiP95Ms': p95(
            frames.map((f) => f.buildDuration.inMicroseconds / 1000).toList(),
          ),
          'rasterP95Ms': p95(
            frames.map((f) => f.rasterDuration.inMicroseconds / 1000).toList(),
          ),
          'overBudgetPercent':
              frames
                  .where(
                    (f) =>
                        f.buildDuration.inMicroseconds > 16667 ||
                        f.rasterDuration.inMicroseconds > 16667,
                  )
                  .length /
              frames.length *
              100,
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
      expect(
        tester.allRenderObjects.whereType<RenderBackdropFilter>(),
        isEmpty,
      );
      await capture('10-library-opaque');
      await state.setTransparency(false);
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
        'data': 'isolated catalog and method-channel fixtures; no real NAS, microphone or audio calls',
        'commands': commands,
        'timings': timings,
      };
    },
  );
}
