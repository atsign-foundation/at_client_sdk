import 'package:at_client/at_client.dart';

/// String values under self keys of one app: the dev harness's whole surface.
abstract interface class DevSession {
  Future<void> put(String key, String value);

  /// The value under [key], or null when there is none.
  Future<String?> get(String key);

  Future<void> delete(String key);

  /// Stops the session; a second call does nothing.
  Future<void> close();
}

/// A [DevSession] on [AtClient], keying each value as `<key>.<app>@<atSign>`.
class AtClientDevSession implements DevSession {
  final AtClient _client;
  final String _app;
  bool _closed = false;

  AtClientDevSession(this._client, {required String app}) : _app = app;

  AtKey _atKey(String key) =>
      AtKey.self(key, namespace: _app, sharedBy: _client.getCurrentAtSign()!)
          .build();

  @override
  Future<void> put(String key, String value) => _client.put(_atKey(key), value);

  @override
  Future<String?> get(String key) async {
    try {
      return (await _client.get(_atKey(key))).value as String?;
    } on KeyNotFoundException {
      return null;
    }
  }

  @override
  Future<void> delete(String key) => _client.delete(_atKey(key));

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _client.stop();
  }
}
