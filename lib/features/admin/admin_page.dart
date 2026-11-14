import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../app/design.dart';
import '../../core/api.dart';
import '../../core/app_state.dart';
import '../library/connection.dart';

Future<void> openAdmin(BuildContext context, AppState state) => uiTask(
  context,
  () async {
    if (state.taking || state.singingPhase == 'RENDERING') {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先结束录音或等待混音完成，再打开管理端。')));
      return;
    }
    if (state.origin.isEmpty) await openConnection(context, state);
    if (!context.mounted || state.origin.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'admin'),
        builder: (_) => AdminPage(state: state),
      ),
    );
  },
);

class AdminPage extends StatefulWidget {
  const AdminPage({super.key, required this.state});
  final AppState state;

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  late final String origin;
  late final String instanceId;
  late Uri lastUrl;
  WebViewController? controller;
  bool connectionChanged = false, loadingRequest = false, goingBack = false;
  int progress = 0;
  String? error;

  bool get active => mounted && !connectionChanged;

  @override
  void initState() {
    super.initState();
    origin = widget.state.origin;
    instanceId = widget.state.instanceId;
    widget.state.addListener(checkConnection);
    unawaited(load());
  }

  bool allows(String url) {
    final target = Uri.tryParse(url);
    return target != null &&
        ['http', 'https'].contains(target.scheme) &&
        target.hasAuthority &&
        target.userInfo.isEmpty &&
        target.origin == origin;
  }

  void checkConnection() {
    if (!active ||
        (widget.state.origin == origin &&
            widget.state.instanceId == instanceId)) {
      return;
    }
    setState(() => connectionChanged = true);
    unawaited(stopWebView(controller));
  }

  Future<void> stopWebView(WebViewController? web) async {
    if (web == null) return;
    try {
      // Unload the document, including any media it started. Web cookies stay
      // independent of the native NAS session and remembered passwords.
      await web.loadHtmlString('<html><body></body></html>');
    } catch (_) {
      // The platform view may already have been removed while closing.
    }
  }

  void fail(String message) {
    if (active) setState(() => error = message);
  }

  Future<void> load({bool refresh = false}) async {
    if (!active || loadingRequest) return;
    loadingRequest = true;
    setState(() {
      error = null;
      progress = 0;
    });
    try {
      final alreadyOpen = controller != null;
      if (controller == null) {
        lastUrl = Uri.parse('${normalizeOrigin(origin)}/admin/#/overview');
        final web = WebViewController(
          onPermissionRequest: (request) => request.deny(),
        );
        await web.setJavaScriptMode(JavaScriptMode.unrestricted);
        await web.setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (request) {
              if (!active) return NavigationDecision.prevent;
              if (allows(request.url)) return NavigationDecision.navigate;
              if (request.isMainFrame) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请在管理端中打开当前 NAS 的页面。')),
                );
              }
              return NavigationDecision.prevent;
            },
            onPageStarted: (url) {
              if (!active || !allows(url)) return;
              setState(() {
                lastUrl = Uri.parse(url);
                progress = 0;
                error = null;
              });
            },
            onProgress: (value) {
              if (active) setState(() => progress = value);
            },
            onPageFinished: (_) {
              if (active) setState(() => progress = 100);
            },
            onWebResourceError: (failure) {
              if (failure.isForMainFrame == true) {
                fail('无法加载管理端，请检查 NAS 地址和网络后重试。');
              }
            },
            onHttpError: (failure) {
              // The plugin's HTTP callback omits the frame flag. Match the
              // document URL so a missing cover or API response stays in-page.
              if (failure.request?.uri.removeFragment() !=
                  lastUrl.removeFragment()) {
                return;
              }
              final status = failure.response?.statusCode;
              fail(
                status == 404
                    ? '此 NAS 未提供管理端页面，请检查 NAS 服务版本或部署配置。'
                    : '管理端暂时无法打开${status == null ? '' : '（HTTP $status）'}，请稍后重试。',
              );
            },
            onSslAuthError: (failure) {
              unawaited(failure.cancel());
              fail('NAS 的 HTTPS 证书验证失败，请检查证书后重试。');
            },
          ),
        );
        if (!active) {
          await stopWebView(web);
          return;
        }
        setState(() => controller = web);
      }
      if (refresh && alreadyOpen) {
        await controller!.reload();
      } else {
        await controller!.loadRequest(lastUrl);
      }
    } catch (_) {
      fail('无法打开管理端，请检查 NAS 连接后重试。');
    } finally {
      loadingRequest = false;
    }
  }

  Future<void> back() async {
    if (goingBack) return;
    goingBack = true;
    try {
      final web = controller;
      if (active && web != null && await web.canGoBack()) {
        if (active) await web.goBack();
      } else if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) Navigator.of(context).pop();
    } finally {
      goingBack = false;
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(checkConnection);
    unawaited(stopWebView(controller));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(back());
    },
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回',
          onPressed: back,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('管理端', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: connectionChanged ? null : () => load(refresh: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: '关闭管理端',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: connectionChanged
            ? SingleChildScrollView(
                child: Notice(
                  'NAS 连接已切换，请返回设置后重新打开管理端。',
                  label: '返回设置',
                  action: () => Navigator.of(context).pop(),
                ),
              )
            : Column(
                children: [
                  if (progress < 100 && error == null)
                    LinearProgressIndicator(
                      value: progress / 100,
                      semanticsLabel: '正在加载管理端',
                    ),
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (controller != null)
                          WebViewWidget(controller: controller!),
                        if (error != null)
                          ColoredBox(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            child: SingleChildScrollView(
                              child: Notice(error!, action: () => load()),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    ),
  );
}
