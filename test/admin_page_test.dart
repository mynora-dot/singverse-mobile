import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:singverse_mobile/app/design.dart';
import 'package:singverse_mobile/app/shell.dart';
import 'package:singverse_mobile/core/app_state.dart';
import 'package:singverse_mobile/core/local_store.dart';
import 'package:singverse_mobile/features/admin/admin_page.dart';
import 'package:singverse_mobile/features/admin/admin_session.dart';
import 'package:singverse_mobile/features/library/connection.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
// Replace only the WebView platform boundary; production widgets and routing
// still run. The interface comes with the locked webview_flutter dependency.
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'widget_test.dart' show FakeApi;

class TestWebViewPlatform extends WebViewPlatform {
  final controllers = <TestWebViewController>[];
  late TestNavigationDelegate navigation;
  Completer<void>? pendingSetup;

  TestWebViewController get web => controllers.last;

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final controller = TestWebViewController(params)
      ..pendingSetup = pendingSetup;
    controllers.add(controller);
    return controller;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => navigation = TestNavigationDelegate(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => TestWebViewWidget(params);
}

class TestWebViewController extends PlatformWebViewController {
  TestWebViewController(super.params) : super.implementation();

  final requests = <LoadRequestParams>[];
  final html = <String>[];
  bool hasHistory = false;
  int backs = 0, reloads = 0;
  JavaScriptMode? javaScriptMode;
  Completer<void>? pendingSetup;

  @override
  Future<void> setOnPlatformPermissionRequest(
    void Function(PlatformWebViewPermissionRequest request) onPermissionRequest,
  ) async {}

  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {
    javaScriptMode = mode;
    await pendingSetup?.future;
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}

  @override
  Future<void> loadRequest(LoadRequestParams params) async =>
      requests.add(params);

  @override
  Future<void> loadHtmlString(String value, {String? baseUrl}) async =>
      html.add(value);

  @override
  Future<bool> canGoBack() async => hasHistory;

  @override
  Future<void> goBack() async => backs++;

  @override
  Future<void> reload() async => reloads++;
}

class TestNavigationDelegate extends PlatformNavigationDelegate {
  TestNavigationDelegate(super.params) : super.implementation();

  late NavigationRequestCallback navigate;
  late PageEventCallback started, finished;
  late ProgressCallback progress;
  late WebResourceErrorCallback resourceError;
  late HttpResponseErrorCallback httpError;
  late SslAuthErrorCallback sslError;

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback callback,
  ) async => navigate = callback;

  @override
  Future<void> setOnPageStarted(PageEventCallback callback) async =>
      started = callback;

  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async =>
      finished = callback;

  @override
  Future<void> setOnProgress(ProgressCallback callback) async =>
      progress = callback;

  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async =>
      resourceError = callback;

  @override
  Future<void> setOnHttpError(HttpResponseErrorCallback callback) async =>
      httpError = callback;

  @override
  Future<void> setOnSSlAuthError(SslAuthErrorCallback callback) async =>
      sslError = callback;
}

class TestWebViewWidget extends PlatformWebViewWidget {
  TestWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) =>
      const SizedBox.expand(key: Key('admin-webview'));
}

class TestSslAuthError extends PlatformSslAuthError {
  TestSslAuthError()
    : super(certificate: null, description: 'invalid certificate');
  int cancellations = 0, bypasses = 0;

  @override
  Future<void> cancel() async => cancellations++;

