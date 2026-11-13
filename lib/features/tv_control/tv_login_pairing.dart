import 'package:flutter/services.dart';

import '../../core/api.dart';

class TvLoginPreview {
  const TvLoginPreview(this.id, this.name);
  final String id;
  final String name;
}

/// The native bridge keeps the account session and TV credential out of Dart.
class TvLoginPairing {
  static const channel = MethodChannel('singverse/tv-pairing');

  static bool recognizes(String value) {
    final uri = Uri.tryParse(value);
    return uri?.scheme == 'singverse' && uri?.host == 'tv-login';
  }

  Future<T?> _call<T>(String method, Map<String, Object?> input) async {
    try {
      return await channel.invokeMethod<T>(method, input);
    } on PlatformException catch (failure) {
      throw ApiFailure(
        int.tryParse(failure.code) ?? 0,
        failure.message ?? '连接电视失败，请重试',
      );
    }
  }

  Future<TvLoginPreview> inspect(String qr, String origin) async {
    final value = await _call<Map<Object?, Object?>>('inspect', {
      'qr': qr,
      'origin': origin,
    });
    final id = value?['id'], name = value?['name'];
    if (id is! String ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(id) ||
        name is! String ||
        name.isEmpty) {
      throw const FormatException('电视登录码无效，请刷新后重试');
    }
    return TvLoginPreview(id, name);
  }

  Future<void> confirm(TvLoginPreview preview, String origin) =>
      _call('confirm', {'id': preview.id, 'origin': origin});

  Future<void> cancel([String? id]) async {
    try {
      await _call('cancel', {'id': id});
    } on MissingPluginException {
      // A route may be disposed after its Flutter engine has already detached.
    }
  }
}
