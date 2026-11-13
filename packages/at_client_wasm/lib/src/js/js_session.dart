import 'dart:async';
import 'dart:typed_data';

import 'package:at_base2e15/at_base2e15.dart';
import 'package:at_client/at_client.dart';

/// A key as the JS bridge names it: [key] under [namespace] (the session's
/// own when null), shared with [sharedWith] when that is set, by [sharedBy]
/// (the session's own atSign when null).
class JsKey {
  const JsKey(this.key, {this.namespace, this.sharedWith, this.sharedBy});

  final String key;
  final String? namespace;
  final String? sharedWith;
  final String? sharedBy;
}

/// A decrypted notification as a subscriber receives it.
typedef JsNotification = ({
  String id,
  String from,
  String key,
  String? value,
  int epochMillis,
});

/// Thrown when a [JsKey] cannot do what was asked of it, such as a notify
/// with no `sharedWith`.
class BadKeyException implements Exception {
  BadKeyException(this.reason);

  final String reason;

  @override
  String toString() => 'BadKeyException: $reason';
}

/// Thrown by every call on a [JsSession] after [JsSession.close].
class SessionClosedException implements Exception {
  @override
  String toString() => 'SessionClosedException: the session is closed';
}

/// What the JS bridge exposes of one open client.
abstract interface class JsSession {
  /// Stores a [String] or [Uint8List] under [key].
  Future<void> put(JsKey key, Object value);

  /// The [String] under [key], the bytes when it holds binary data, or null
  /// when there is no such key.
  Future<Object?> get(JsKey key);

  Future<void> delete(JsKey key);

  /// The full key strings matching [regex], by default those of the
  /// session's namespace.
  Future<List<String>> keys([String? regex]);

  /// Notifies [key]'s `sharedWith` of [value]; true only once the atServer
  /// reports it delivered. Throws a [BadKeyException] without `sharedWith`.
  Future<bool> notify(JsKey key, String value);

  /// Calls [onEvent] with each decrypted notification whose key matches
  /// [regex], except those this session sent; the returned function
  /// unsubscribes.
  void Function() subscribe(
      String regex, void Function(JsNotification) onEvent);

  /// Stops the client and every subscription; a second call does nothing.
  Future<void> close();
}

/// A [JsSession] on an [AtClient], keying each value as
/// `<key>.<namespace>@<sharedBy>` with the namespace taken verbatim.
class AtClientJsSession implements JsSession {
  AtClientJsSession(this._client, {required String namespace})
      : _namespace = namespace;

  /// How many sent notification ids are remembered for dropping echoes.
  static const sentIdLimit = 1024;

  final AtClient _client;
  final String _namespace;
  final _sent = <String>{};
  final _subscriptions = <StreamSubscription<AtNotification>>{};
  bool _closed = false;

  void _open() {
    if (_closed) throw SessionClosedException();
  }

  AtKey _atKey(JsKey key) {
    final sharedBy = key.sharedBy?.toAtsign() ?? _client.getCurrentAtSign()!;
    final namespace = key.namespace ?? _namespace;
    final sharedWith = key.sharedWith;
    final builder = sharedWith == null
        ? AtKey.self(key.key, namespace: namespace, sharedBy: sharedBy)
        : (AtKey.shared(key.key, namespace: namespace, sharedBy: sharedBy)
          ..sharedWith(sharedWith.toAtsign()));
    // Not namespace-aware: at_client would otherwise fold the session's
    // namespace into [namespace] (`rpc.tally` -> `rpc.tally.<app>`).
    return builder.build()..metadata.namespaceAware = false;
  }

  @override
  Future<void> put(JsKey key, Object value) async {
    _open();
    switch (value) {
      case String():
        await _client.put(_atKey(key), value);
      case Uint8List():
        await _client.putBinary(_atKey(key), value);
      default:
        throw ArgumentError.value(
            value.runtimeType, 'value', 'must be a String or Uint8List');
    }
  }

  @override
  Future<Object?> get(JsKey key) async {
    _open();
    final AtValue result;
    try {
      result = await _client.get(_atKey(key));
    } on KeyNotFoundException {
      return null;
    } on AtKeyNotFoundException {
      return null;
    }
    final value = result.value;
    return result.metadata?.isBinary == true && value is String
        ? Uint8List.fromList(Base2e15.decode(value))
        : value;
  }

  @override
  Future<void> delete(JsKey key) async {
    _open();
    await _client.delete(_atKey(key));
  }

  @override
  Future<List<String>> keys([String? regex]) async {
    _open();
    return _client.getKeys(regex: regex ?? '\\.${RegExp.escape(_namespace)}@');
  }

  @override
  Future<bool> notify(JsKey key, String value) async {
    _open();
    if (key.sharedWith == null) {
      throw BadKeyException('notify needs sharedWith');
    }
    final result = await _client.notificationService.notify(
        NotificationParams.forUpdate(_atKey(key), value: value),
        onSentToSecondary: (sent) => _remember(sent.notificationID));
    _remember(result.notificationID);
    if (result.notificationStatusEnum == NotificationStatusEnum.delivered) {
      return true;
    }
    if (result.atClientException case final cause?) throw cause;
    return false;
  }

  void _remember(String id) {
    _sent.add(id);
    if (_sent.length > sentIdLimit) _sent.remove(_sent.first);
  }

  @override
  void Function() subscribe(
      String regex, void Function(JsNotification) onEvent) {
    _open();
    final service = _client.notificationService;
    final subscription = service
        .subscribe(regex: regex, shouldDecrypt: true)
        .where((n) => !_sent.contains(n.id))
        .listen((n) => onEvent((
              id: n.id,
              from: n.from,
              key: n.key,
              value: n.value,
              epochMillis: n.epochMillis,
            )));
    _subscriptions.add(subscription);
    service.startListening();
    return () {
      if (_subscriptions.remove(subscription)) {
        unawaited(subscription.cancel());
      }
    };
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    await _client.stop();
  }
}