  @override
  Future<void> proceed() async => bypasses++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late LocalStore store;
  late AppState state;
  late TestWebViewPlatform platform;
  late WebViewPlatform previousPlatform;
  late List<MethodCall> sessionCalls;
  Completer<void>? pendingSession;
  PlatformException? sessionFailure;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open(
      factory: databaseFactoryFfiNoIsolate,
      path: inMemoryDatabasePath,
    );
    state =
        AppState(
            api: FakeApi(),
            store: store,
            preferences: await SharedPreferences.getInstance(),
            listenPlayer: false,
          )
          ..origin = 'https://nas.example.test:18443'
          ..instanceId = 'nas-a';
    previousPlatform = WebViewPlatform.instance ?? TestWebViewPlatform();
    platform = TestWebViewPlatform();
    WebViewPlatform.instance = platform;
    sessionCalls = [];
    pendingSession = null;
    sessionFailure = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeAdminSession.channel, (call) async {
          sessionCalls.add(call);
          if (call.method == 'prepare') {
            await pendingSession?.future;
            if (sessionFailure != null) throw sessionFailure!;
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppState.player, (call) async => null);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeAdminSession.channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppState.player, null);
    WebViewPlatform.instance = previousPlatform;
    state.dispose();
    await store.close();
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: SettingsPage(state: state)));
    await tester.tap(find.byKey(const Key('open-admin')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'signed-out app opens current NAS admin with an empty web session',
    (tester) async {
      await open(tester);
      expect(find.byType(AdminPage), findsOneWidget);
      expect(find.byKey(const Key('admin-webview')), findsOneWidget);
      expect(platform.web.javaScriptMode, JavaScriptMode.unrestricted);
      final request = platform.web.requests.single;
      expect(
        request.uri.toString(),
        'https://nas.example.test:18443/admin/#/overview',
      );
      expect(request.headers, isEmpty);
      expect(request.body, isNull);
      expect(state.authenticated, isFalse);
      expect((state.api as FakeApi).requests, isEmpty);
      expect(sessionCalls.single.method, 'prepare');
      expect(sessionCalls.single.arguments, {
        'id': isNotEmpty,
        'origin': state.origin,
        'username': null,
      });
      platform.navigation.progress(60);
      await tester.pump();
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        .6,
      );
      platform.navigation.finished(request.uri.toString());
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.tap(find.byTooltip('关闭管理端'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(platform.web.html, hasLength(1));
      expect(sessionCalls.last.method, 'clear');
      expect(
        sessionCalls.last.arguments['id'],
        sessionCalls.first.arguments['id'],
      );
    },
  );

  testWidgets('current app account is synchronized before loading admin', (
    tester,
  ) async {
    state.authenticated = true;
    state.accountName = 'family';
    pendingSession = Completer<void>();
    await open(tester);
    expect(platform.controllers, isEmpty);
    expect(sessionCalls.single.arguments['username'], 'family');
    expect(sessionCalls.single.arguments['origin'], state.origin);
    expect(
      sessionCalls.single.arguments.keys,
      unorderedEquals(['id', 'origin', 'username']),
    );
    pendingSession!.complete();
    await tester.pumpAndSettle();
    expect(
      platform.web.requests.single.uri.toString(),
      '${state.origin}/admin/#/overview',
    );
    expect(platform.web.requests.single.headers, isEmpty);
    await tester.tap(find.byTooltip('刷新'));
    await tester.pumpAndSettle();
    expect(
      sessionCalls.where((call) => call.method == 'prepare'),
      hasLength(1),
    );
  });

  testWidgets('expired app session blocks old web accounts and can retry', (
    tester,
  ) async {
    state.authenticated = true;
    state.accountName = 'admin';
    sessionFailure = PlatformException(code: '401', message: '请先登录');
    await open(tester);
    expect(platform.controllers, isEmpty);
    expect(find.text('App 登录已失效，请返回设置重新登录后再打开管理端。'), findsOneWidget);
    sessionFailure = null;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(platform.web.requests, hasLength(1));
  });

  testWidgets('closing during account sync never loads the late session', (
    tester,
  ) async {
    pendingSession = Completer<void>();
    await open(tester);
    await tester.tap(find.byTooltip('关闭管理端'));
    await tester.pumpAndSettle();
    expect(sessionCalls.last.method, 'clear');
    pendingSession!.complete();
    await tester.pumpAndSettle();
    expect(platform.controllers, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching NAS during account sync discards the old page', (
    tester,
  ) async {
    pendingSession = Completer<void>();
    await open(tester);
    await state.connect('http://nas-b.test:18080');
    await tester.pumpAndSettle();
    pendingSession!.complete();
    await tester.pumpAndSettle();
    expect(platform.controllers, isEmpty);
    expect(find.text('NAS 连接已切换，请返回设置后重新打开管理端。'), findsOneWidget);
    expect(sessionCalls.last.method, 'clear');
  });

  testWidgets('logging out or changing app account unloads the admin session', (
    tester,
  ) async {
    for (final logout in [true, false]) {
      state.authenticated = true;
      state.accountName = 'admin';
      await open(tester);
      if (logout) {
        await state.logout();
      } else {
        state.accountName = 'family';
        await state.setAutomaticLogin(null);
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('admin-webview')), findsNothing);
      expect(find.text('App 登录账号已变化，请返回设置后重新打开管理端。'), findsOneWidget);
      expect(platform.web.html, hasLength(1));
      expect(sessionCalls.last.method, 'clear');
      await tester.tap(find.byTooltip('关闭管理端'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
    'missing NAS opens connection first and cancellation opens no webpage',
    (tester) async {
      state.origin = '';
      state.instanceId = '';
      await open(tester);
      expect(find.byType(ConnectionPage), findsOneWidget);
      expect(platform.controllers, isEmpty);
      Navigator.of(tester.element(find.byType(ConnectionPage))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(AdminPage), findsNothing);
      expect(platform.controllers, isEmpty);
    },
  );

  testWidgets('connecting first continues to the newly selected NAS', (
    tester,
  ) async {
    state.origin = '';
    await open(tester);
    await state.connect('http://nas-b.test:18080');
    Navigator.of(tester.element(find.byType(ConnectionPage))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(AdminPage), findsOneWidget);
    expect(
      platform.web.requests.single.uri.toString(),
      'http://nas-b.test:18080/admin/#/overview',
    );
  });

  testWidgets(
    'navigation retains scheme, host and port and blocks external targets',
    (tester) async {
      await open(tester);
      for (final path in [
        '/admin/#/library/songs',
        '/#/login',
        '/downloads/',
      ]) {
        expect(
          await platform.navigation.navigate(
            NavigationRequest(url: '${state.origin}$path', isMainFrame: true),
          ),
          NavigationDecision.navigate,
        );
      }
      for (final url in [
        'http://nas.example.test:18443/admin/',
        'https://nas.example.test/admin/',
        'https://other.test:18443/admin/',
        'https://nas.example.test.evil.test:18443/admin/',
        'https://user:password@nas.example.test:18443/admin/',
        'javascript:alert(1)',
        'file:///etc/passwd',
        'intent://admin/',
      ]) {
        expect(
          await platform.navigation.navigate(
            NavigationRequest(url: url, isMainFrame: true),
          ),
          NavigationDecision.prevent,
          reason: url,
        );
      }
      expect(find.byType(AdminPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'subresource failures preserve the page; main-frame failures retry the same URL',
    (tester) async {
      await open(tester);
      final url = '${state.origin}/admin/#/library/songs';
      platform.navigation.started(url);
      platform.navigation.resourceError(
        const WebResourceError(
          errorCode: -2,
          description: 'image failed',
          isForMainFrame: false,
        ),
      );
      await tester.pump();
      expect(find.text('重试'), findsNothing);
      platform.navigation.resourceError(
        const WebResourceError(
          errorCode: -2,
          description: 'host unavailable',
          isForMainFrame: true,
        ),
      );
      // WebView can report page-finished after a failed navigation.
      platform.navigation.finished(url);
      await tester.pumpAndSettle();
      expect(find.text('无法加载管理端，请检查 NAS 地址和网络后重试。'), findsOneWidget);
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(platform.web.requests.last.uri.toString(), url);
      expect(find.text('重试'), findsNothing);
      await tester.tap(find.byTooltip('刷新'));
      await tester.pumpAndSettle();
      expect(platform.web.reloads, 1);
    },
  );

  testWidgets('HTTP failures only replace main-frame content', (tester) async {
    await open(tester);
    HttpResponseError failure(bool mainFrame, int status) => HttpResponseError(
      request: WebResourceRequest(
        uri: Uri.parse(
          '${state.origin}${mainFrame ? '/admin/' : '/assets/cover.png'}',
        ),
      ),
      response: WebResourceResponse(uri: null, statusCode: status),
    );
    platform.navigation.httpError(failure(false, 404));
    await tester.pump();
    expect(find.text('重试'), findsNothing);
    platform.navigation.httpError(failure(true, 404));
    await tester.pumpAndSettle();
    expect(find.text('此 NAS 未提供管理端页面，请检查 NAS 服务版本或部署配置。'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    platform.navigation.httpError(failure(true, 503));
    await tester.pumpAndSettle();
    expect(find.textContaining('HTTP 503'), findsOneWidget);
  });

  testWidgets('invalid HTTPS certificates are cancelled and can be retried', (
    tester,
  ) async {
    await open(tester);
    final failure = TestSslAuthError();
    platform.navigation.sslError(failure);
    await tester.pumpAndSettle();
    expect(failure.cancellations, 1);
    expect(failure.bypasses, 0);
    expect(find.text('NAS 的 HTTPS 证书验证失败，请检查证书后重试。'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(platform.web.requests, hasLength(2));
  });

  testWidgets(
    'closing while WebView initializes never loads the NAS afterwards',
    (tester) async {
      platform.pendingSetup = Completer<void>();
      await open(tester);
      expect(platform.web.requests, isEmpty);
      await tester.tap(find.byTooltip('关闭管理端'));
      await tester.pumpAndSettle();
      platform.pendingSetup!.complete();
      await tester.pumpAndSettle();
      expect(platform.web.requests, isEmpty);
      expect(platform.web.html, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('toolbar and system back traverse web history before closing', (
    tester,
  ) async {
    await open(tester);
    platform.web.hasHistory = true;
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(platform.web.backs, 1);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(platform.web.backs, 2);
    expect(find.byType(AdminPage), findsOneWidget);
    platform.web.hasHistory = false;
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AdminPage), findsNothing);
    expect(find.byType(SettingsPage), findsOneWidget);
  });

  testWidgets('changing NAS unloads the old page and ignores late callbacks', (
    tester,
  ) async {
    await open(tester);
    await state.connect('http://nas-b.test:18080');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('admin-webview')), findsNothing);
    expect(find.text('NAS 连接已切换，请返回设置后重新打开管理端。'), findsOneWidget);
    expect(platform.web.html, hasLength(1));
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.refresh_rounded),
          )
          .onPressed,
      isNull,
    );
    platform.navigation.started('https://nas.example.test:18443/admin/');
    platform.navigation.finished('https://nas.example.test:18443/admin/');
    expect(
      await platform.navigation.navigate(
        const NavigationRequest(
          url: 'https://nas.example.test:18443/admin/',
          isMainFrame: true,
        ),
      ),
      NavigationDecision.prevent,
    );
    await tester.tap(find.text('返回设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-admin')));
    await tester.pumpAndSettle();
    expect(platform.controllers, hasLength(2));
    expect(platform.web.requests.single.uri.origin, 'http://nas-b.test:18080');
  });

  testWidgets(
    'opening during recording or mixing keeps the current take intact',
    (tester) async {
      for (final phase in ['RECORDING', 'RENDERING']) {
        state.singing = {'phase': phase, 'takeId': 'take-a'};
        await open(tester);
        expect(find.byType(AdminPage), findsNothing);
        expect(find.text('请先结束录音或等待混音完成，再打开管理端。'), findsOneWidget);
        expect(state.singingPhase, phase);
        expect(state.takeId, 'take-a');
        expect(platform.controllers, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    'admin controls fit a small screen with senior mode and large type',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      state.uiMode = UiMode.senior;
      await tester.pumpWidget(
        MaterialApp(
          theme: singVerseTheme(Brightness.light, senior: true),
          home: SettingsPage(state: state),
        ),
      );
      final entry = find.byKey(const Key('open-admin'));
      await tester.scrollUntilVisible(entry, 300);
      await tester.pumpAndSettle();
      expect(entry.hitTestable(), findsOneWidget);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      for (final tooltip in ['返回', '刷新', '关闭管理端']) {
        final button = find.byTooltip(tooltip);
        expect(button.hitTestable(), findsOneWidget);
        expect(tester.getSize(button).height, greaterThanOrEqualTo(56));
      }
      expect(find.byKey(const Key('admin-webview')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
