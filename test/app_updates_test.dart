import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:singverse_mobile/core/app_updates.dart';
import 'package:singverse_mobile/features/updates/update_page.dart';

import 'widget_test.dart' show FakeApi;

class ReleaseApi extends FakeApi {
  Map<String, dynamic> release = {
    'available': true,
    'versionCode': 1001,
    'versionName': '0.1.1',
    'packageName': 'com.mynora.singverse.mobile',
    'minSdk': 24,
    'abis': ['arm64-v8a'],
    'size': 100,
    'sha256': 'a' * 64,
    'certificateSha256': 'b' * 64,
    'notes': '修复播放',
    'url': '/api/v1/client-releases/mobile/apk',
  };
  int checks = 0;
  Completer<dynamic>? response;
  @override
  Future<dynamic> request(String path, {String method = 'GET', Object? body}) {
    expect(path, '/api/v1/client-releases/mobile');
    checks++;
    return response?.future ?? Future.value(Map<String, dynamic>.from(release));
  }
}

class TestPlatform implements UpdatePlatform {
  final stream = StreamController<dynamic>.broadcast(sync: true);
  Completer<void>? pending, cancellation;
  int cancelled = 0;
  String result = 'installer';
  @override
  Stream<dynamic> get events => stream.stream;
  @override
  Future<Map<String, dynamic>> info() async => {
    'packageName': 'com.mynora.singverse.mobile',
    'versionCode': 1000,
    'versionName': '0.1.0',
    'sdk': 24,
    'abis': ['arm64-v8a'],
    'certificateSha256': 'b' * 64,
  };
  @override
  Future<void> download(Map<String, dynamic> release) async {
    await pending?.future;
  }

  @override
  Future<void> cancel() async {
    cancelled++;
    await cancellation?.future;
  }

