import 'dart:ui' as ui;
import 'dart:developer' as developer;

import 'package:fluid_glass/fluid_glass.dart' show DrawBackdrop, FluidGlass;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:singverse_mobile/app/design.dart';
import 'package:singverse_mobile/core/app_state.dart';
import 'package:singverse_mobile/core/local_store.dart';
import 'package:singverse_mobile/core/login_store.dart';
import 'package:singverse_mobile/core/models.dart';
import 'package:singverse_mobile/features/library/connection.dart';
import 'package:singverse_mobile/main.dart';

import '../test/widget_test.dart' show FakeApi;

import 'phone_failure_reporter.dart';

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
  installPhoneFailureReporter(binding);
  testWidgets('NAS optical glass renders on Impeller and remains interruptible', (
    tester,
  ) async {
    // Controlled UI data, an in-memory database and preferences: no daily NAS,
    // native playback, microphone, or user's credentials are touched.
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open(path: ':memory:');
    await tester.runAsync(FluidGlass.ensureInitialized);
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
    final lenses = find.byType(DrawBackdrop).evaluate().length;
    expect(lenses, greaterThanOrEqualTo(1));
    final username = find.byKey(const ValueKey('nas-username-field'));
    final address = find.byKey(const ValueKey('nas-address-field'));
    final mini = find.byKey(const Key('mini-player'));
    final protocol = find.byKey(const ValueKey('nas-protocol'));
    expect(tester.widget<AppSegments<String>>(protocol).liquid, isFalse);
    for (final field in [
      address,
      username,
      find.byKey(const ValueKey('nas-password-field')),
    ]) {
      final decoration = tester.widget<TextField>(field).decoration!;
      expect(decoration.filled, isTrue);
      expect(
        decoration.fillColor,
        Theme.of(tester.element(field)).colorScheme.surface,
      );
      expect(
        find.ancestor(of: field, matching: find.byType(GlassField)),
        findsNothing,
      );
      expect(tester.getSize(field).height, closeTo(52, .1));
    }
    expect(tester.getSize(mini).height, closeTo(56, .1));
    final miniGlass = find
        .ancestor(of: mini, matching: find.byType(Glass))
        .first;
    expect(tester.widget<Glass>(miniGlass).material?.refraction, isFalse);
    await tester.pumpAndSettle();
    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      debugPrint('NAS_GLASS_SCREEN:$name');
      // Host adb captures the real display; no Android ImageView conversion.
      for (var i = 0; i < 65; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.takeException(), isNull, reason: name);
    }

    await capture('01-nas-light');
    await state.setTheme(ThemeMode.dark);
    await capture('02-nas-dark');
    expect(Theme.of(tester.element(username)).brightness, Brightness.dark);
    expect(
      tester.widget<TextField>(username).decoration!.fillColor,
      Theme.of(tester.element(username)).colorScheme.surface,
    );
    await state.setTheme(ThemeMode.light);
    await tester.pumpAndSettle();
    await tester.tap(username);
    await tester.pumpAndSettle();
    for (
      var i = 0;
      i < 30 && View.of(tester.element(username)).viewInsets.bottom == 0;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(View.of(tester.element(username)).viewInsets.bottom, greaterThan(0));
    expect(
      tester
          .widget<EditableText>(
            find.descendant(of: username, matching: find.byType(EditableText)),
          )
          .focusNode
          .hasFocus,
      isTrue,
    );
    expect(
      tester
          .widget<TextField>(username)
          .decoration!
          .focusedBorder!
          .borderSide
          .color,
      Theme.of(tester.element(username)).colorScheme.primary,
    );
    expect(
      mini,
      findsNothing,
      reason: 'The real Android keyboard hides the shared mini player.',
    );
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
    expect(tester.getSize(username).height, closeTo(52, .1));
    await state.setTransparency(false);
    await state.setUiMode(UiMode.senior);
    await tester.pumpAndSettle();
    expect(tester.widget<AppSegments<String>>(protocol).senior, isTrue);
    expect(tester.getSize(username).height, greaterThanOrEqualTo(64));
    expect(tester.getSize(mini).height, greaterThanOrEqualTo(72));
    expect(
      tester.getSize(find.byType(BackButton)).height,
      greaterThanOrEqualTo(56),
    );
    expect(tester.allRenderObjects.whereType<RenderBackdropFilter>(), isEmpty);
    await capture('07-nas-senior');
    await state.setUiMode(UiMode.standard);
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
      'materialPolicy':
          'one floating back lens; neutral account fields and '
          'protocol control; regular 56px mini player',
      'behaviorChecks': [
        '52px neutral fields with visible focus border',
        'real Android keyboard hides the shared mini player',
        'light, dark, opaque, performance and senior modes',
        'protocol selection survives a policy change during animation',
      ],
      'data': 'controlled fixture; no NAS or native playback calls',
      'timings': timings,
    };
  });
}
