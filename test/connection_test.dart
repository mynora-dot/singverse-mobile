import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:singverse_mobile/app/design.dart';
import 'package:singverse_mobile/core/api.dart';
import 'package:singverse_mobile/core/app_state.dart';
import 'package:singverse_mobile/core/local_store.dart';
import 'package:singverse_mobile/core/login_store.dart';
import 'package:singverse_mobile/core/nas_discovery.dart';
import 'package:singverse_mobile/features/library/connection.dart';
import 'package:singverse_mobile/features/library/login_history_page.dart';
import 'package:singverse_mobile/features/library/nas_discovery_page.dart';
import 'package:singverse_mobile/features/library/password_reset_page.dart';

import 'mobile_redesign_test.dart' show NativeFixture;
import 'widget_test.dart' show FakeApi;

LoginRecord record({
  String origin = 'http://nas.local:18080',
  String instance = 'nas-a',
  String username = 'admin',
  bool password = true,
}) => LoginRecord(
  origin: origin,
  instanceId: instance,
  username: username,
  name: instance == 'nas-a' ? '客厅曲库' : '另一台 NAS',
  lastUsed: 1,
  hasPassword: password,
);

class MemoryLogins implements LoginStore {
  final records = <LoginRecord>[];
  final secrets = <String, String>{};
  int passwordReads = 0;
  Completer<List<LoginRecord>>? pendingLoad;
  void seed(LoginRecord record, [String secret = 'remembered password']) {
    records.add(record);
    if (record.hasPassword) secrets[record.id] = secret;
  }

  @override
  Future<List<LoginRecord>> load() async =>
      pendingLoad?.future ?? List.of(records);
  @override
  Future<String?> password(LoginRecord record) async {
    passwordReads++;
    return secrets[record.id];
  }

  @override
  Future<void> save(LoginRecord record, {String? password}) async {
    records.removeWhere(
      (item) =>
          item.origin == record.origin && item.username == record.username,
    );
    secrets.remove(record.id);
    records.insert(
      0,
      LoginRecord(
        origin: record.origin,
        instanceId: record.instanceId,
        username: record.username,
        name: record.name,
        lastUsed: record.lastUsed,
        hasPassword: password?.isNotEmpty == true,
      ),
    );
    if (password?.isNotEmpty == true) secrets[record.id] = password!;
  }

  @override
  Future<void> remove(LoginRecord record) async {
    records.removeWhere((item) => item.id == record.id);
    secrets.remove(record.id);
  }

  @override
  Future<void> forgetPassword(LoginRecord record) async {
    secrets.remove(record.id);
    final index = records.indexWhere((item) => item.id == record.id);
    if (index >= 0) {
      records[index] = LoginRecord(
        origin: record.origin,
        instanceId: record.instanceId,
        username: record.username,
        name: record.name,
        lastUsed: record.lastUsed,
      );
    }
  }

  @override
  Future<void> forgetServerPasswords(String instanceId) async {
    for (final record in List.of(
      records.where((item) => item.instanceId == instanceId),
    )) {
      await forgetPassword(record);
    }
  }
}

class LoginApi extends FakeApi {
  String identity = 'nas-a', username = 'admin';
  final loginBodies = <Map>[];
  final resetBodies = <Map>[];
  ApiFailure? verifyFailure, resetFailure;
  Completer<void>? pendingInspection;
  @override
  Future<void> configure(String value) async {
    if (value != origin) loggedIn = false;
    origin = value;
  }

  @override
  Future<dynamic> inspect(String origin, {String? invitation}) async {
    await pendingInspection?.future;
    if (offline) throw ApiFailure(0, 'NAS 不可达');
    return {
      'service': 'singverse',
      'apiVersion': 1,
      'instanceId': identity,
      'name': '客厅曲库',
    };
  }

  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Object? body,
  }) async {
    if (path.endsWith('/auth/login')) {
      loginBodies.add(body as Map);
      username = body['username'] as String;
    }
    if (path.endsWith('/auth/session') && loggedIn) {
      return {'username': username};
    }
    if (path.startsWith('/api/v1/favorites') && !loggedIn) {
      throw ApiFailure(401, '请登录');
    }
    if (path.endsWith('/mfa/verify') && verifyFailure != null) {
      throw verifyFailure!;
    }
    if (path.endsWith('/auth/password/reset')) {
      resetBodies.add(body as Map);
      if (resetFailure != null) throw resetFailure!;
      loggedIn = false;
      return null;
    }
    return super.request(path, method: method, body: body);
  }
}

class DiscoveryFixture implements NasDiscovery {
  final events = StreamController<NasDiscoverySnapshot>.broadcast(sync: true);
  NasDiscoverySnapshot result = const NasDiscoverySnapshot(
    services: [DiscoveredNas('客厅曲库', 'http://192.168.1.8:18080')],
  );
  int starts = 0, stops = 0;
  @override
  Stream<NasDiscoverySnapshot> get snapshots => events.stream;
  @override
  Future<void> start() async {
    starts++;
    events.add(result);
  }

