import 'dart:ui' as ui;
import 'dart:developer' as developer;

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
import 'package:singverse_mobile/main.dart';

import '../test/widget_test.dart' show FakeApi;

class _EmptyVault implements LoginStore {
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
  testWidgets('NAS optical glass renders on Impeller and remains interruptible', (
    tester,
  ) async {
    // Controlled UI data, an in-memory database and preferences: no daily NAS,
    // native playback, microphone, or user's credentials are touched.
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open(path: ':memory:');
    await tester.runAsync(
      () => ui.FragmentProgram.fromAsset('shaders/liquid_lens.frag'),
    );
    final state =
        AppState(
            api: FakeApi(),
            store: store,
            preferences: await SharedPreferences.getInstance(),
            loginStore: _EmptyVault(),
            listenPlayer: false,
          )
          ..initialized = true
          ..origin = 'http://nas.local:18080'
          ..themeMode = ThemeMode.light
          ..current = Song({'id': 'optical-preview', 'title': 'All Night'})
          ..playbackState = 'PAUSED'
          ..positionMs = 30000
          ..durationMs = 240000;
    addTearDown(() async {
      state.dispose();
      await store.close();
    });
    await tester.pumpWidget(SingVerseApp(state: state));
    await tester.pumpAndSettle();
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    navigator.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'connection'),
        builder: (_) => ConnectionPage(state: state),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    expect(
      ui.ImageFilter.isShaderFilterSupported,
      isTrue,
      reason: 'Run on Impeller to validate real backdrop refraction.',
    );
    final lenses = find
        .byWidgetPredicate((widget) => widget is SingleChildRenderObjectWidget)
        .evaluate()
        .map((element) => element.renderObject)
        .whereType<RenderLiquidLens>()
        .toSet()
        .length;
    expect(
      lenses,
      greaterThanOrEqualTo(3),
      reason:
          'Back button, selected segment, and player must use the real shader.',
    );
    await tester.pumpAndSettle();
    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      debugPrint('NAS_GLASS_SCREEN:$name');
      // Host adb captures the real display; no Android ImageView conversion.
      for (var i = 0; i < 65; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    await capture('01-nas-light');
    await state.setTheme(ThemeMode.dark);
    await capture('02-nas-dark');
    await state.setTheme(ThemeMode.light);
    await tester.pumpAndSettle();
    final username = find.byKey(const ValueKey('nas-username-field'));
    await tester.tap(username);
    await tester.pumpAndSettle();
    await capture('03-nas-focus-keyboard');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    Future<Map<String, Object>> sample(bool performance) async {
      debugPrint('NAS_GLASS_SAMPLE:${performance ? 'performance' : 'default'}');
      await state.setPerformanceMode(performance);
      await tester.pumpAndSettle();
      final frames = <ui.FrameTiming>[];
      var started = 0;
      void timing(List<ui.FrameTiming> values) => frames.addAll(
        values.where(
          (frame) =>
              frame.timestampInMicroseconds(ui.FramePhase.buildStart) >=
              started,
        ),
      );
      // Warm the segment, rim and shader pipelines before collecting timings.
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.text(i.isEven ? 'HTTPS' : 'HTTP'));
        await tester.pumpAndSettle();
      }
      started = developer.Timeline.now;
      binding.addTimingsCallback(timing);
      try {
        for (var i = 0; i < 24; i++) {
          await tester.tap(find.text(i.isEven ? 'HTTPS' : 'HTTP'));
          await tester.pump(const Duration(milliseconds: 48));
        }
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        });
      } finally {
        binding.removeTimingsCallback(timing);
      }
      double p95(List<double> values) {
        if (values.isEmpty) return 0;
        values.sort();
        return values[((values.length - 1) * .95).ceil()];
      }

      expect(frames, isNotEmpty);
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
    expect(find.byType(BackdropFilter), findsNothing);
    expect(tester.allRenderObjects.whereType<RenderBackdropFilter>(), isEmpty);
    await capture('04-nas-performance');
    await state.setPerformanceMode(false);
    await state.setTransparency(true);
    await capture('05-nas-reduce-transparency');
    expect(tester.allRenderObjects.whereType<RenderBackdropFilter>(), isEmpty);
    await state.setTransparency(false);
    await tester.pumpAndSettle();
    // Change policy while the sliding selection and focus sheen are in flight.
    await tester.tap(find.text('HTTPS'));
    await tester.pump(const Duration(milliseconds: 40));
    await state.setPerformanceMode(true);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AppSegments<String>>(
            find.byKey(const ValueKey('nas-protocol')),
          )
          .selected,
      'https',
    );
    expect(tester.allRenderObjects.whereType<RenderBackdropFilter>(), isEmpty);
    await state.setPerformanceMode(false);
    await tester.tap(find.text('HTTP'));
    await capture('06-nas-final');
    expect(state.current?.id, 'optical-preview');
    expect(state.positionMs, 30000);
    expect(state.origin, 'http://nas.local:18080');
    expect(tester.takeException(), isNull);
    binding.reportData = {
      'renderer': 'Impeller',
      'shaderLenses': lenses,
      'data': 'controlled fixture; no NAS or native playback calls',
      'timings': timings,
    };
  });
}
