import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Forwards VM stdout independently of Android's device log reader.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Expected the verified local VM service URL.');
    exitCode = 1;
    return;
  }
  final service = Uri.parse(arguments.single);
  if (!['127.0.0.1', 'localhost', '::1'].contains(service.host)) {
    stderr.writeln('Only a verified loopback VM service is supported.');
    exitCode = 1;
    return;
  }
  final path = service.path.endsWith('/')
      ? '${service.path}ws'
      : '${service.path}/ws';
  final socket = await WebSocket.connect(
    service
        .replace(scheme: service.scheme == 'https' ? 'wss' : 'ws', path: path)
        .toString(),
  ).timeout(const Duration(seconds: 10));
  final pending = <String, Completer<void>>{};
  final done = Completer<void>();
  final streams = {
    for (final name in ['Stdout', 'Stderr'])
      name: StreamController<List<int>>(),
  };
  final outputs = [
    for (final stream in streams.values)
      stream.stream
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen(stdout.writeln),
  ];
  var nextId = 0;
  void connectionClosed([Object? error]) {
    for (final request in pending.values) {
      if (!request.isCompleted) {
        request.completeError(error ?? StateError('VM connection closed.'));
      }
    }
    if (!done.isCompleted) done.complete();
  }

  final subscription = socket.listen(
    (message) {
      final json = jsonDecode(message as String) as Map<String, dynamic>;
      final id = json['id']?.toString();
      if (id != null && pending.containsKey(id)) {
        final request = pending.remove(id)!;
        if (json.containsKey('error')) {
          request.completeError(
            StateError('VM subscription failed: ${json['error']}'),
          );
        } else {
          request.complete();
        }
      } else if (json['method'] == 'streamNotify') {
        final params = json['params'] as Map<String, dynamic>;
        final event = params['event'] as Map<String, dynamic>;
        final bytes = event['bytes'];
        if (bytes is String) {
          streams[params['streamId']]?.add(base64Decode(bytes));
        }
      }
    },
    onDone: connectionClosed,
    onError: (Object error) {
      stderr.writeln('VM log bridge error: $error');
      connectionClosed(error);
    },
  );
  try {
    for (final name in streams.keys) {
      final id = (++nextId).toString();
      final request = Completer<void>();
      pending[id] = request;
      socket.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': id,
          'method': 'streamListen',
          'params': {'streamId': name},
        }),
      );
      await request.future.timeout(const Duration(seconds: 10));
    }
    stdout.writeln('PHONE_VM_LOG_BRIDGE_READY');
    await stdout.flush();
    await done.future;
    stderr.writeln('VM log bridge connection closed.');
    exitCode = 1;
  } finally {
    await subscription.cancel();
    await socket.close();
    for (final stream in streams.values) {
      await stream.close();
    }
    for (final output in outputs) {
      await output.cancel();
    }
    await stdout.flush();
  }
}
