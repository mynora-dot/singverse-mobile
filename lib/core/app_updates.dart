import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

abstract interface class UpdatePlatform {
  Future<Map<String, dynamic>> info();
  Future<void> download(Map<String, dynamic> release);
  Future<void> cancel();
  Future<String> install();
  Stream<dynamic> get events;
}

class NativeUpdatePlatform implements UpdatePlatform {
  static const channel = MethodChannel('singverse/updates');
  @override
  Stream<dynamic> get events =>
      const EventChannel('singverse/update-events').receiveBroadcastStream();
  @override
  Future<Map<String, dynamic>> info() async => Map<String, dynamic>.from(
    (await channel.invokeMethod<Map<dynamic, dynamic>>('info'))!,
  );
  @override
  Future<void> download(Map<String, dynamic> release) =>
      channel.invokeMethod<void>('download', release);
  @override
  Future<void> cancel() => channel.invokeMethod<void>('cancel');
  @override
  Future<String> install() async =>
      await channel.invokeMethod<String>('install') ?? 'deferred';
}

/// Only the household NAS connection drives updates; party QR sessions never do.
class AppUpdates extends ChangeNotifier with WidgetsBindingObserver {
  AppUpdates({
    required this.api,
    required this.preferences,
    UpdatePlatform? platform,
    this.enabled = true,
    DateTime Function()? clock,
  }) : platform = platform ?? NativeUpdatePlatform(),
       clock = clock ?? DateTime.now {
    if (enabled) {
      WidgetsBinding.instance.addObserver(this);
      _events = this.platform.events.listen(_event, onError: (Object _) {});
    }
  }
  final NasApi api;
  final SharedPreferences preferences;
  final UpdatePlatform platform;
  final bool enabled;
  final DateTime Function() clock;
  StreamSubscription<dynamic>? _events;
  Timer? _timer;
  String origin = '', status = '连接家庭 NAS 后可检查更新';
  Map<String, dynamic>? release, installed;
  bool checking = false, downloading = false, ready = false, dismissed = false;
  int received = 0, _generation = 0;
  bool _disposed = false, _foreground = true;
  static const interval = Duration(hours: 24);
  bool get available => release != null;
  bool get skipped =>
      release != null &&
      preferences.getInt('update-skip:$origin') == release!['versionCode'];
  bool get prompt =>
      available && !skipped && !dismissed && !downloading && !ready;
  String get currentVersion => installed?['versionName']?.toString() ?? '读取中';
  double? get progress =>
      release == null ? null : received / (release!['size'] as num);

  void connect(String next, {bool connection = true}) {
    if (!enabled || _disposed || next.isEmpty) return;
    if (origin != next) {
      _generation++;
      unawaited(platform.cancel().catchError((Object _) {}));
      origin = next;
      status = '已连接家庭 NAS，可手动检查更新';
      release = null;
      ready = false;
      downloading = false;
      checking = false;
      dismissed = false;
    }
    unawaited(check(connection: connection));
  }

  void disconnect() {
    _generation++;
    _timer?.cancel();
    origin = '';
    release = null;
    ready = false;
    downloading = false;
    checking = false;
    dismissed = false;
    status = '连接家庭 NAS 后可检查更新';
    if (enabled) unawaited(platform.cancel().catchError((Object _) {}));
    if (!_disposed) notifyListeners();
  }

  bool _current(int ticket, String server) =>
      !_disposed && ticket == _generation && server == origin;

