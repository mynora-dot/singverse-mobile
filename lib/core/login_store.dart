import 'dart:convert';

import 'package:flutter/services.dart';

import 'api.dart';

class LoginRecord {
  const LoginRecord({
    required this.origin,
    required this.instanceId,
    required this.username,
    required this.name,
    required this.lastUsed,
    this.hasPassword = false,
  });

  final String origin, instanceId, username, name;
  final int lastUsed;
  final bool hasPassword;
  String get id => '$origin\n$instanceId\n$username';
  String get address => Uri.parse(origin).authority;
  String get protocol => Uri.parse(origin).scheme.toUpperCase();

  factory LoginRecord.fromJson(Map<String, dynamic> json) => LoginRecord(
    origin: normalizeOrigin(json['origin'] as String),
    instanceId: json['instanceId'] as String,
    username: json['username'] as String,
    name: json['name'] as String? ?? 'SingVerse NAS',
    lastUsed: (json['lastUsed'] as num).toInt(),
    hasPassword: json['hasPassword'] == true,
  );

  Map<String, Object> toJson() => {
    'origin': origin,
    'instanceId': instanceId,
    'username': username,
    'name': name,
    'lastUsed': lastUsed,
  };
}

abstract interface class LoginStore {
  Future<List<LoginRecord>> load();
  Future<String?> password(LoginRecord record);
  Future<void> save(LoginRecord record, {String? password});
  Future<void> remove(LoginRecord record);
  Future<void> forgetPassword(LoginRecord record);
  Future<void> forgetServerPasswords(String instanceId);
}

/// The native vault encrypts both history and passwords with Android Keystore.
/// Passwords are read only after server-info verifies the saved NAS identity.
class NativeLoginStore implements LoginStore {
  static const channel = MethodChannel('singverse/logins');

  @override
  Future<List<LoginRecord>> load() async {
    final value = await channel.invokeMethod<String>('list') ?? '[]';
    return (jsonDecode(value) as List)
        .map(
          (item) =>
              LoginRecord.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  @override
  Future<String?> password(LoginRecord record) =>
      channel.invokeMethod<String>('password', record.toJson());

  @override
  Future<void> save(LoginRecord record, {String? password}) =>
      channel.invokeMethod('save', {...record.toJson(), 'password': password});

  @override
  Future<void> remove(LoginRecord record) =>
      channel.invokeMethod('remove', record.toJson());

  @override
  Future<void> forgetPassword(LoginRecord record) =>
      channel.invokeMethod('forgetPassword', record.toJson());

  @override
  Future<void> forgetServerPasswords(String instanceId) =>
      channel.invokeMethod('forgetServerPasswords', {'instanceId': instanceId});
}

String connectionOrigin(String address, String scheme) {
  final value = address.trim();
  return normalizeOrigin(
    RegExp(r'^https?://', caseSensitive: false).hasMatch(value)
        ? value
        : '$scheme://$value',
  );
}
