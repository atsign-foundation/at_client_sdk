import 'dart:async';
import 'dart:convert';

import 'package:at_client/at_client.dart';

import '../collections/js_collections_adapter.dart';

/// A key as the JS bridge names it: [key] under [namespace] (the session's
/// own when null), shared with [sharedWith] when that is set, by [sharedBy]
/// (the session's own atSign when null). [isPublic] and [isCached] make it
/// the `public:` and `cached:` form of that key; [noNamespace] keeps the
/// session's namespace off a key that has none.
class JsKey {
  const JsKey(this.key,
      {this.namespace,
      this.sharedWith,
      this.sharedBy,
      this.isPublic = false,
      this.isCached = false,
      this.noNamespace = false});

  final String key;
  final String? namespace;
  final String? sharedWith;
  final String? sharedBy;
  final bool isPublic;
  final bool isCached;
  final bool noNamespace;
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
  /// The atSign this session acts as.
  String get atSign;

  /// Notifies [key]'s `sharedWith` of [value]; true only once the atServer
  /// reports it delivered. Throws a [BadKeyException] without `sharedWith`.
  Future<bool> notify(JsKey key, String value);

  /// Calls [onEvent] with each decrypted notification whose key matches
  /// [regex], except the echoes of those this session sent (a sent id coming
  /// from this session's own atSign); the returned function unsubscribes.
  /// An error on the notification stream goes to [onError] and the
  /// subscription carries on. A notification dropped because its sender is
  /// not the owner of its key is logged, never delivered.
  void Function() subscribe(String regex, void Function(JsNotification) onEvent,
      {required void Function(Object error) onError});

  /// Where the connection to the atServer is: `connecting`, `connected`,
  /// `waiting:network`, `waiting:server` or `waiting:auth`. The latest
  /// change wins; closing keeps the last one.
  String get status;

  /// Calls [onChange] with each later change of [status]; the returned
  /// function stops it. Throws a [SessionClosedException] after [close].
  void Function() onStatus(void Function(String status) onChange);

  /// Opens the collection [name] (qualified with the session's namespace
  /// unless it already ends in it) whose items carry the wire type tag
  /// [type]. [expirationMs] defaults to seven days; [eventSource] is
  /// `data`, `notifs` or `both`. Throws a [SessionClosedException] after
  /// [close] and rejects with a [JsCollectionsError] for a bad argument.
  Future<JsCollection> collection(String name,
      {required String type, String? eventSource, int? expirationMs});

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
  /// [warn] receives the warnings the session raises, by default through the
  /// atSign logger; [isNavigatorOnline] tells a [JsSession.status] of
  /// `waiting:network` from `waiting:server`, by default always online.
  AtClientJsSession(this._client,
      {required String namespace,
      void Function(String message)? warn,
      bool Function()? isNavigatorOnline})
      : _namespace = namespace,
        _warn = warn ?? _logger.warning,
        _isNavigatorOnline = isNavigatorOnline ?? (() => true) {
    _status = _statusOf(_client.connection.current) ?? 'connecting';
    _connection = _client.connection.changes.listen((state) {
      final next = _statusOf(state);
      if (next == null || next == _status) return;
      _status = next;
      for (final listener in [..._statusListeners]) {
        listener(next);
      }
    });
  }

  static final _logger = AtSignLogger('AtClientJsSession');

  /// How long a collection keeps an item when the caller names no expiration.
  static const defaultExpirationMs = 7 * 24 * 3600 * 1000;

  /// How many sent notification ids are remembered for dropping echoes.
  static const sentIdLimit = 1024;

  final AtClient _client;
  final String _namespace;
  final _sent = <String>{};
  final _subscriptions = <StreamSubscription<Object?>>{};
  final void Function(String message) _warn;
  final bool Function() _isNavigatorOnline;
  final _statusListeners = <void Function(String)>{};
  late StreamSubscription<AtConnectionState> _connection;
  late String _status;
  bool _closed = false;