  Future<void> check({bool manual = false, bool connection = false}) async {
    if (!enabled || _disposed || origin.isEmpty || checking || downloading) {
      return;
    }
    final last = preferences.getInt('update-check:$origin');
    if (!manual &&
        !connection &&
        last != null &&
        clock().millisecondsSinceEpoch - last < interval.inMilliseconds) {
      if (installed == null) {
        final ticket = _generation, server = origin;
        try {
          final local = await platform.info();
          if (_current(ticket, server)) {
            installed = local;
            notifyListeners();
          }
        } catch (_) {}
      }
      _schedule();
      return;
    }
    final ticket = _generation, server = origin;
    checking = true;
    if (manual) status = '正在检查更新…';
    notifyListeners();
    try {
      final local = await platform.info();
      final value = Map<String, dynamic>.from(
        await api.request('/api/v1/client-releases/mobile') as Map,
      );
      if (!_current(ticket, server)) return;
      installed = local;
      Map<String, dynamic>? candidate;
      if (value['available'] == true) {
        final code = value['versionCode'];
        if (code is! int ||
            code < 1 ||
            value['versionName'] is! String ||
            value['packageName'] != local['packageName'] ||
            value['url'] != '/api/v1/client-releases/mobile/apk' ||
            value['size'] is! int ||
            (value['size'] as int) <= 0 ||
            (value['size'] as int) > 268435456 ||
            value['minSdk'] is! int ||
            value['abis'] is! List ||
            !RegExp(r'^[a-f0-9]{64}$')
                .hasMatch(value['sha256']?.toString() ?? '') ||
            !RegExp(r'^[a-f0-9]{64}$')
                .hasMatch(value['certificateSha256']?.toString() ?? '')) {
          throw const FormatException('NAS 安装包信息无效');
        }
        if (code > (local['versionCode'] as int)) {
          if ((value['minSdk'] as int) > (local['sdk'] as int)) {
            throw const FormatException('新版本不支持此手机的 Android 版本');
          }
          final abis = value['abis'] as List;
          if (abis.isNotEmpty &&
              !abis.contains('universal') &&
              !abis.any((abi) => (local['abis'] as List).contains(abi))) {
            throw const FormatException('新版本不支持此手机的处理器');
          }
          if (value['certificateSha256'] != local['certificateSha256']) {
            throw const FormatException('新版本签名与当前应用不同，无法覆盖安装');
          }
          candidate = value;
        }
      }
      if (release?['versionCode'] != candidate?['versionCode']) {
        ready = false;
        dismissed = false;
      }
      release = candidate;
      status = candidate != null
          ? '发现新版本 ${candidate['versionName']}'
          : value['available'] == true
          ? '当前已是最新版本'
          : 'NAS 尚未提供手机安装包';
      await preferences.setInt(
        'update-check:$server',
        clock().millisecondsSinceEpoch,
      );
    } catch (e) {
      if (_current(ticket, server)) {
        release = null;
        ready = false;
        status = e is PlatformException
            ? e.message ?? '检查更新失败，请重试'
            : e.toString();
        // Failed checks retry after 24 hours in the foreground; manual retry is immediate.
        await preferences.setInt(
          'update-check:$server',
          clock().millisecondsSinceEpoch,
        );
      }
    } finally {
      if (_current(ticket, server)) {
        checking = false;
        _schedule();
        notifyListeners();
      }
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (!enabled || !_foreground || origin.isEmpty || _disposed) {
      return;
    }
    final last =
        preferences.getInt('update-check:$origin') ??
        clock().millisecondsSinceEpoch;
    final remaining =
        interval.inMilliseconds - (clock().millisecondsSinceEpoch - last);
    _timer = Timer(
      Duration(milliseconds: remaining > 0 ? remaining : 1),
      () => unawaited(check()),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      unawaited(check());
    } else {
      _timer?.cancel();
    }
  }

  Future<void> skip() async {
    if (release == null) return;
    final ticket = _generation, server = origin;
    final code = release!['versionCode'] as int;
    await preferences.setInt('update-skip:$server', code);
    if (!_current(ticket, server) || release?['versionCode'] != code) return;
    dismissed = true;
    notifyListeners();
  }

  void later() {
    dismissed = true;
    notifyListeners();
  }

  Future<void> download() async {
    if (release == null || downloading || checking || _disposed) return;
    final ticket = _generation, server = origin;
    downloading = true;
    ready = false;
    received = 0;
    status = '正在下载并校验安装包…';
    notifyListeners();
    try {
      await platform.download({...release!, 'requestGeneration': ticket});
      if (!_current(ticket, server)) return;
      ready = true;
      status = '安装包已校验，可确认安装';
    } catch (e) {
      if (_current(ticket, server)) {
        status = e is PlatformException
            ? e.message ?? '下载失败，请重试'
            : e.toString();
      }
    } finally {
      if (_current(ticket, server)) {
        downloading = false;
        _schedule();
        notifyListeners();
      }
    }
  }

  Future<void> cancel() async {
    final ticket = ++_generation, server = origin;
    await platform.cancel();
    if (!_current(ticket, server)) return;
    downloading = false;
    ready = false;
    status = '已取消下载，可重新下载';
    _schedule();
    if (!_disposed) notifyListeners();
  }

  Future<void> install() async {
    if (!ready) return;
    final ticket = _generation, server = origin;
    try {
      final result = await platform.install();
      if (!_current(ticket, server)) return;
      status = switch (result) {
        'permission' => '请允许安装此来源应用，返回后将继续安装',
        'deferred' => '请先结束录音、混音或导出，再点击安装',
        _ => '请在系统安装页面确认更新',
      };
    } catch (e) {
      if (!_current(ticket, server)) return;
      ready = false;
      status = e is PlatformException
          ? e.message ?? '无法打开安装程序，请重新下载'
          : e.toString();
    }
    if (!_disposed) notifyListeners();
  }

  void _event(dynamic value) {
    if (_disposed ||
        value is! Map ||
        value['origin'] != origin ||
        value['requestGeneration'] != _generation) {
      return;
    }
    if (value['received'] is num && downloading) {
      received = (value['received'] as num).toInt();
    }
    if (value['status'] == 'installer') status = '请在系统安装页面确认更新';
    if (value['status'] == 'deferred') status = '请先结束录音、混音或导出，再点击安装';
    if (value['status'] == 'invalid') {
      ready = false;
      status = value['message'] is String
          ? value['message'] as String
          : '安装包校验失败，请重新下载';
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    if (enabled) {
      WidgetsBinding.instance.removeObserver(this);
      unawaited(_events?.cancel());
      unawaited(platform.cancel().catchError((Object _) {}));
    }
    super.dispose();
  }
}
