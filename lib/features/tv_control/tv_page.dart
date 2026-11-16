import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../app/design.dart';
import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/models.dart';
import '../singing/actions.dart';
import 'tv_login_pairing.dart';

// A retained WebView keeps H5 sessionStorage alive when returning to native pages.
final tvSession = TvSession();

class TvSession {
  WebViewController? controller;
  TvInvite? invite;
  String? deviceName;
  Future<void> disconnect() async {
    final old = controller;
    if (old != null) {
      await old.runJavaScript(
        "sessionStorage.removeItem('singverse-party'); location.replace('/party/');",
      );
      // Keep the remembered nickname for the next scan. Only the temporary
      // participant credential belongs to the connection being closed.
      await old.loadHtmlString('<html><body></body></html>');
    }
    controller = null;
    invite = null;
    deviceName = null;
  }
}

Future<bool> prepareTvPlayback(BuildContext context, AppState state) async {
  if (!context.mounted || !await keepCurrentRecording(context, state)) {
    return false;
  }
  // Invalidate a pending song-detail request before it can open native media.
  state.cancelPendingPlay();
  // Pausing also cancels autoplay when a pending media request finishes.
  if (state.current != null ||
      state.isPlaying ||
      state.playbackState == 'PREPARING') {
    await state.command('pause');
  }
  return context.mounted;
}

Future<void> openTv(BuildContext context, AppState state) =>
    uiTask(context, () async {
      if (!context.mounted || !await prepareTvPlayback(context, state)) return;
      if (!context.mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'tv'),
          builder: (_) => TvPage(state: state),
        ),
      );
    });

class TvPage extends StatefulWidget {
  const TvPage({super.key, required this.state, this.resume = false});
  final AppState state;
  final bool resume;
  @override
  State<TvPage> createState() => _TvPageState();
}

class _TvPageState extends State<TvPage> {
  @override
  void initState() {
    super.initState();
    if (!widget.resume || tvSession.controller == null) {
      scanning = true;
      camera = createCamera();
    }
  }