  @override
  Future<void> stop() async {
    stops++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late LocalStore local;
  late AppState state;
  late LoginApi api;
  late MemoryLogins logins;
  late DiscoveryFixture discovery;
  late NativeFixture native;

  setUpAll(() async {
    final bytes = File('test/fixtures/fonts/UiCapture.ttf').readAsBytesSync();
    for (final family in ['Roboto', 'UiCapture', 'Ahem']) {
      await (FontLoader(
        family,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    local = await LocalStore.open(
      factory: databaseFactoryFfiNoIsolate,
      path: inMemoryDatabasePath,
    );
    api = LoginApi();
    logins = MemoryLogins();
    discovery = DiscoveryFixture();
    state = AppState(
      api: api,
      store: local,
      preferences: await SharedPreferences.getInstance(),
      loginStore: logins,
      listenPlayer: false,
    )..initialized = true;
    native = NativeFixture(state)..install();
  });
  tearDown(() async {
    native.uninstall();
    state.dispose();
    await local.close();
    await discovery.events.close();
  });

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double scale = 1,
    Brightness brightness = Brightness.light,
    Widget? page,
  }) async {
    await tester.binding.setSurfaceSize(size);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: singVerseTheme(brightness, senior: state.senior),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const ValueKey('open-login'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      page ??
                      ConnectionPage(
                        state: state,
                        loginStore: logins,
                        discovery: discovery,
                      ),
                ),
              ),
              child: const Text('打开连接'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-login')));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, String key, String value) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.enterText(finder, value);
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) =>
      tap(tester, find.byKey(const ValueKey('nas-submit')));

  test(
    'protocol entry preserves explicit ports and rejects non-root addresses',
    () {
      expect(
        connectionOrigin(' NAS.local:18443 ', 'https'),
        'https://nas.local:18443',
      );
      expect(
        connectionOrigin('http://NAS.local:18080/', 'https'),
        'http://nas.local:18080',
      );
      expect(
        connectionOrigin('[fd00::1]:18080', 'http'),
        'http://[fd00::1]:18080',
      );
      for (final address in [
        'nas.local/admin',
        'user:secret@nas.local',
        'nas.local?token=secret',
        'nas.local#secret',
        'nas.local:0',
        'nas.local:65536',
      ]) {
        expect(
          () => connectionOrigin(address, 'https'),
          throwsFormatException,
          reason: address,
        );
      }
    },
  );

  testWidgets(
    'one form logs in with chosen protocol and administrator username',
    (tester) async {
      await open(tester);
      expect(
        tester
            .widget<Checkbox>(find.byKey(const ValueKey('remember-password')))
            .value,
        false,
      );
      await tap(tester, find.text('HTTPS'));
      await enter(tester, 'nas-address-field', 'NAS.local:18443');
      await enter(tester, 'nas-username-field', 'family-admin');
      await enter(tester, 'nas-password-field', 'a strong password');
      await tap(tester, find.byTooltip('显示密码'));
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('nas-password-field')))
            .obscureText,
        false,
      );
      await tap(tester, find.byKey(const ValueKey('remember-password')));
      await submit(tester);
      expect(state.authenticated, true);
      expect(state.origin, 'https://nas.local:18443');
      expect(api.loginBodies.single, {
        'username': 'family-admin',
        'password': 'a strong password',
      });
      expect(logins.records.single.username, 'family-admin');
      expect(logins.records.single.protocol, 'HTTPS');
      expect(logins.secrets.values.single, 'a strong password');
      expect(
        (await SharedPreferences.getInstance()).getKeys().any(
          (key) => key.contains('password'),
        ),
        false,
      );
      expect(find.byType(ConnectionPage), findsNothing);
    },
  );

  testWidgets('unchecked remember keeps history without a password', (
    tester,
  ) async {
    await open(tester);
    await enter(tester, 'nas-address-field', 'http://nas.local:18080');
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('nas-address-field')))
          .controller!
          .text,
      'nas.local:18080',
    );
    await enter(tester, 'nas-password-field', 'one use password');
    await submit(tester);
    expect(logins.records.single.hasPassword, false);
    expect(logins.secrets, isEmpty);
  });

  testWidgets('automatic login requires remembering the password', (
    tester,
  ) async {
    await open(tester);
    final automatic = find.byKey(const ValueKey('automatic-login'));
    final remember = find.byKey(const ValueKey('remember-password'));
    expect(tester.widget<Checkbox>(automatic).value, false);
    await tap(tester, automatic);
    expect(tester.widget<Checkbox>(automatic).value, true);
    expect(tester.widget<Checkbox>(remember).value, true);
    await tap(tester, remember);
    expect(tester.widget<Checkbox>(automatic).value, false);
    expect(tester.widget<Checkbox>(remember).value, false);
    expect(state.automaticLogin, false);
    expect(api.loginBodies, isEmpty);
  });

  testWidgets('automatic login persists only after a successful login', (
    tester,
  ) async {
    await open(tester);
    await enter(tester, 'nas-address-field', 'nas.local:18080');
    await enter(tester, 'nas-username-field', 'family-admin');
    await enter(tester, 'nas-password-field', 'automatically remembered');
    await tap(tester, find.byKey(const ValueKey('automatic-login')));
    expect(state.automaticLogin, false);
    await submit(tester);
    expect(state.automaticLoginFor(logins.records.single), true);
    expect(logins.secrets.values.single, 'automatically remembered');

    // A fresh process can reconnect from history even if its session has gone.
    api.origin = '';
    api.loggedIn = false;
    final restarted = AppState(
      api: api,
      store: local,
      preferences: state.preferences,
      loginStore: logins,
      listenPlayer: false,
    );
    addTearDown(restarted.dispose);
    await restarted.initialize();
    expect(restarted.authenticated, true);
    expect(restarted.accountName, 'family-admin');
    expect(restarted.origin, 'http://nas.local:18080');
    expect(api.loginBodies, hasLength(2));
    expect(logins.passwordReads, 1);
    expect(
      state.preferences.getKeys().map(state.preferences.get),
      isNot(contains('automatically remembered')),
    );
  });

  testWidgets('turning off automatic login keeps the remembered password', (
    tester,
  ) async {
    final saved = record();
    logins.seed(saved);
    await state.setAutomaticLogin(saved);
    await open(tester);
    final automatic = find.byKey(const ValueKey('automatic-login'));
    expect(tester.widget<Checkbox>(automatic).value, true);
    await tap(tester, automatic);
    expect(state.automaticLogin, false);
    expect(logins.secrets[saved.id], 'remembered password');
    expect(
      tester
          .widget<Checkbox>(find.byKey(const ValueKey('remember-password')))
          .value,
      true,
    );
  });

  test(
    'automatic login reuses an unexpired session without reading a password',
    () async {
      final saved = record();
      logins.seed(saved);
      await state.setAutomaticLogin(saved);
      api.origin = saved.origin;
      api.loggedIn = true;
      await state.initialize();
      expect(state.authenticated, true);
      expect(logins.passwordReads, 0);
      expect(api.loginBodies, isEmpty);
    },
  );

  testWidgets('foreground return renews an expired automatic login', (
    tester,
  ) async {
    final saved = record();
    logins.seed(saved);
    await state.setAutomaticLogin(saved);
    api.origin = saved.origin;
    api.loggedIn = true;
    await state.initialize();
    expect(state.authenticated, isTrue);
    expect(api.loginBodies, isEmpty);

    state.didChangeAppLifecycleState(AppLifecycleState.paused);
    api.loggedIn = false;
    state.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(state.authenticated, isTrue);
    expect(state.accountName, saved.username);
    expect(logins.passwordReads, 1);
    expect(api.loginBodies, hasLength(1));
    expect(state.automaticLoginFor(saved), isTrue);
    expect(state.favoritesReady, isTrue);
    expect(state.error, isNull);
  });

  testWidgets('foreground return retries an offline automatic startup', (
    tester,
  ) async {
    final saved = record();
    logins.seed(saved);
    await state.setAutomaticLogin(saved);
    api.offline = true;
    await state.initialize();
    expect(state.authenticated, isFalse);
    expect(state.error, 'NAS 不可达');

    state.didChangeAppLifecycleState(AppLifecycleState.paused);
    api.offline = false;
    state.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(state.authenticated, isTrue);
    expect(state.accountName, saved.username);
    expect(logins.passwordReads, 1);
    expect(api.loginBodies, hasLength(1));
    expect(state.error, isNull);
  });

  testWidgets(
    'foreground return keeps a valid session without reading secrets',
    (tester) async {
      final saved = record();
      logins.seed(saved);
      await state.setAutomaticLogin(saved);
      api.origin = saved.origin;
      api.loggedIn = true;
      await state.initialize();

      state.didChangeAppLifecycleState(AppLifecycleState.paused);
      state.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(state.authenticated, isTrue);
      expect(logins.passwordReads, 0);
      expect(api.loginBodies, isEmpty);
    },
  );

  testWidgets('foreground return honors disabled automatic login', (
    tester,
  ) async {
    final saved = record();
    logins.seed(saved);
    await state.setAutomaticLogin(null);
    api.origin = state.origin = saved.origin;
    state.instanceId = saved.instanceId;
    api.loggedIn = state.authenticated = true;

    state.didChangeAppLifecycleState(AppLifecycleState.paused);
    api.loggedIn = false;
    state.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(state.authenticated, isFalse);
    expect(logins.passwordReads, 0);
    expect(api.loginBodies, isEmpty);
    expect(logins.secrets[saved.id], 'remembered password');
  });

  testWidgets('foreground automatic login never switches to a previous NAS', (
    tester,
  ) async {
    final saved = record();
    logins.seed(saved);
    await state.setAutomaticLogin(saved);
    state.origin = api.origin = 'http://other-nas.local:18080';
    state.instanceId = 'nas-b';

    state.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(state.origin, 'http://other-nas.local:18080');
    expect(api.origin, state.origin);
    expect(logins.passwordReads, 0);
    expect(api.loginBodies, isEmpty);
  });

  testWidgets(
    'foreground automatic login checks the NAS before reading secrets',
    (tester) async {
      final saved = record();
      logins.seed(saved);
      await state.setAutomaticLogin(saved);
      state.origin = api.origin = saved.origin;
      api.identity = 'replacement';

      state.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(state.authenticated, isFalse);
      expect(state.automaticLogin, isFalse);
      expect(logins.passwordReads, 0);
      expect(api.loginBodies, isEmpty);
      expect(state.error, contains('曲库身份已变化'));
    },
  );

  testWidgets('foreground automatic login still waits for MFA verification', (
    tester,
  ) async {
    final saved = record();
    logins.seed(saved);
    await state.setAutomaticLogin(saved);
    state.origin = api.origin = saved.origin;
    api.loginState = 'mfaRequired';

    state.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(state.authenticated, isFalse);
    expect(state.mfaRequired, isTrue);
    expect(api.loginBodies, hasLength(1));

    state.didChangeAppLifecycleState(AppLifecycleState.paused);
    state.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(api.loginBodies, hasLength(1));

    await open(tester);
    await enter(tester, 'nas-mfa-field', '123456');
    await submit(tester);
    expect(state.authenticated, isTrue);
    expect(state.automaticLogin, isTrue);
  });

  testWidgets('rejected foreground credentials stop later automatic attempts', (
    tester,
  ) async {
    final saved = record();
    logins.seed(saved);
    await state.setAutomaticLogin(saved);
    state.origin = api.origin = saved.origin;
    api.loginFailure = ApiFailure(401, '密码错误');

    state.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(state.authenticated, isFalse);
    expect(state.automaticLogin, isFalse);
    expect(state.error, '密码错误');

    state.didChangeAppLifecycleState(AppLifecycleState.paused);
    state.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(api.loginBodies, hasLength(1));
    expect(logins.secrets[saved.id], 'remembered password');
  });

  testWidgets(
    'overlapping foreground events make one automatic login attempt',
    (tester) async {
      final saved = record();
      logins.seed(saved);
      await state.setAutomaticLogin(saved);
      state.origin = api.origin = saved.origin;
      final inspection = api.pendingInspection = Completer<void>();

      state.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(state.busy, isTrue);
      state.didChangeAppLifecycleState(AppLifecycleState.resumed);
      inspection.complete();
      await tester.pumpAndSettle();

      expect(state.authenticated, isTrue);
      expect(api.loginBodies, hasLength(1));
      expect(logins.passwordReads, 1);
      expect(state.busy, isFalse);
    },
  );

  testWidgets('foreground automatic login waits until recording is finished', (
    tester,
  ) async {
    final saved = record();
    logins.seed(saved);
    await state.setAutomaticLogin(saved);
    state.origin = api.origin = saved.origin;
    state.singing = {'phase': 'RECORDING'};

    state.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(api.loginBodies, isEmpty);
    expect(logins.passwordReads, 0);

    state.singing = {'phase': 'IDLE'};
    state.didChangeAppLifecycleState(AppLifecycleState.paused);
    state.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(state.authenticated, isTrue);
    expect(api.loginBodies, hasLength(1));
  });

  testWidgets(
    'focus follows the active field without changing credentials or sending requests',
    (tester) async {
      await open(tester);
      await enter(tester, 'nas-address-field', 'nas.local:18080');
      await enter(tester, 'nas-username-field', 'family-admin');
      await enter(tester, 'nas-password-field', 'test password');
      FocusNode focusFor(String key) => tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(ValueKey(key)),
              matching: find.byType(EditableText),
            ),
          )
          .focusNode;
      expect(focusFor('nas-password-field').hasFocus, isTrue);
      expect(focusFor('nas-username-field').hasFocus, isFalse);
      final username = find.byKey(const ValueKey('nas-username-field'));
      await tap(tester, username);
      expect(focusFor('nas-username-field').hasFocus, isTrue);
      expect(focusFor('nas-password-field').hasFocus, isFalse);
      expect(
        tester.widget<TextField>(username).controller!.text,
        'family-admin',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('nas-password-field')))
            .controller!
            .text,
        'test password',
      );
      expect(api.loginBodies, isEmpty);
      expect(logins.secrets, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'disabled automatic login requires manual login with a valid cookie',
    () async {
      api.origin = record().origin;
      api.loggedIn = true;
      await state.setAutomaticLogin(null);
      await state.initialize();
      expect(state.authenticated, false);
      expect(api.requests, isNot(contains('/api/v1/auth/session')));
      expect(logins.passwordReads, 0);
    },
  );

  test(
    'automatic login verifies the NAS identity before retrieving a password',
    () async {
      final saved = record();
      logins.seed(saved);
      await state.setAutomaticLogin(saved);
      api.identity = 'replacement';
      await state.initialize();
      expect(state.authenticated, false);
      expect(state.automaticLogin, false);
      expect(logins.passwordReads, 0);
      expect(api.loginBodies, isEmpty);
      expect(state.error, contains('曲库身份已变化'));
    },
  );

  test(
    'an unreachable NAS does not read the saved password or retry in a loop',
    () async {
      final saved = record();
      logins.seed(saved);
      await state.setAutomaticLogin(saved);
      api.offline = true;
      await state.initialize();
      expect(state.initialized, true);
      expect(state.authenticated, false);
      expect(state.automaticLogin, true);
      expect(logins.passwordReads, 0);
      expect(api.loginBodies, isEmpty);
      expect(state.error, 'NAS 不可达');
    },
  );

  test(
    'rejected automatic credentials stop further automatic attempts',
    () async {
      final saved = record();
      logins.seed(saved);
      await state.setAutomaticLogin(saved);
      api.loginFailure = ApiFailure(401, '密码错误');
      await state.initialize();
      expect(state.initialized, true);
      expect(state.authenticated, false);
      expect(state.automaticLogin, false);
      expect(api.loginBodies, hasLength(1));
      expect(logins.secrets[saved.id], 'remembered password');
      expect(state.error, '密码错误');
    },
  );

  test('rate-limited automatic login exposes the server retry delay', () async {
    final saved = record();
    logins.seed(saved);
    await state.setAutomaticLogin(saved);
    api.loginFailure = ApiFailure(429, '登录次数过多', retryAfter: '30');
    await state.initialize();
    expect(state.authenticated, false);
    expect(api.loginBodies, hasLength(1));
    expect(state.retryAfter, '30');
    expect(state.automaticLogin, true);
  });

  test('a removed remembered login disables automatic login', () async {
    final saved = record();
    logins.seed(saved);
    await state.setAutomaticLogin(saved);
    await logins.forgetPassword(saved);
    api.origin = saved.origin;
    api.loggedIn = true;
    await state.initialize();
    expect(state.authenticated, false);
    expect(state.automaticLogin, false);
    expect(logins.passwordReads, 0);
    expect(api.loginBodies, isEmpty);
  });

  test(
    'explicit logout disables automatic login but keeps saved credentials',
    () async {
      final saved = record();
      logins.seed(saved);
      await state.setAutomaticLogin(saved);
      state.origin = api.origin = saved.origin;
      state.authenticated = api.loggedIn = true;
      await state.logout();
      expect(state.automaticLogin, false);
      expect(state.authenticated, false);
      expect(logins.secrets[saved.id], 'remembered password');
      await state.initialize();
      expect(state.authenticated, false);
      expect(api.loginBodies, isEmpty);
    },
  );

  testWidgets('automatic login still requires MFA verification', (
    tester,
  ) async {
    final saved = record();
    logins.seed(saved);
    await state.setAutomaticLogin(saved);
    api.loginState = 'mfaRequired';
    await state.initialize();
    expect(state.authenticated, false);
    expect(state.mfaRequired, true);
    await open(tester);
    expect(find.text('验证身份'), findsOneWidget);
    await enter(tester, 'nas-mfa-field', '123456');
    await submit(tester);
    expect(state.authenticated, true);
    expect(state.automaticLogin, true);
  });

  testWidgets(
    'MFA saves credentials and automatic login only after verification',
    (tester) async {
      api.loginState = 'mfaRequired';
      api.verifyFailure = ApiFailure(401, '验证码错误');
      await open(tester);
      await enter(tester, 'nas-address-field', 'nas.local:18080');
      await enter(tester, 'nas-password-field', 'pending MFA password');
      await tap(tester, find.byKey(const ValueKey('automatic-login')));
      await submit(tester);
      expect(find.text('验证身份'), findsOneWidget);
      expect(logins.records, isEmpty);
      expect(state.automaticLogin, false);
      await enter(tester, 'nas-mfa-field', '000000');
      await submit(tester);
      expect(logins.secrets, isEmpty);
      expect(state.automaticLogin, false);
      expect(find.textContaining('验证码错误'), findsOneWidget);
      api.verifyFailure = null;
      await enter(tester, 'nas-mfa-field', '123456');
      await submit(tester);
      expect(logins.secrets.values.single, 'pending MFA password');
      expect(state.authenticated, true);
      expect(state.automaticLoginFor(logins.records.single), true);
    },
  );

  testWidgets(
    'saved password is read only after the same NAS identity is verified',
    (tester) async {
      logins.seed(record());
      await open(tester);
      expect(logins.passwordReads, 0);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('nas-password-field')))
            .controller!
            .text,
        '',
      );
      await submit(tester);
      expect(logins.passwordReads, 1);
      expect(api.loginBodies.single['password'], 'remembered password');
    },
  );

  testWidgets(
    'replacement NAS never receives the password for the old instance',
    (tester) async {
      logins.seed(record());
      api.identity = 'replacement';
      await open(tester);
      await submit(tester);
      expect(logins.passwordReads, 0);
      expect(api.loginBodies, isEmpty);
      expect(find.textContaining('曲库身份已变化'), findsOneWidget);
      expect(state.authenticated, false);
    },
  );

  testWidgets('changing protocol clears saved credential selection', (
    tester,
  ) async {
    logins.seed(record());
    await open(tester);
    await tap(tester, find.text('HTTPS'));
    await submit(tester);
    expect(state.origin, 'https://nas.local:18080');
    expect(api.loginBodies, isEmpty);
    expect(logins.passwordReads, 0);
    expect(find.text('请输入密码'), findsOneWidget);
  });

  testWidgets(
    'tapping the selected protocol preserves the remembered credential',
    (tester) async {
      logins.seed(record());
      await open(tester);
      await tap(tester, find.text('HTTP'));
      expect(find.text('已保存密码'), findsOneWidget);
      await submit(tester);
      expect(logins.passwordReads, 1);
      expect(api.loginBodies.single['password'], 'remembered password');
      expect(state.authenticated, isTrue);
    },
  );

  testWidgets(
    'unchecking remember deletes the stored secret before another login',
    (tester) async {
      logins.seed(record());
      await open(tester);
      await tap(tester, find.byKey(const ValueKey('remember-password')));
      expect(logins.secrets, isEmpty);
      expect(logins.records.single.hasPassword, false);
      expect(api.loginBodies, isEmpty);
    },
  );

  testWidgets('failed login does not save a secret and exposes retry delay', (
    tester,
  ) async {
    api.loginFailure = ApiFailure(429, '登录次数过多', retryAfter: '30');
    await open(tester);
    await enter(tester, 'nas-address-field', 'nas.local:18080');
    await enter(tester, 'nas-password-field', 'invalid password');
    await tap(tester, find.byKey(const ValueKey('remember-password')));
    await submit(tester);
    expect(logins.records, isEmpty);
    expect(find.textContaining('30 秒后重试'), findsOneWidget);
  });

  testWidgets(
    'history fills address account and protocol without authenticating',
    (tester) async {
      final first = record(password: false);
      final second = record(
        origin: 'https://remote.example:18443',
        instance: 'nas-b',
        username: 'family-admin',
        password: false,
      );
      logins.seed(first);
      logins.seed(second);
      await open(tester);
      await tap(tester, find.byKey(const ValueKey('nas-history')));
      await tap(tester, find.byKey(ValueKey('login-record:${second.id}')));
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('nas-address-field')))
            .controller!
            .text,
        'remote.example:18443',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('nas-username-field')))
            .controller!
            .text,
        'family-admin',
      );
      expect(
        tester
            .widget<AppSegments<String>>(
              find.byKey(const ValueKey('nas-protocol')),
            )
            .selected,
        'https',
      );
      expect(api.loginBodies, isEmpty);
    },
  );

  testWidgets('history can forget a secret and remove a record independently', (
    tester,
  ) async {
    final first = record();
    final second = record(origin: 'https://nas.local:18443');
    logins.seed(first);
    logins.seed(second);
    await open(tester, page: LoginHistoryPage(store: logins));
    Finder menu(LoginRecord record) => find.descendant(
      of: find.byKey(ValueKey('login-record:${record.id}')),
      matching: find.byType(PopupMenuButton<String>),
    );
    await tap(tester, menu(first));
    await tap(tester, find.text('忘记已保存密码'));
    expect(logins.secrets.containsKey(first.id), false);
    expect(logins.secrets.containsKey(second.id), true);
    await tap(tester, menu(first));
    await tap(tester, find.text('移除登录记录'));
    expect(logins.records.map((item) => item.id), [second.id]);
    expect(find.text('HTTPS · 已记住密码'), findsOneWidget);
  });

  testWidgets(
    'returning from history reflects a forgotten password in the form',
    (tester) async {
      logins.seed(record());
      await open(tester);
      await tap(tester, find.byKey(const ValueKey('nas-history')));
      await tap(tester, find.byType(PopupMenuButton<String>));
      await tap(tester, find.text('忘记已保存密码'));
      await tap(tester, find.byType(BackButton));
      expect(
        tester
            .widget<Checkbox>(find.byKey(const ValueKey('remember-password')))
            .value,
        false,
      );
      expect(find.text('密码'), findsOneWidget);
      expect(find.text('已保存密码'), findsNothing);
      expect(logins.secrets, isEmpty);
    },
  );

  testWidgets(
    'cancelling a history selection restores the connected administrator',
    (tester) async {
      state.origin = 'http://nas.local:18080';
      state.authenticated = true;
      state.accountName = 'owner';
      final remote = record(
        origin: 'https://remote.example:18443',
        instance: 'nas-b',
        username: 'other-admin',
      );
      logins.seed(remote);
      await open(tester);
      await tap(tester, find.text('修改 NAS 地址'));
      await tap(tester, find.byKey(const ValueKey('nas-history')));
      await tap(tester, find.byKey(ValueKey('login-record:${remote.id}')));
      await tap(tester, find.text('取消修改'));
      await tap(tester, find.text('修改 NAS 地址'));
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('nas-address-field')))
            .controller!
            .text,
        'nas.local:18080',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('nas-username-field')))
            .controller!
            .text,
        'owner',
      );
      expect(
        tester
            .widget<Checkbox>(find.byKey(const ValueKey('remember-password')))
            .value,
        false,
      );
      expect(api.loginBodies, isEmpty);
    },
  );

  testWidgets('late history cannot overwrite a manually edited address', (
    tester,
  ) async {
    final gate = Completer<List<LoginRecord>>();
    logins.pendingLoad = gate;
    await open(tester);
    await enter(tester, 'nas-address-field', 'my-new-nas.local:18080');
    gate.complete([record()]);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('nas-address-field')))
          .controller!
          .text,
      'my-new-nas.local:18080',
    );
  });

  testWidgets('LAN discovery selects an address and stops when leaving', (
    tester,
  ) async {
    await open(tester);
    await tap(tester, find.byKey(const ValueKey('nas-discover')));
    expect(discovery.starts, 1);
    expect(find.text('找到 1 台 NAS'), findsOneWidget);
    await tap(
      tester,
      find.byKey(const ValueKey('discovered-nas:http://192.168.1.8:18080')),
    );
    expect(discovery.stops, greaterThanOrEqualTo(1));
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('nas-address-field')))
          .controller!
          .text,
      '192.168.1.8:18080',
    );
    expect(api.loginBodies, isEmpty);
  });

  testWidgets('discovery supports empty results retry and cancellation', (
    tester,
  ) async {
    discovery.result = const NasDiscoverySnapshot();
    await open(tester, page: NasDiscoveryPage(discovery: discovery));
    expect(find.text('未发现设备'), findsOneWidget);
    await tap(tester, find.text('重新查找'));
    expect(discovery.starts, 2);
    await tap(tester, find.text('手动输入 IP 或域名'));
    expect(discovery.stops, greaterThanOrEqualTo(1));
    expect(find.byType(NasDiscoveryPage), findsNothing);
  });

  testWidgets(
    'password reset validates inputs and retains secrets on server rejection',
    (tester) async {
      state.origin = 'http://nas.local:18080';
      state.instanceId = 'nas-a';
      logins.seed(record());
      api.resetFailure = ApiFailure(401, '重置码已过期');
      await open(
        tester,
        page: PasswordResetPage(
          state: state,
          store: logins,
          username: 'family-admin',
        ),
      );
      await tap(tester, find.byKey(const ValueKey('reset-submit')));
      expect(api.resetBodies, isEmpty);
      expect(find.textContaining('43 位重置码'), findsOneWidget);
      await enter(tester, 'reset-token', ''.padLeft(43, 'a'));
      await enter(tester, 'reset-password', 'short');
      await tap(tester, find.byKey(const ValueKey('reset-submit')));
      expect(find.textContaining('15～128'), findsAtLeastNWidgets(1));
      await enter(tester, 'reset-password', 'a new strong password');
      await enter(tester, 'reset-confirmation', 'different password');
      await tap(tester, find.byKey(const ValueKey('reset-submit')));
      expect(find.text('两次输入的新密码不一致'), findsOneWidget);
      await enter(tester, 'reset-confirmation', 'a new strong password');
      await tap(tester, find.byKey(const ValueKey('reset-submit')));
      expect(api.resetBodies.single['username'], 'family-admin');
      expect(find.text('重置码已过期'), findsOneWidget);
      expect(logins.secrets, isNotEmpty);
    },
  );

  testWidgets(
    'forgot password verifies address and clears all aliases after resetting',
    (tester) async {
      logins.seed(record());
      logins.seed(record(origin: 'https://remote.example:18443'));
      final other = record(
        origin: 'http://other.local:18080',
        instance: 'nas-b',
      );
      logins.seed(other);
      await open(tester);
      await tap(tester, find.byKey(const ValueKey('forgot-password')));
      expect(find.byType(PasswordResetPage), findsOneWidget);
      expect(state.instanceId, 'nas-a');
      await enter(tester, 'reset-username', 'family-admin');
      await enter(tester, 'reset-token', ''.padLeft(43, 'a'));
      await enter(tester, 'reset-password', 'a new strong password');
      await enter(tester, 'reset-confirmation', 'a new strong password');
      await tap(tester, find.byKey(const ValueKey('reset-submit')));
      expect(find.byType(PasswordResetPage), findsNothing);
      expect(find.text('密码已重置，请使用新密码登录'), findsOneWidget);
      expect(logins.secrets.keys, [other.id]);
      expect(api.resetBodies.single, {
        'username': 'family-admin',
        'resetToken': ''.padLeft(43, 'a'),
        'newPassword': 'a new strong password',
      });
      expect(state.authenticated, false);
      expect(state.mfaRequired, false);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('nas-username-field')))
            .controller!
            .text,
        'family-admin',
      );
      expect(api.loginBodies, isEmpty);
    },
  );

  testWidgets(
    'login and helper pages remain usable at small size and large text',
    (tester) async {
      state.uiMode = UiMode.senior;
      logins.seed(
        record(
          origin: 'https://a-long-family-library-name.home.local:18443',
          username: 'family-administrator',
        ),
      );
      final pages = <Widget Function()>[
        () => ConnectionPage(
          state: state,
          loginStore: logins,
          discovery: discovery,
        ),
        () => LoginHistoryPage(store: logins),
        () => NasDiscoveryPage(discovery: discovery),
        () => PasswordResetPage(
          state: state,
          store: logins,
          username: 'family-admin',
        ),
      ];
      for (final brightness in Brightness.values) {
        for (final page in pages) {
          await tester.pumpWidget(const SizedBox());
          await open(
            tester,
            size: const Size(320, 568),
            scale: 2,
            brightness: brightness,
            page: page(),
          );
          final submit = find.byKey(const ValueKey('nas-submit'));
          if (submit.evaluate().isNotEmpty) {
            await tester.ensureVisible(
              find.byKey(const ValueKey('nas-password-field')),
            );
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('nas-password-field')).hitTestable(),
              findsOneWidget,
            );
            await tester.tap(find.byKey(const ValueKey('nas-password-field')));
            tester.view.viewInsets = const FakeViewPadding(bottom: 220);
            await tester.pumpAndSettle();
            await tester.ensureVisible(submit);
            await tester.pumpAndSettle();
            expect(submit.hitTestable(), findsOneWidget);
            expect(tester.getSize(submit).height, greaterThanOrEqualTo(56));
            tester.view.resetViewInsets();
          }
          expect(
            tester.takeException(),
            isNull,
            reason: '$brightness ${page().runtimeType}',
          );
        }
      }
    },
  );

  testWidgets('capture login history discovery and recovery', (tester) async {
    if (!const bool.fromEnvironment('CAPTURE_LOGIN_UI')) return;
    logins.seed(
      record(origin: 'http://192.168.1.8:18080', username: 'family-admin'),
    );
    logins.seed(
      record(origin: 'https://music.home.example:18443', password: false),
    );
    logins.seed(
      record(
        origin: 'http://192.168.1.20:18080',
        instance: 'nas-b',
        username: 'admin',
        password: false,
      ),
    );
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final samples = <(String, Widget, Brightness)>[
      (
        'login-light',
        ConnectionPage(state: state, loginStore: logins, discovery: discovery),
        Brightness.light,
      ),
      (
        'login-dark',
        ConnectionPage(state: state, loginStore: logins, discovery: discovery),
        Brightness.dark,
      ),
      ('login-history', LoginHistoryPage(store: logins), Brightness.light),
      (
        'lan-discovery',
        NasDiscoveryPage(discovery: discovery),
        Brightness.light,
      ),
      (
        'password-reset',
        PasswordResetPage(
          state: state,
          store: logins,
          username: 'family-admin',
        ),
        Brightness.light,
      ),
    ];
    for (final sample in samples) {
      if (sample.$1 == 'password-reset') {
        state.origin = 'http://192.168.1.8:18080';
        state.instanceId = 'nas-a';
      }
      await tester.pumpWidget(const SizedBox());
      final key = GlobalKey();
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            navigatorKey: navigator,
            theme: singVerseTheme(sample.$3),
            home: const Scaffold(),
          ),
        ),
      );
      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => sample.$2),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final directory = Directory('build/reports/mobile-login')
          ..createSync(recursive: true);
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('${directory.path}/${sample.$1}.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      expect(tester.takeException(), isNull, reason: sample.$1);
    }
    await tester.pumpWidget(const SizedBox());
  });
}