  /// The [JsSession.status] [state] is, or null for the connection having
  /// stopped, which says nothing about the atServer.
  String? _statusOf(AtConnectionState state) {
    if (state.isOnline) return 'connected';
    if (state.isRefused) return 'waiting:auth';
    return switch (state.cause) {
      AtConnectionCause.stopped => null,
      AtConnectionCause.unattempted => 'connecting',
      AtConnectionCause.noAtServer => 'waiting:server',
      _ => _isNavigatorOnline() ? 'waiting:server' : 'waiting:network',
    };
  }

  @override
  String get atSign => _client.getCurrentAtSign()!;

  @override
  String get status => _status;

  @override
  void Function() onStatus(void Function(String status) onChange) {
    _open();
    _statusListeners.add(onChange);
    return () => _statusListeners.remove(onChange);
  }

  /// [name] qualified with [namespace] unless it already ends in it.
  static String qualified(String name, String namespace) =>
      name.endsWith('.$namespace') ? name : '$name.$namespace';

  @override
  Future<JsCollection> collection(String name,
      {required String type, String? eventSource, int? expirationMs}) async {
    _open();
    return JsCollectionsAdapter.open(_client,
        namespace: qualified(name, _namespace),
        type: type,
        expirationMs: expirationMs ?? defaultExpirationMs,
        eventSource: eventSource);
  }

  void _open() {
    if (_closed) throw SessionClosedException();
  }

  AtKey _atKey(JsKey key) {
    final sharedBy = key.sharedBy?.toAtsign() ?? _client.getCurrentAtSign()!;
    final namespace = key.noNamespace ? null : key.namespace ?? _namespace;
    final sharedWith = key.sharedWith;
    final builder = key.isPublic
        ? AtKey.public(key.key, namespace: namespace, sharedBy: sharedBy)
        : sharedWith == null
            ? AtKey.self(key.key, namespace: namespace, sharedBy: sharedBy)
            : (AtKey.shared(key.key, namespace: namespace, sharedBy: sharedBy)
              ..sharedWith(sharedWith.toAtsign()));
    // Not namespace-aware: at_client would otherwise fold the session's
    // namespace into [namespace] (`rpc.tally` -> `rpc.tally.<app>`).
    final atKey = builder.build()..metadata.namespaceAware = false;
    if (key.isCached) atKey.metadata.isCached = true;
    return atKey;
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
  void Function() subscribe(String regex, void Function(JsNotification) onEvent,
      {required void Function(Object error) onError}) {
    _open();
    final service = _client.notificationService;
    final own = _canonical(_client.getCurrentAtSign()!);
    final subscription = service
        .subscribe(regex: regex, shouldDecrypt: true)
        .map((n) => (n, _sender(n)))
        .where((e) {
      final (n, from) = e;
      if (from == null) {
        // Never the value: it is the sender's, decrypted for this client.
        _warn('Dropped notification ${jsonEncode(n.id)}: its sender '
            'is not the owner of its key');
        return false;
      }
      return !(from == own && _sent.contains(n.id));
    }).listen((e) {
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
    }, onError: (Object error) => onError(error));
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
    await _requireManage();
    return (await _managed(() => _client.enrollments.otp())).value;
  }

  @override
  Future<List<JsEnrollment>> pendingEnrollments() async {
    await _requireManage();
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

  /// Throws a [ManageAccessException] unless this session's enrollment
  /// holds `__manage` read-write. The primary enrollment, which has no
  /// grants to read, holds it.
  Future<void> _requireManage() async {
    _open();
    final grants = await _managed(() => ownGrantsOf(_client));
    if (grants != null &&
        grants[EnrollmentConstants.enrollManageNamespace] != 'rw') {
      throw ManageAccessException();
    }
  }

  Future<List<Enrollment>> _pending() =>
      _managed(() => _client.enrollments.pending());

  Future<void> _requirePending(String id) async {
    await _requireManage();
    if (!(await _pending()).any((e) => e.enrollmentId == id)) {
      throw AtEnrollmentException(
          '${_client.getCurrentAtSign()} has no pending enrollment $id');
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    unawaited(_connection.cancel());
    _statusListeners.clear();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    await _client.stop();
  }
}
