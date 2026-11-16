import 'package:flutter/services.dart';

class NativeAdminSession {
  static const channel = MethodChannel('singverse/admin-session');

  static Future<void> prepare({
    required String id,
    required String origin,
    required String? username,
  }) => channel.invokeMethod<void>('prepare', {
    'id': id,
    'origin': origin,
    'username': username,
  });

  static Future<void> clear(String id) =>
      channel.invokeMethod<void>('clear', {'id': id});
}
