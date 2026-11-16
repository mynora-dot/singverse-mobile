import 'package:flutter_test/flutter_test.dart';
import 'package:singverse_mobile/core/api.dart';
import 'package:singverse_mobile/features/tv_control/tv_page.dart';
import 'package:webview_flutter/webview_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

class SessionWebViewPlatform extends WebViewPlatform {
  late SessionWebViewController controller;

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => controller = SessionWebViewController(params);
}

class SessionWebViewController extends PlatformWebViewController {
  SessionWebViewController(super.params) : super.implementation();
  final scripts = <String>[];
  final documents = <String>[];
  bool persistentStorageCleared = false;

  @override
  Future<void> runJavaScript(String script) async => scripts.add(script);

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async =>
      documents.add(html);

  @override
  Future<void> clearLocalStorage() async => persistentStorageCleared = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'disconnect removes participation but keeps the remembered nickname',
    () async {
      final previous = WebViewPlatform.instance ?? SessionWebViewPlatform();
      final platform = SessionWebViewPlatform();
      WebViewPlatform.instance = platform;
      addTearDown(() => WebViewPlatform.instance = previous);
      final session = TvSession()
        ..controller = WebViewController()
        ..invite = TvInvite('https://nas.test', 'invitation')
        ..deviceName = '客厅电视';
      await session.disconnect();
      expect(
        platform.controller.scripts.single,
        contains("sessionStorage.removeItem('singverse-party')"),
      );
      expect(platform.controller.persistentStorageCleared, isFalse);
      expect(platform.controller.documents, hasLength(1));
      expect(session.controller, isNull);
      expect(session.invite, isNull);
      expect(session.deviceName, isNull);
    },
  );
}
