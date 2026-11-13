import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:singverse_mobile/core/app_state.dart';
import 'package:singverse_mobile/core/local_store.dart';
import 'package:singverse_mobile/features/tv_control/tv_login_pairing.dart';
import 'package:singverse_mobile/features/tv_control/tv_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'tv_layout_test.dart' show ScannerPlatformFixture;
import 'widget_test.dart' show FakeApi;

class _ScanApi extends FakeApi {
  final inspections = <(String, String?)>[];

  @override
  Future<dynamic> inspect(String origin, {String? invitation}) async {
    inspections.add((origin, invitation));
    return {
      'service': 'singverse',
      'apiVersion': 1,
      'instanceId': 'nas-a',
      'deviceName': '聚会电视',
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late LocalStore store;
  late AppState state;
  late _ScanApi api;
  late ScannerPlatformFixture scanner;
  late MobileScannerPlatform original;
  final calls = <MethodCall>[];
  final id = 'a' * 32;
  // Full v1 format emitted by the TV, including its URL-encoded local endpoint.
  // All capability fields here are fixed test values, never a live TV code.
  const qr =
      'singverse://tv-login?v=1&endpoint=http%3A%2F%2F192.168.1.101%3A45678'
      '&session=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      '&key=000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open(
      factory: databaseFactoryFfiNoIsolate,
      path: inMemoryDatabasePath,
    );
    api = _ScanApi();
    state =
        AppState(
            api: api,
            store: store,
            preferences: await SharedPreferences.getInstance(),
            listenPlayer: false,
          )
          ..origin = 'http://192.168.1.2:18080'
          ..authenticated = true
          ..serverName = '家里的音乐库';
    original = MobileScannerPlatform.instance;
    scanner = ScannerPlatformFixture();
    MobileScannerPlatform.instance = scanner;
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(TvLoginPairing.channel, (call) async {
          calls.add(call);
          if (call.method == 'inspect') {
            return {'id': id, 'name': '客厅电视', 'remainingSeconds': 290};
          }
          return null;
        });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(TvLoginPairing.channel, null);
    MobileScannerPlatform.instance = original;
    state.dispose();
    await store.close();
    await scanner.close();
  });

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: TvPage(state: state)));
    await tester.pumpAndSettle();
  }

  void detect(WidgetTester tester, [String value = qr]) {
    tester.widget<MobileScanner>(find.byType(MobileScanner)).onDetect!(
      BarcodeCapture(barcodes: [Barcode(rawValue: value)]),
    );
  }

  testWidgets(
    'login QR uses current library and waits for explicit phone confirmation',
    (tester) async {
      await show(tester);
      detect(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('连接这台电视？'), findsOneWidget);
      expect(find.textContaining('家里的音乐库'), findsOneWidget);
      expect(calls.where((call) => call.method == 'confirm'), isEmpty);
      expect(find.byType(TextField), findsNothing);
      expect((calls.first.arguments as Map)['origin'], state.origin);
      expect((calls.first.arguments as Map)['qr'], qr);
      expect(api.inspections, isEmpty);
      await tester.tap(find.text('确认连接'));
      await tester.pumpAndSettle();
      expect(calls.where((call) => call.method == 'confirm'), hasLength(1));
      expect(find.text('已连接 客厅电视'), findsOneWidget);
      expect(find.byType(MobileScanner), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('party QR still opens the party preview without login pairing', (
    tester,
  ) async {
    final token = 'b' * 43;
    await show(tester);
    detect(tester, 'http://nas.local:18080/party/#invite=$token');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('连接电视聚会'), findsOneWidget);
    expect(find.text('连接这台电视？'), findsNothing);
    expect(api.inspections, [
      ('http://nas.local:18080', null),
      ('http://nas.local:18080', token),
    ]);
    expect(calls.where((call) => call.method == 'inspect'), isEmpty);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(MobileScanner), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('signed-out login QR explains the required phone login', (
    tester,
  ) async {
    state.authenticated = false;
    await show(tester);
    detect(tester);
    await tester.pumpAndSettle();
    expect(find.text('请先在 App 登录音乐库，再扫描电视登录码'), findsOneWidget);
    expect(find.textContaining('FormatException'), findsNothing);
    expect(calls.where((call) => call.method == 'inspect'), isEmpty);
    expect(api.inspections, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('unrelated QR shows a readable error and can retry login QR', (
    tester,
  ) async {
    await show(tester);
    detect(tester, 'https://example.com/');
    await tester.pumpAndSettle();
    expect(find.text('请扫描 SingVerse 电视上的登录或聚会二维码'), findsOneWidget);
    expect(find.textContaining('FormatException'), findsNothing);
    expect(calls.where((call) => call.method == 'inspect'), isEmpty);
    final starts = scanner.starts;
    await tester.ensureVisible(find.text('重试'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(scanner.starts, starts + 1);
    detect(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('连接这台电视？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('cancel never requests login and returns to scanning', (
    tester,
  ) async {
    await show(tester);
    detect(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(calls.where((call) => call.method == 'confirm'), isEmpty);
    expect(calls.where((call) => call.method == 'cancel'), isNotEmpty);
    expect(find.byType(MobileScanner), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'switching library while confirmation is open invalidates login',
    (tester) async {
      await show(tester);
      detect(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      state.origin = 'http://192.168.1.3:18080';
      await tester.tap(find.text('确认连接'));
      await tester.pumpAndSettle();
      expect(calls.where((call) => call.method == 'confirm'), isEmpty);
      expect(find.textContaining('音乐库已切换'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('late inspection after leaving page cannot open confirmation', (
    tester,
  ) async {
    final pending = Completer<Map<String, Object>>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(TvLoginPairing.channel, (call) async {
          calls.add(call);
          return call.method == 'inspect' ? pending.future : null;
        });
    await show(tester);
    detect(tester);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete({'id': id, 'name': '客厅电视', 'remainingSeconds': 200});
    await tester.pumpAndSettle();
    expect(calls.where((call) => call.method == 'confirm'), isEmpty);
    expect(tester.takeException(), isNull);
  });

  test('party invite stays separate from initial TV login', () {
    expect(TvLoginPairing.recognizes(qr), isTrue);
    expect(
      TvLoginPairing.recognizes(
        'http://nas.local:18080/party/#invite=${'a' * 32}',
      ),
      isFalse,
    );
    expect(TvLoginPairing.recognizes('singverse://other'), isFalse);
  });
}
