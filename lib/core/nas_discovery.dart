import 'package:flutter/services.dart';

import 'api.dart';

class DiscoveredNas {
  const DiscoveredNas(this.name, this.origin);
  final String name, origin;
}

class NasDiscoverySnapshot {
  const NasDiscoverySnapshot({
    this.searching = false,
    this.services = const [],
    this.error,
  });
  final bool searching;
  final List<DiscoveredNas> services;
  final String? error;

  factory NasDiscoverySnapshot.fromMap(Map<dynamic, dynamic> map) =>
      NasDiscoverySnapshot(
        searching: map['searching'] == true,
        error: map['error'] as String?,
        services: (map['services'] as List? ?? []).map((item) {
          final value = item as Map;
          return DiscoveredNas(
            value['name'] as String,
            normalizeOrigin(value['origin'] as String),
          );
        }).toList(),
      );
}

abstract interface class NasDiscovery {
  Stream<NasDiscoverySnapshot> get snapshots;
  Future<void> start();
  Future<void> stop();
}

class NativeNasDiscovery implements NasDiscovery {
  static const channel = MethodChannel('singverse/discovery');
  static const events = EventChannel('singverse/discovery-events');
  @override
  Stream<NasDiscoverySnapshot> get snapshots => events
      .receiveBroadcastStream()
      .map((value) => NasDiscoverySnapshot.fromMap(value as Map));
  @override
  Future<void> start() => channel.invokeMethod('start');
  @override
  Future<void> stop() => channel.invokeMethod('stop');
}