  bool scanning = false, checking = false;
  final loginPairing = TvLoginPairing();
  String? loginComplete;
  int scanGeneration = 0;
  String? error;
  MobileScannerController? camera;
  MobileScannerController createCamera() {
    final controller = MobileScannerController(
      autoStart: false,
      formats: [BarcodeFormat.qrCode],
    );
    // Starting synchronously inside MobileScanner's layout would notify the
    // state builder above it while that tree is still being built.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !identical(camera, controller) || !scanning) return;
      await controller.start();
    });
    return controller;
  }

  Future<void> scan() async {
    if (!mounted) return;
    final previous = camera;
    await previous?.stop();
    if (!mounted) return;
    setState(() {
      camera = createCamera();
      scanning = true;
      loginComplete = null;
      error = null;
    });
    // MobileScanner owns a final controller in its State. Replace that State
    // before disposing the old controller, including when cancelling a login.
    await WidgetsBinding.instance.endOfFrame;
    await previous?.dispose();
  }

  Future<void> detected(String value) async {
    if (checking) return;
    setState(() => checking = true);
    try {
      if (TvLoginPairing.recognizes(value)) {
        await loginTelevision(value);
        return;
      }
      final invite = TvInvite.parse(value);
      await camera?.stop();
      final info = await widget.state.api.inspect(invite.origin) as Json;
      if (info['service'] != 'singverse' || info['apiVersion'] != 1) {
        throw const FormatException('此二维码不是兼容的 SingVerse 服务');
      }
      final preview = await widget.state.api.inspect(
        invite.origin,
        invitation: invite.token,
      ) as Json;
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('连接电视聚会'),
          content: Text(
            '${preview['deviceName']}\n${invite.origin}\n\n电视点歌会话独立于本机曲库。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('打开点歌页面'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) {
        if (mounted) await scan();
        return;
      }
      if (tvSession.invite?.origin != invite.origin ||
          tvSession.invite?.token != invite.token) {
        final web =
            WebViewController(onPermissionRequest: (request) => request.deny())
              ..setJavaScriptMode(JavaScriptMode.unrestricted)
              ..setNavigationDelegate(
                NavigationDelegate(
                  onNavigationRequest: (request) {
                    final target = Uri.tryParse(request.url);
                    return target != null &&
                            target.hasAuthority &&
                            ['http', 'https'].contains(target.scheme) &&
                            target.origin == invite.origin &&
                            target.userInfo.isEmpty &&
                            target.path.startsWith('/party/')
                        ? NavigationDecision.navigate
                        : NavigationDecision.prevent;
                  },
                  onWebResourceError: (failure) {
                    if (mounted && failure.isForMainFrame == true) {
                      setState(() => error = 'NAS 点歌页面无法连接，请重试。');
                    }
                  },
                ),
              );
        await web.loadRequest(Uri.parse(invite.url));
        tvSession.controller = web;
        tvSession.invite = invite;
        tvSession.deviceName = preview['deviceName'] as String?;
      }
      if (mounted) setState(() => scanning = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e is FormatException ? e.message : e.toString();
          scanning = true;
        });
        await camera?.stop();
      }
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  Future<void> loginTelevision(String value) async {
    final state = widget.state;
    if (!state.authenticated || state.origin.isEmpty) {
      throw const FormatException('请先在 App 登录音乐库，再扫描电视登录码');
    }
    final generation = ++scanGeneration;
    final origin = state.origin;
    await camera?.stop();
    final preview = await loginPairing.inspect(value, origin);
    try {
      if (!mounted || generation != scanGeneration) return;
      if (state.origin != origin || !state.authenticated) {
        throw const FormatException('音乐库已切换，请重新扫码');
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('连接这台电视？'),
          content: Text(
            '${preview.name}\n\n将「${state.serverName.isEmpty ? '当前音乐库' : state.serverName}」连接到电视，随后就能在大屏上点歌。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认连接'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted || generation != scanGeneration) {
        if (mounted) await scan();
        return;
      }
      if (state.origin != origin || !state.authenticated) {
        throw const FormatException('音乐库已切换，请重新扫码');
      }
      await loginPairing.confirm(preview, origin);
      if (mounted && generation == scanGeneration) {
        setState(() {
          loginComplete = preview.name;
          scanning = false;
        });
      }
    } finally {
      await loginPairing.cancel(preview.id);
    }
  }

  Future<void> back() async {
    final web = tvSession.controller;
    if (!scanning && web != null && await web.canGoBack()) {
      await web.goBack();
    } else if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    scanGeneration++;
    loginPairing.cancel();
    camera?.dispose();
    super.dispose();
  }

  Widget cameraFailure(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              Icons.camera_alt_outlined,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '还不能使用相机',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '允许相机权限后，就能扫描电视上的二维码。若已关闭权限，请到系统设置中允许相机访问。',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        FilledButton(
          key: const ValueKey('tv-camera-settings'),
          onPressed: () => uiTask(context, () async {
            await widget.state.sing('settings');
          }),
          child: const Text('打开设置'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: scan, child: const Text('重试相机')),
      ],
    ),
  );

  Widget scannerBody(
    BuildContext context,
  ) => ValueListenableBuilder<MobileScannerState>(
    valueListenable: camera!,
    builder: (context, scanner, _) => LayoutBuilder(
      builder: (context, size) => SingleChildScrollView(
        child: ContentWidth(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (tvSession.controller != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      children: [
                        Text(
                          '已连接${tvSession.deviceName ?? '电视'}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        TextButton(
                          onPressed: checking
                              ? null
                              : () async {
                                  await camera?.stop();
                                  if (mounted) {
                                    setState(() {
                                      scanning = false;
                                      error = null;
                                    });
                                  }
                                },
                          child: const Text('继续点歌'),
                        ),
                      ],
                    ),
                  ),
                if (scanner.error != null)
                  cameraFailure(context)
                else ...[
                  SizedBox(
                    key: const ValueKey('tv-scanner-preview'),
                    height: math.min(
                      size.maxWidth - 40,
                      math.max(220, size.maxHeight * .57),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: LayoutBuilder(
                        builder: (context, preview) {
                          final side = math.min(
                            244.0,
                            math.min(preview.maxWidth, preview.maxHeight) * .72,
                          );
                          final window = Rect.fromCenter(
                            center: Offset(
                              preview.maxWidth / 2,
                              preview.maxHeight / 2,
                            ),
                            width: side,
                            height: side,
                          );
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              MobileScanner(
                                key: ObjectKey(camera),
                                controller: camera,
                                scanWindow: window,
                                onDetect: (capture) {
                                  final raw =
                                      capture.barcodes.firstOrNull?.rawValue;
                                  if (raw != null) detected(raw);
                                },
                                errorBuilder: (_, _) => const SizedBox.shrink(),
                              ),
                              IgnorePointer(
                                child: CustomPaint(painter: _ScanFrame(window)),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '对准电视上的二维码',
                    key: const ValueKey('tv-scan-instructions'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '扫描登录码，将当前音乐库连接到电视；也可扫描聚会码参与点歌。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      key: const ValueKey('tv-torch'),
                      onPressed: scanner.torchState == TorchState.unavailable
                          ? null
                          : () => uiTask(context, camera!.toggleTorch),
                      icon: Icon(
                        scanner.torchState == TorchState.on
                            ? Icons.flashlight_off_rounded
                            : Icons.flashlight_on_rounded,
                        size: 20,
                      ),
                      label: Text(
                        scanner.torchState == TorchState.on ? '关闭手电筒' : '打开手电筒',
                      ),
                    ),
                  ),
                ],
                if (checking)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: LinearProgressIndicator(),
                  ),
                if (error != null)
                  Notice(error!, action: checking ? null : scan),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Theme(
    data: scanning
        ? singVerseTheme(
            Brightness.dark,
            senior: widget.state.senior,
            compact: MediaQuery.sizeOf(context).width < 375,
          )
        : Theme.of(context),
    child: Builder(
      builder: (context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) back();
        },
        child: Scaffold(
          backgroundColor: scanning ? const Color(0xFF111318) : null,
          appBar: AppBar(
            backgroundColor: scanning ? const Color(0xFF111318) : null,
            leading: IconButton(
              tooltip: '关闭',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
            ),
            title: Text(
              scanning
                  ? '扫一扫'
                  : loginComplete != null
                  ? '电视已连接'
                  : tvSession.deviceName ?? '电视点歌',
            ),
            actions: [
              if (!scanning && loginComplete == null)
                IconButton(
                  tooltip: '重新扫码',
                  onPressed: checking ? null : scan,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                ),
              if (!scanning &&
                  loginComplete == null &&
                  tvSession.controller != null)
                IconButton(
                  tooltip: '断开电视',
                  onPressed: () => uiTask(context, () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('结束电视连接？'),
                        content: const Text('结束后，可以重新扫描电视上的二维码继续点歌。'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('结束连接'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true) return;
                    await tvSession.disconnect();
                    if (mounted) await scan();
                  }),
                  icon: const Icon(Icons.link_off_rounded),
                ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: loginComplete != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.check_circle_outline_rounded,
                            size: 56,
                          ),
                          const SizedBox(height: 20),
                          Text(
                            '已连接 $loginComplete',
                            style: Theme.of(context).textTheme.titleLarge,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            '音乐库已在电视上打开，可以开始点歌了。',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 28),
                          FilledButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('完成'),
                          ),
                          TextButton(
                            onPressed: scan,
                            child: const Text('继续扫码点歌'),
                          ),
                        ],
                      ),
                    ),
                  )
                : scanning
                ? scannerBody(context)
                : tvSession.controller != null
                ? Column(
                    children: [
                      if (error != null)
                        Notice(
                          error!,
                          action: () => tvSession.controller!.reload(),
                        ),
                      Expanded(
                        child: WebViewWidget(controller: tvSession.controller!),
                      ),
                    ],
                  )
                : Notice('未连接电视，请重新扫码。', action: scan),
          ),
        ),
      ),
    ),
  );
}

class _ScanFrame extends CustomPainter {
  const _ScanFrame(this.window);
  final Rect window;

  @override
  void paint(Canvas canvas, Size size) {
    final shade = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(window, const Radius.circular(16)));
    shade.fillType = PathFillType.evenOdd;
    canvas.drawPath(
      shade,
      Paint()..color = Colors.black.withValues(alpha: .32),
    );
    final border = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final corner in [
      window.topLeft,
      window.topRight,
      window.bottomLeft,
      window.bottomRight,
    ]) {
      final dx = corner.dx == window.left ? 1.0 : -1.0;
      final dy = corner.dy == window.top ? 1.0 : -1.0;
      final path = Path()
        ..moveTo(corner.dx, corner.dy + dy * 24)
        ..lineTo(corner.dx, corner.dy + dy * 12)
        ..quadraticBezierTo(
          corner.dx,
          corner.dy,
          corner.dx + dx * 12,
          corner.dy,
        )
        ..lineTo(corner.dx + dx * 24, corner.dy);
      canvas.drawPath(path, border);
    }
  }

  @override
  bool shouldRepaint(_ScanFrame oldDelegate) => oldDelegate.window != window;
}