  @override
  Future<String> install() async => result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ReleaseApi api;
  late TestPlatform native;
  late SharedPreferences prefs;
  late AppUpdates updates;
  late DateTime now;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    api = ReleaseApi();
    native = TestPlatform();
    prefs = await SharedPreferences.getInstance();
    now = DateTime(2026, 11, 12);
    updates = AppUpdates(
      api: api,
      preferences: prefs,
      platform: native,
      clock: () => now,
    );
    updates.origin = 'http://nas-a';
  });
  tearDown(() async {
    updates.dispose();
    await native.stream.close();
  });

  test('automatic checks are limited to once per NAS per 24 hours; manual bypasses', () async {
    await updates.check();
    expect(updates.prompt, isTrue);
    await updates.check();
    expect(api.checks, 1);
    await updates.check(manual: true);
    expect(api.checks, 2);
    now = now.add(const Duration(hours: 24));
    await updates.check();
    expect(api.checks, 3);
  });
  test('restoring and reconnecting the same NAS checks immediately; foreground remains throttled', () async {
    await updates.check();
    api.release['versionCode'] = 1002;
    updates.connect('http://nas-a');
    await Future<void>.delayed(Duration.zero);
    expect(api.checks, 2);
    expect(updates.release!['versionCode'], 1002);
    updates.didChangeAppLifecycleState(AppLifecycleState.paused);
    updates.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    updates.connect('http://nas-a', connection: false);
    await Future<void>.delayed(Duration.zero);
    expect(api.checks, 2);
    updates.disconnect();
    updates.connect('http://nas-a');
    await Future<void>.delayed(Duration.zero);
    expect(api.checks, 3);
    updates.dispose();
    updates = AppUpdates(
      api: api,
      preferences: prefs,
      platform: native,
      clock: () => now,
    );
    updates.connect('http://nas-a');
    await Future<void>.delayed(Duration.zero);
    expect(api.checks, 4);
    now = now.add(const Duration(hours: 24));
    updates.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(api.checks, 5);
  });
  test('skip persists for this origin/version; new version and another NAS can prompt', () async {
    await updates.check();
    await updates.skip();
    expect(updates.prompt, isFalse);
    await updates.check(manual: true);
    expect(updates.available, isTrue);
    expect(updates.skipped, isTrue);
    api.release['versionCode'] = 1002;
    await updates.check(manual: true);
    expect(updates.prompt, isTrue);
    updates.origin = 'http://nas-b';
    api.release['versionCode'] = 1001;
    await updates.check();
    expect(updates.prompt, isTrue);
  });
  test('pending skip does not dismiss a newer release', () async {
    await updates.check();
    final saving = updates.skip();
    updates.release = {...api.release, 'versionCode': 1002};
    await saving;
    expect(updates.prompt, isTrue);
  });
  test('pending cancellation cannot overwrite a disconnected state', () async {
    await updates.check();
    native.cancellation = Completer<void>();
    final cancelling = updates.cancel();
    updates.disconnect();
    native.cancellation!.complete();
    await cancelling;
    expect(updates.status, '连接家庭 NAS 后可检查更新');
  });
  test('same/older versions are never offered', () async {
    api.release['versionCode'] = 1000;
    await updates.check(manual: true);
    expect(updates.available, isFalse);
    expect(updates.status, '当前已是最新版本');
    api.release['versionCode'] = 999;
    await updates.check(manual: true);
    expect(updates.available, isFalse);
  });
  test('unavailable, unsupported Android/ABI, wrong package/signature/URL are not offered', () async {
    final valid = Map<String, dynamic>.from(api.release);
    for (final change in [
      {'available': false},
      {'minSdk': 25},
      {
        'abis': ['x86'],
      },
      {'packageName': 'other.app'},
      {'certificateSha256': 'c' * 64},
      {'url': 'https://other.invalid/app.apk'},
      {'sha256': 'broken'},
    ]) {
      api.release = {...valid, ...change};
      await updates.check(manual: true);
      expect(updates.available, isFalse, reason: change.toString());
    }
  });
  test('late check and download cannot republish after disconnect', () async {
    api.response = Completer<dynamic>();
    final pending = updates.check();
    await Future<void>.delayed(Duration.zero);
    updates.disconnect();
    api.response!.complete(api.release);
    await pending;
    expect(updates.release, isNull);
    expect(updates.checking, isFalse);
    updates.origin = 'http://nas-a';
    api.response = null;
    await updates.check(manual: true);
    native.pending = Completer<void>();
    final download = updates.download();
    updates.disconnect();
    native.pending!.complete();
    await download;
    expect(updates.ready, isFalse);
    expect(updates.release, isNull);
  });
  test(
    'progress, cancellation, retry and deferred/permission install are visible',
    () async {
      await updates.check();
      native.pending = Completer<void>();
      final download = updates.download();
      native.stream.add({
        'origin': 'http://nas-a',
        'requestGeneration': 0,
        'received': 40,
      });
      expect(updates.progress, .4);
      await updates.cancel();
      native.pending!.complete();
      await download;
      expect(updates.ready, isFalse);
      native.stream.add({
        'origin': 'http://nas-a',
        'requestGeneration': 0,
        'status': 'installer',
      });
      expect(updates.status, '已取消下载，可重新下载');
      native.pending = null;
      await updates.download();
      expect(updates.ready, isTrue);
      native.result = 'deferred';
      await updates.install();
      expect(updates.status, contains('结束录音'));
      native.result = 'permission';
      await updates.install();
      expect(updates.status, contains('允许安装'));
    },
  );
  test(
    'failed permission-return verification enables downloading again',
    () async {
      await updates.check();
      await updates.download();
      expect(updates.ready, isTrue);
      native.stream.add({
        'origin': 'http://nas-a',
        'requestGeneration': 0,
        'status': 'invalid',
        'message': '安装包大小或 SHA-256 校验失败',
      });
      expect(updates.ready, isFalse);
      expect(updates.status, contains('SHA-256'));
      await updates.download();
      expect(updates.ready, isTrue);
    },
  );
  testWidgets('update page supports large text, skip and manual download', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await updates.check();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            textScaler: TextScaler.linear(1.8),
          ),
          child: UpdatePage(updates: updates),
        ),
      ),
    );
    await tester.scrollUntilVisible(find.text('下载更新'), 160);
    await tester.pumpAndSettle();
    expect(find.text('下载更新'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('跳过此版本'), 120);
    await tester.pumpAndSettle();
    await tester.tap(find.text('跳过此版本'));
    await tester.pump();
    await tester.scrollUntilVisible(find.text('已跳过自动提醒，仍可手动更新'), 120);
    await tester.pumpAndSettle();
    expect(find.text('已跳过自动提醒，仍可手动更新'), findsOneWidget);
    expect(tester.takeException(), isNull);
    updates.didChangeAppLifecycleState(AppLifecycleState.paused);
  });
}
