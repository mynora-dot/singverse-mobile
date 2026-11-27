import 'dart:ui' show Tristate;
import 'dart:ui' as ui;

import 'package:fluid_glass/fluid_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:singverse_mobile/app/design.dart';
import 'package:singverse_mobile/core/app_state.dart';
import 'package:singverse_mobile/core/local_store.dart';

import 'widget_test.dart' show FakeApi;

typedef Policy = ({bool performance, bool reduce, bool senior, bool solid});
const full = (performance: false, reduce: false, senior: false, solid: false);

class MotionTestApp extends StatelessWidget {
  const MotionTestApp({super.key, required this.policy, required this.home});
  final ValueNotifier<Policy> policy;
  final Widget home;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Policy>(
    valueListenable: policy,
    builder: (context, value, _) => MaterialApp(
      theme: singVerseTheme(Brightness.light),
      builder: (context, child) => AppMotionScope(
        performanceMode: value.performance,
        senior: value.senior,
        reduceTransparency: value.solid,
        child: MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: value.reduce),
          child: child!,
        ),
      ),
      home: home,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'floating fallback quiets backdrop detail without tinting controls',
    (tester) async {
      final boundary = GlobalKey();
      for (final brightness in [Brightness.light, Brightness.dark]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: singVerseTheme(brightness),
            home: Center(
              child: RepaintBoundary(
                key: boundary,
                child: SizedBox(
                  width: 200,
                  height: 100,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Row(
                        children: const [
                          Expanded(child: ColoredBox(color: Colors.black)),
                          Expanded(child: ColoredBox(color: Colors.white)),
                        ],
                      ),
                      const GlassSurface(
                        variant: GlassVariant.liquid,
                        child: Center(
                          child: SizedBox(
                            width: 12,
                            height: 12,
                            child: ColoredBox(color: AppPalette.brand),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final bytes = await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          try {
            return await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          } finally {
            image.dispose();
          }
        });
        Color pixel(int x) {
          final offset = (50 * 200 + x) * 4;
          return Color.fromARGB(
            bytes!.getUint8(offset + 3),
            bytes.getUint8(offset),
            bytes.getUint8(offset + 1),
            bytes.getUint8(offset + 2),
          );
        }

        final left = pixel(50).computeLuminance();
        final right = pixel(150).computeLuminance();
        final contrast =
            ((left > right ? left : right) + .05) /
            ((left < right ? left : right) + .05);
        expect(contrast, inInclusiveRange(1, 1.5), reason: '$brightness');
        expect(pixel(100), AppPalette.brand);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'native view routes use stable opaque sheets and unsampled dialog backdrops',
    (tester) async {
      final policy = ValueNotifier<Policy>(full);
      addTearDown(policy.dispose);
      await tester.pumpWidget(
        MotionTestApp(
          policy: policy,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    settings: const RouteSettings(name: 'admin'),
                    builder: (context) => Scaffold(
                      body: Column(
                        children: [
                          TextButton(
                            onPressed: () => showAppDialog<void>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('确认操作'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('取消'),
                                  ),
                                ],
                              ),
                            ),
                            child: const Text('打开对话框'),
                          ),
                          TextButton(
                            onPressed: () => showAppSheet<void>(
                              context: context,
                              builder: (context) => TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('关闭面板'),
                              ),
                            ),
                            child: const Text('打开面板'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                child: const Text('管理端'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('管理端'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开对话框'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<BackdropFilter>(find.byType(BackdropFilter))
            .where((filter) => filter.enabled),
        isEmpty,
      );
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开面板'));
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNothing);
      await tester.tap(find.text('关闭面板'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'rapid segment reversals keep the latest selection and one call per tap',
    (tester) async {
      final policy = ValueNotifier<Policy>(full);
      addTearDown(policy.dispose);
      var selected = 0, calls = 0;
      await tester.pumpWidget(
        MotionTestApp(
          policy: policy,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => AppSegments<int>(
                liquid: true,
                values: const [(0, '收藏'), (1, '最近练唱')],
                selected: selected,
                onChanged: (value) {
                  calls++;
                  update(() => selected = value);
                },
              ),
            ),
          ),
        ),
      );
      final semantics = tester.ensureSemantics();
      try {
        for (final label in ['最近练唱', '收藏', '最近练唱']) {
          await tester.tap(find.text(label));
          await tester.pump(const Duration(milliseconds: 40));
        }
        await tester.pumpAndSettle();
        expect(selected, 1);
        expect(calls, 3);
        expect(
          tester
              .getSemantics(find.text('最近练唱'))
              .getSemanticsData()
              .flagsCollection
              .isSelected,
          Tristate.isTrue,
        );
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'press feedback keeps the target stable and disabled buttons cannot act',
    (tester) async {
      final policy = ValueNotifier<Policy>(full);
      addTearDown(policy.dispose);
      var calls = 0;
      await tester.pumpWidget(
        MotionTestApp(
          policy: policy,
          home: Scaffold(
            body: Column(
              children: [
                FilledButton(
                  key: const Key('enabled'),
                  onPressed: () => calls++,
                  child: const Text('播放'),
                ),
                const FilledButton(
                  key: Key('disabled'),
                  onPressed: null,
                  child: Text('录音暂不可用'),
                ),
              ],
            ),
          ),
        ),
      );
      final button = find.byKey(const Key('enabled'));
      final bounds = tester.getRect(button);
      final gesture = await tester.startGesture(bounds.center);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getRect(button), bounds);
      expect(calls, 0);
      policy.value = (
        performance: true,
        reduce: false,
        senior: false,
        solid: false,
      );
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(calls, 1);
      await tester.tap(find.byKey(const Key('disabled')));
      expect(calls, 1);
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'floating accessory reverses and stops immediately in performance mode',
    (tester) async {
      final policy = ValueNotifier<Policy>(full);
      final shown = ValueNotifier(false);
      addTearDown(policy.dispose);
      addTearDown(shown.dispose);
      var calls = 0;
      await tester.pumpWidget(
        MotionTestApp(
          policy: policy,
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: shown,
              builder: (context, visible, _) => Column(
                children: [
                  const Expanded(child: Text('表单')),
                  MotionVisibility(
                    visible: visible,
                    child: FilledButton(
                      onPressed: () => calls++,
                      child: const Text('浮动播放器'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('浮动播放器'), findsNothing);
      shown.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      shown.value = false;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(find.text('浮动播放器').hitTestable(), findsNothing);
      expect(calls, 0);
      shown.value = true;
      await tester.pumpAndSettle();
      await tester.tap(find.text('浮动播放器'));
      expect(calls, 1);
      shown.value = false;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      policy.value = (
        performance: true,
        reduce: false,
        senior: false,
        solid: false,
      );
      await tester.pump();
      expect(find.text('浮动播放器'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reduced motion fades a floating accessory without changing its geometry',
    (tester) async {
      final policy = ValueNotifier<Policy>((
        performance: false,
        reduce: true,
        senior: false,
        solid: false,
      ));
      final shown = ValueNotifier(false);
      addTearDown(policy.dispose);
      addTearDown(shown.dispose);
      await tester.pumpWidget(
        MotionTestApp(
          policy: policy,
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: shown,
              builder: (context, visible, _) => MotionVisibility(
                visible: visible,
                child: const SizedBox(
                  key: Key('accessory'),
                  width: 240,
                  height: 72,
                ),
              ),
            ),
          ),
        ),
      );
      shown.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      final bounds = tester.getRect(find.byKey(const Key('accessory')));
      expect(find.byType(SizeTransition), findsNothing);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(const Key('accessory'))), bounds);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reduce motion cancels entrance and displacement while retaining transparency preference',
    (tester) async {
      final policy = ValueNotifier<Policy>(full);
      addTearDown(policy.dispose);
      await tester.pumpWidget(
        MotionTestApp(
          policy: policy,
          home: Scaffold(
            body: Column(
              children: [
                const GlassSurface(
                  variant: GlassVariant.control,
                  child: SizedBox(width: 200, height: 64),
                ),
                const MotionEntrance(index: 5, child: Text('歌曲内容')),
                AppSegments<int>(
                  values: const [(0, '收藏'), (1, '最近')],
                  selected: 0,
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 40));
      policy.value = (
        performance: false,
        reduce: true,
        senior: false,
        solid: false,
      );
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsOneWidget);
      final entranceOpacity = tester.widget<Opacity>(
        find.descendant(
          of: find.byType(MotionEntrance),
          matching: find.byType(Opacity),
        ),
      );
      expect(entranceOpacity.opacity, 1);
      expect(
        tester.widget<AnimatedAlign>(find.byType(AnimatedAlign)).duration,
        Duration.zero,
      );
      policy.value = (
        performance: false,
        reduce: false,
        senior: true,
        solid: false,
      );
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('performance mode immediately settles a dialog and its barrier', (
    tester,
  ) async {
    final policy = ValueNotifier<Policy>(full);
    addTearDown(policy.dispose);
    ModalRoute<void>? dialog;
    var completions = 0;
    await tester.pumpWidget(
      MotionTestApp(
        policy: policy,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                await showAppDialog<void>(
                  context: context,
                  builder: (context) {
                    dialog = ModalRoute.of<void>(context);
                    return AlertDialog(
                      title: const Text('正在进入'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('取消'),
                        ),
                      ],
                    );
                  },
                );
                completions++;
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(dialog!.animation!.value, lessThan(1));
    policy.value = (
      performance: true,
      reduce: false,
      senior: false,
      solid: false,
    );
    await tester.pump();
    await tester.pump();
    expect(dialog!.animation!.value, 1);
    expect(
      tester
          .widgetList<BackdropFilter>(find.byType(BackdropFilter))
          .where((filter) => filter.enabled),
      isEmpty,
    );
    await tester.tap(find.text('取消'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);
    expect(completions, 1);
    expect(find.text('打开').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'performance mode settles a running sheet and cancellation removes its barrier',
    (tester) async {
      final policy = ValueNotifier<Policy>(full);
      addTearDown(policy.dispose);
      var dismissed = 0, committed = 0;
      await tester.pumpWidget(
        MotionTestApp(
          policy: policy,
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () async {
                  final result = await showAppSheet<bool>(
                    context: context,
                    builder: (context) => SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('确认'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                  dismissed++;
                  if (result == true) committed++;
                },
                child: const Text('打开弹层'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开弹层'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      policy.value = (
        performance: true,
        reduce: false,
        senior: false,
        solid: false,
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(BackdropFilter), findsNothing);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(dismissed, 1);
      expect(committed, 0);
      expect(
        find.byWidgetPredicate((w) => w is ModalBarrier && w.dismissible),
        findsNothing,
      );
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('打开弹层').hitTestable(), findsOneWidget);
      // Reopening and dragging still cancels normally with full motion.
      policy.value = full;
      await tester.pump();
      await tester.tap(find.text('打开弹层'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(BottomSheet), const Offset(0, 500));
      await tester.pumpAndSettle();
      expect(dismissed, 2);
      expect(committed, 0);
      expect(
        find.byWidgetPredicate((w) => w is ModalBarrier && w.dismissible),
        findsNothing,
      );
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'back during page and dialog entrance leaves no overlay or duplicate completion',
    (tester) async {
      final policy = ValueNotifier<Policy>(full);
      addTearDown(policy.dispose);
      var dismissed = 0;
      await tester.pumpWidget(
        MotionTestApp(
          policy: policy,
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const Scaffold(body: Text('详情内容')),
                      ),
                    ),
                    child: const Text('查看详情'),
                  ),
                  TextButton(
                    onPressed: () async {
                      await showAppDialog<void>(
                        context: context,
                        builder: (_) => const AlertDialog(title: Text('确认操作')),
                      );
                      dismissed++;
                    },
                    child: const Text('打开对话框'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('查看详情'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('查看详情').hitTestable(), findsOneWidget);
      await tester.tap(find.text('打开对话框'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(dismissed, 1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.byWidgetPredicate((w) => w is ModalBarrier && w.dismissible),
        findsNothing,
      );
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'first six entrances wait for visibility and never replay after disposal',
    (tester) async {
      final policy = ValueNotifier<Policy>(full);
      final visible = ValueNotifier(true);
      final active = ValueNotifier(false);
      final bucket = PageStorageBucket();
      addTearDown(policy.dispose);
      addTearDown(visible.dispose);
      addTearDown(active.dispose);
      await tester.pumpWidget(
        MotionTestApp(
          policy: policy,
          home: Scaffold(
            body: PageStorage(
              bucket: bucket,
              child: ValueListenableBuilder<bool>(
                valueListenable: visible,
                builder: (_, value, _) => value
                    ? ValueListenableBuilder<bool>(
                        valueListenable: active,
                        builder: (_, enabled, _) => TickerMode(
                          enabled: enabled,
                          child: const MotionEntrance(
                            key: ValueKey('song:a'),
                            child: Text('第一次入场'),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      );
      final entrance = find.descendant(
        of: find.byType(MotionEntrance),
        matching: find.byType(Opacity),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(tester.widget<Opacity>(entrance).opacity, 0);
      active.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.widget<Opacity>(entrance).opacity, inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      visible.value = false;
      await tester.pump();
      visible.value = true;
      await tester.pump();
      final opacity = tester.widget<Opacity>(
        find.descendant(
          of: find.byType(MotionEntrance),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, 1);
      expect(tester.binding.hasScheduledFrame, isFalse);
    },
  );

  test(
    'liquidGlass defaults to enabled and persists unified off/on toggle',
    () async {
      sqfliteFfiInit();
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open(
        factory: databaseFactoryFfiNoIsolate,
        path: inMemoryDatabasePath,
      );
      final prefs = await SharedPreferences.getInstance();
      final state = AppState(
        api: FakeApi(),
        store: store,
        preferences: prefs,
        listenPlayer: false,
      );
      expect(state.liquidGlass, isTrue);
      expect(state.reduceTransparency, isFalse);
      expect(state.performanceMode, isFalse);

      await state.setLiquidGlass(false);
      expect(state.liquidGlass, isFalse);
      expect(state.reduceTransparency, isTrue);
      expect(state.performanceMode, isTrue);

      final restored = AppState(
        api: FakeApi(),
        store: store,
        preferences: prefs,
        listenPlayer: false,
      );
      expect(restored.liquidGlass, isFalse);
      expect(restored.reduceTransparency, isTrue);
      expect(restored.performanceMode, isTrue);

      await restored.setLiquidGlass(true);
      expect(restored.liquidGlass, isTrue);
      expect(restored.reduceTransparency, isFalse);
      expect(restored.performanceMode, isFalse);

      state.dispose();
      restored.dispose();
      await store.close();
    },
  );

  test('performance preference persists without changing theme transparency or media clocks', () async {
    sqfliteFfiInit();
    SharedPreferences.setMockInitialValues({
      'theme': ThemeMode.dark.index,
      'reduceTransparency': true,
      'uiMode': 'senior',
    });
    final store = await LocalStore.open(
      factory: databaseFactoryFfiNoIsolate,
      path: inMemoryDatabasePath,
    );
    final prefs = await SharedPreferences.getInstance();
    final state = AppState(
      api: FakeApi(),
      store: store,
      preferences: prefs,
      listenPlayer: false,
    );
    state.positionMs = 12345;
    expect(state.performanceMode, isFalse);
    var notified = false;
    state.addListener(() => notified = true);
    final saving = state.setPerformanceMode(true);
    expect(notified, isTrue);
    await saving;
    final restored = AppState(
      api: FakeApi(),
      store: store,
      preferences: prefs,
      listenPlayer: false,
    );
    expect(restored.performanceMode, isTrue);
    await state.setPerformanceMode(false);
    expect(state.themeMode, ThemeMode.dark);
    expect(state.reduceTransparency, isTrue);
    expect(state.senior, isTrue);
    expect(state.positionMs, 12345);
    state.dispose();
    restored.dispose();
    await store.close();
  });

  testWidgets(
    'fluid_glass initializes, mounts DrawBackdrop in scope, and skips on solid',
    (tester) async {
      await tester.runAsync(FluidGlass.ensureInitialized);

      expect(GlassMaterialSpec.floating.refraction, isTrue);
      expect(GlassMaterialSpec.player.refraction, isTrue);
      expect(GlassMaterialSpec.search.refraction, isTrue);
      expect(GlassMaterialSpec.shortcut.refraction, isTrue);
      expect(GlassMaterialSpec.standard.refraction, isTrue);
      expect(GlassMaterialSpec.field.refraction, isTrue);
      expect(GlassMaterialSpec.sheet.refraction, isTrue);
      expect(GlassMaterialSpec.mediaOverlay.refraction, isFalse);
      expect(GlassMaterialSpec.sheetNative.refraction, isFalse);
      expect(GlassMaterialSpec.standard.sampleContent, isFalse);
      expect(GlassMaterialSpec.floating.sampleContent, isTrue);
      expect(GlassMaterialSpec.sheet.sampleContent, isTrue);
      expect(
        AppSurfaces.forBrightness(Brightness.dark).glass,
        const Color(0xFF1B1B22),
      );

      final boundary = GlobalKey();
      for (final brightness in [Brightness.light, Brightness.dark]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: singVerseTheme(brightness),
            home: Center(
              child: RepaintBoundary(
                key: boundary,
                child: SizedBox(
                  width: 200,
                  height: 100,
                  child: AppBackdropCapture(
                    builder: (context, layerBackdrop) => Stack(
                      fit: StackFit.expand,
                      children: [
                        AppBackdropSource(
                          backdrop: layerBackdrop,
                          child: Row(
                            children: const [
                              Expanded(
                                child: ColoredBox(color: Color(0xFFE85D24)),
                              ),
                              Expanded(
                                child: ColoredBox(color: Color(0xFF183E9E)),
                              ),
                            ],
                          ),
                        ),
                        AppBackdropScope(
                          backdrop: layerBackdrop,
                          child: const GlassSurface(
                            variant: GlassVariant.liquid,
                            child: Center(
                              child: SizedBox(
                                width: 12,
                                height: 12,
                                child: ColoredBox(color: AppPalette.brand),
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
        );
        await tester.pumpAndSettle();
        expect(find.byType(DrawBackdrop), findsOneWidget);
        final bytes = await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          try {
            return await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          } finally {
            image.dispose();
          }
        });
        final offset = (50 * 200 + 100) * 4;
        final center = Color.fromARGB(
          bytes!.getUint8(offset + 3),
          bytes.getUint8(offset),
          bytes.getUint8(offset + 1),
          bytes.getUint8(offset + 2),
        );
        expect(center, AppPalette.brand);
        expect(tester.takeException(), isNull);
      }

      // When solid is true, DrawBackdrop and BackdropFilter are both omitted.
      await tester.pumpWidget(
        MaterialApp(
          theme: singVerseTheme(Brightness.dark),
          home: Center(
            child: SizedBox(
              width: 200,
              height: 100,
              child: AppBackdropCapture(
                solid: true,
                builder: (context, layerBackdrop) => AppBackdropScope(
                  backdrop: layerBackdrop,
                  child: const GlassSurface(
                    solid: true,
                    variant: GlassVariant.liquid,
                    child: SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DrawBackdrop), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dual-layer AppBackdropPage mounts DrawBackdrop on cards and showAppSheet',
    (tester) async {
      await tester.runAsync(FluidGlass.ensureInitialized);
      await tester.pumpWidget(
        MaterialApp(
          theme: singVerseTheme(Brightness.dark),
          home: AppBackdropPage(
            appBar: const AppToolbar(title: Text('测试页')),
            body: Builder(
              builder: (context) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const GlassSurface(
                      material: GlassMaterialSpec.standard,
                      child: SizedBox(width: 120, height: 60),
                    ),
                    TextButton(
                      onPressed: () => showAppSheet<void>(
                        context: context,
                        builder: (context) => const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('液态玻璃弹层'),
                        ),
                      ),
                      child: const Text('打开弹层'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // The in-scroll standard card samples environment without recursion.
      expect(find.byType(DrawBackdrop), findsOneWidget);
      await tester.tap(find.text('打开弹层'));
      await tester.pumpAndSettle();
      expect(find.text('液态玻璃弹层'), findsOneWidget);
      // Both the underlying standard card and the modal sheet mount DrawBackdrop.
      expect(find.byType(DrawBackdrop), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );
}
