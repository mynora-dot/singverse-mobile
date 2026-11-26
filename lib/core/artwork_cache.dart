import 'dart:typed_data';

typedef ArtworkBytes = ({Uint8List bytes, DateTime expiresAt});

/// Device-local byte cache. Only identical NAS, resource and revision share work.
class ArtworkCache {
  ArtworkCache({this.maxBytes = 16 * 1024 * 1024, DateTime Function()? now})
    : _now = now ?? DateTime.now;
  final int maxBytes;
  final DateTime Function() _now;
  final _images = <String, ArtworkBytes>{};
  final _pending = <String, Future<Uint8List>>{};
  int _bytes = 0, _generation = 0;

  Future<Uint8List> load(String key, Future<Uint8List> Function() read) =>
      loadPayload(key, () async {
        final bytes = await read();
        return (
          bytes: bytes,
          expiresAt: _now().add(const Duration(minutes: 5)),
        );
      });

  Future<Uint8List> loadPayload(
    String key,
    Future<ArtworkBytes> Function() read,
  ) {
    final cached = _images.remove(key);
    if (cached != null) {
      if (cached.expiresAt.isAfter(_now())) {
        _images[key] = cached;
        return Future.value(cached.bytes);
      }
      _bytes -= cached.bytes.length;
    }
    return _pending.putIfAbsent(key, () {
      final generation = _generation;
      late final Future<Uint8List> request;
      request = Future.sync(read)
          .then((payload) {
            final bytes = payload.bytes;
            if (generation == _generation &&
                payload.expiresAt.isAfter(_now()) &&
                bytes.isNotEmpty &&
                bytes.length <= maxBytes) {
              while (_bytes + bytes.length > maxBytes && _images.isNotEmpty) {
                _bytes -= _images.remove(_images.keys.first)!.bytes.length;
              }
              _images[key] = payload;
              _bytes += bytes.length;
            }
            return bytes;
          })
          .whenComplete(() {
            if (identical(_pending[key], request)) _pending.remove(key);
          });
      return request;
    });
  }

  void clear() {
    _generation++;
    _images.clear();
    _pending.clear();
    _bytes = 0;
  }
}
