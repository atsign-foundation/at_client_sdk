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

/// A decrypted notification as a subscriber receives it; [operation] is
/// `update` or `delete`.
typedef JsNotification = ({
  String id,
  String from,
  String key,
  String? value,
  int epochMillis,
  String operation,
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

/// An enrollment request awaiting a decision, as filed: its [id], the
/// [appName] and [deviceName] it names, and the [namespaces] it asks for, each
/// with its access (`r` or `rw`).
typedef JsEnrollment = ({
  String id,
  String appName,
  String deviceName,
  Map<String, String> namespaces,
});

/// Thrown by the pairing calls of a session that holds no `__manage`, which
/// only the atServer's roster-managing enrollments do.
class ManageAccessException implements Exception {
  @override
  String toString() =>
      'ManageAccessException: this session cannot manage enrollments';
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

  /// A one-time passcode a new device quotes to request enrollment.
  /// Throws a [ManageAccessException] without `__manage`.
  Future<String> otp();

  /// The requests awaiting a decision. Throws a [ManageAccessException]
  /// without `__manage`.
  Future<List<JsEnrollment>> pendingEnrollments();

  /// Approves the pending request [id] for the namespaces it asked for.
  /// Throws a [ManageAccessException] without `__manage` and an
  /// [AtEnrollmentException] when no request [id] is pending.
  Future<void> approve(String id);

  /// Denies the pending request [id]; same throws as [approve].
  Future<void> deny(String id);

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
  final _subscriptions = <StreamSubscription<Object?>>{};
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

  /// The canonical atSign that sent [n], or null when it is not the owner of
  /// the notification's key (the atSign after the key's last `@`).
  static String? _sender(AtNotification n) {
    final at = n.key.lastIndexOf('@');
    if (at < 0) return null;
    final owner = _canonical(n.key.substring(at));
    final from = _canonical(n.from);
    return owner != null && owner == from ? from : null;
  }

  /// [atSign] trimmed, lower-cased and put in `@name` form; null when it is
  /// not an atSign.
  static String? _canonical(String atSign) {
    try {
      return atSign.trim().toLowerCase().toAtsign();
    } on Exception {
      return null;
    }
  }

  @override
  void Function() subscribe(
      String regex, void Function(JsNotification) onEvent) {
    _open();
    final service = _client.notificationService;
    final subscription = service
        .subscribe(regex: regex, shouldDecrypt: true)
        .where((n) => !_sent.contains(n.id))
        .map((n) => (n, _sender(n)))
        .where((e) => e.$2 != null)
        .listen((e) {
      final (n, from) = e;
      onEvent((
        id: n.id,
        from: from!,
        key: n.key,
        value: n.value,
        epochMillis: n.epochMillis,
        operation:
            n.operation?.endsWith('delete') == true ? 'delete' : 'update',
      ));
    });
    _subscriptions.add(subscription);
    service.startListening();
    return () {
      if (_subscriptions.remove(subscription)) {
        unawaited(subscription.cancel());
      }
    };
  }

  @override
  Future<String> otp() async {
    _open();
    return (await _managed(() => _client.enrollments.otp())).value;
  }

  @override
  Future<List<JsEnrollment>> pendingEnrollments() async {
    _open();
    return [
      for (final e in await _pending())
        (
          id: e.enrollmentId!,
          appName: e.appName ?? '',
          deviceName: e.deviceName ?? '',
          namespaces: {
            for (final MapEntry(:key, :value)
                in (e.namespace ?? const <String, dynamic>{}).entries)
              key: '$value'
          },
        )
    ];
  }

  @override
  Future<void> approve(String id) async {
    await _requirePending(id);
    await _managed(() => _client.enrollments.approve(id));
  }

  @override
  Future<void> deny(String id) async {
    await _requirePending(id);
    await _managed(() => _client.enrollments.deny(id));
  }

  /// The result of [call], with the atServer's refusal of a session that
  /// holds no `__manage` as a [ManageAccessException].
  Future<T> _managed<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on UnAuthorizedException {
      throw ManageAccessException();
    }
  }

  /// The pending requests. A session without `__manage` is answered only with
  /// its own, approved record whatever the filter, so a record that is not
  /// pending shows the filter was ignored.
  Future<List<Enrollment>> _pending() async {
    final listed = await _managed(() => _client.enrollments.pending());
    if (listed.any((e) => e.enrollmentStatus != EnrollmentStatus.pending)) {
      throw ManageAccessException();
    }
    return listed;
  }

  Future<void> _requirePending(String id) async {
    _open();
    if (!(await _pending()).any((e) => e.enrollmentId == id)) {
      throw AtEnrollmentException(
          '${_client.getCurrentAtSign()} has no pending enrollment $id');
    }
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
