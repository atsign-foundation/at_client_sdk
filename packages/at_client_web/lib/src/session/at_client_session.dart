import 'dart:async';

import 'package:at_client/at_client.dart';

import '../collections/js_collections_adapter.dart';
import '../collections/item_locks.dart';
import '../exceptions.dart';
import '../log_text.dart';
import 'session_namespace.dart';

/// A key as the JS bridge names it: [key] under [namespace] (the session's
/// own when null), shared with [sharedWith] when that is set, by [sharedBy]
/// (the session's own atSign when null). [isPublic] and [isCached] make it
/// the `public:` and `cached:` form of that key; [noNamespace] keeps the
/// session's namespace off a key that has none.
class NotifyKey {
  const NotifyKey(this.key,
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
typedef ReceivedNotification = ({
  String id,
  String from,
  String key,
  String? value,
  int epochMillis,
  String operation,
});

/// An enrollment request awaiting a decision, as filed: its [id], the
/// [appName] and [deviceName] it names, and the [namespaces] it asks for, each
/// with its access (`r` or `rw`).
typedef JsEnrollment = ({
  String id,
  String appName,
  String deviceName,
  Map<String, String> namespaces,
});

/// What the JS bridge exposes of one open client.
abstract interface class Session {
  /// The atSign this session acts as.
  String get atSign;

  /// Whether [close] has started or completed on this session.
  bool get isClosed;

  /// Notifies [key]'s `sharedWith` of [value]; true only once the atServer
  /// reports it delivered. Throws a [InvalidKeyException] without `sharedWith`.
  Future<bool> notify(NotifyKey key, String value);

  /// Calls [onEvent] with each decrypted notification whose key matches
  /// [regex], except the echoes of those this session sent (a sent id coming
  /// from this session's own atSign); the returned function unsubscribes.
  /// An error on the notification stream goes to [onError] and the
  /// subscription carries on. A notification dropped because its sender is
  /// not the owner of its key is logged, never delivered.
  void Function() subscribe(
      String regex, void Function(ReceivedNotification) onEvent,
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
  Future<ItemCollection> collection(String name,
      {required String type, String? eventSource, int? expirationMs});

  /// A one-time passcode a new device quotes to request enrollment.
  /// Throws a [ManageAccessRequiredException] without `__manage`.
  Future<String> otp();

  /// The requests awaiting a decision. Throws a [ManageAccessRequiredException]
  /// without `__manage`.
  Future<List<JsEnrollment>> pendingEnrollments();

  /// Approves the pending request [id] for the namespaces it asked for.
  /// Throws a [ManageAccessRequiredException] without `__manage` and an
  /// [AtEnrollmentException] when no request [id] is pending.
  Future<void> approve(String id);

  /// Denies the pending request [id]; same throws as [approve].
  Future<void> deny(String id);

  /// Stops the client and every subscription; concurrent calls await the same
  /// teardown.
  Future<void> close();
}

/// A [Session] on an [AtClient], keying each value as
/// `<key>.<namespace>@<sharedBy>` with the namespace folded to lower case.
class AtClientSession implements Session {
  /// [stop] ends what opened the client, by default the client's own stop;
  /// [close] awaits it. [warn] receives the warnings the session raises, by
  /// default through the atSign logger; [isNavigatorOnline] tells a
  /// [Session.status] of `waiting:network` from `waiting:server`, by
  /// default always online, and [networkChanges] says when it may have
  /// changed (each event re-reads it; by default there are none). [itemLocks]
  /// is the item lock map every collection handle shares; by default a new one.
  /// [subscriptions] is the set that holds each live notification subscription,
  /// so a test can see one leave when its stream completes; by default a new
  /// one.
  AtClientSession(this._client,
      {required String namespace,
      void Function(String message)? warn,
      bool Function()? isNavigatorOnline,
      Stream<void>? networkChanges,
      Future<void> Function()? stop,
      ItemLocks? itemLocks,
      Set<StreamSubscription<Object?>>? subscriptions})
      : _namespace = normalizeSessionNamespace(namespace),
        _itemLocks = itemLocks ?? ItemLocks(),
        _subscriptions = subscriptions ?? {},
        _warn = warn ?? _logger.warning,
        _isNavigatorOnline = isNavigatorOnline ?? (() => true),
        _stop = stop ?? _client.stop {
    _status = _statusOf(_client.connection.current) ?? 'connecting';
    _connection =
        _client.connection.changes.listen((state) => _reportStatusOf(state));
    _network = networkChanges
        ?.listen((_) => _reportStatusOf(_client.connection.current));
  }

  static final _logger = AtSignLogger('AtClientSession');

  /// How long a collection keeps an item when the caller names no expiration.
  static const defaultExpirationMs = 7 * 24 * 3600 * 1000;

  /// How many sent notification ids are remembered for dropping echoes.
  static const sentIdLimit = 1024;

  static final _keySegmentInvalidChars = RegExp(r'[:@\s\x00-\x1f\x7f-\x9f]');
  static final _collectionNameAllowed =
      RegExp('^(?:${Regexes.charsInEntity}|${Regexes.allowedEmoji})+\$');
  static final _notifyNamespacePattern = RegExp(
      '^(?:(?:${Regexes.charsInEntity}|${Regexes.allowedEmoji})+\\.)?${Regexes.charsInNamespace}\$');
  static final _notifInvalidChars = RegExp(r'[\s\x00-\x1f\x7f-\x9f]');

  final AtClient _client;
  final String _namespace;
  final _sent = <String>{};
  final Set<StreamSubscription<Object?>> _subscriptions;
  final _watchCancels = <Future<void> Function()>{};
  final _deciding = <String>{};
  final ItemLocks _itemLocks;
  final void Function(String message) _warn;
  final bool Function() _isNavigatorOnline;
  final Future<void> Function() _stop;
  final _statusListeners = <void Function(String)>{};
  late StreamSubscription<AtConnectionState> _connection;
  StreamSubscription<void>? _network;
  late String _status;
  bool _closed = false;
  Future<void>? _closing;

  /// Moves [status] to the one [state] gives and tells each listener, once per
  /// change.
  void _reportStatusOf(AtConnectionState state) {
    if (_closed) return;
    final next = _statusOf(state);
    if (next == null || next == _status) return;
    _status = next;
    for (final listener in [..._statusListeners]) {
      if (_closed || !_statusListeners.contains(listener)) continue;
      try {
        listener(next);
      } on Object catch (_) {
        _warn('Status listener threw an error');
      }
    }
  }

  /// The [Session.status] [state] is, or null for the connection having
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
  bool get isClosed => _closed;

  @override
  String get status => _status;

  @override
  void Function() onStatus(void Function(String status) onChange) {
    _open();
    _statusListeners.add(onChange);
    return () => _statusListeners.remove(onChange);
  }

  /// [name] folded to lower case and qualified with [namespace] (already
  /// folded, as the session's own is) unless it already ends in it.
  static String qualifiedCollectionName(String name, String namespace) {
    final lower = name.toLowerCase();
    return lower.endsWith('.$namespace') ? lower : '$lower.$namespace';
  }

  /// Whether [segment] can be one key or namespace segment: not empty, no
  /// leading or trailing dot, no `..`, and none of [_keySegmentInvalidChars].
  static bool _isKeySegment(String segment) =>
      segment.isNotEmpty &&
      !segment.startsWith('.') &&
      !segment.endsWith('.') &&
      !segment.contains('..') &&
      !_keySegmentInvalidChars.hasMatch(segment);

  static String _validateCollectionName(String name) {
    if (!_isKeySegment(name) || !_collectionNameAllowed.hasMatch(name)) {
      throw JsCollectionsError(CollectionFailure.invalidArgument,
          refusal: CollectionRefusal.collectionName);
    }
    return name;
  }

  @override
  Future<ItemCollection> collection(String name,
      {required String type, String? eventSource, int? expirationMs}) async {
    _open();
    final validName = _validateCollectionName(name);
    final namespace = qualifiedCollectionName(validName, _namespace);
    final expiration = expirationMs ?? defaultExpirationMs;
    // A fresh adapter per call: at_client keeps the open AtCollection and
    // its grants, and every adapter queues item operations on the one
    // session lock map.
    final adapter = await JsCollectionsAdapter.open(_client,
        namespace: namespace,
        type: type,
        expirationMs: expiration,
        eventSource: eventSource,
        locks: _itemLocks);
    _open();
    if (eventSource != 'data') {
      _client.notificationService.startListening();
    }
    return SessionBoundCollection(this, adapter);
  }

  void _open() {
    if (_closed) throw SessionClosedException();
  }

  /// [raw] as an [Atsign], or an [InvalidKeyException] carrying [refusal].
  Atsign _parseAtsign(String raw, KeyRefusal refusal) {
    try {
      return raw.toAtsign();
    } on InvalidAtSignException {
      throw InvalidKeyException(refusal);
    }
  }

  AtKey _atKey(NotifyKey key) {
    if (key.isPublic) {
      throw InvalidKeyException(KeyRefusal.publicKey);
    }
    if (key.isCached) {
      throw InvalidKeyException(KeyRefusal.cachedKey);
    }
    final rawSharedWith = key.sharedWith;
    if (rawSharedWith == null) {
      throw InvalidKeyException(KeyRefusal.sharedWithMissing);
    }
    final sharedWith =
        _parseAtsign(rawSharedWith, KeyRefusal.sharedWithInvalid);
    final own = _canonical(_client.getCurrentAtSign()!)!;
    final Atsign sharedBy;
    if (key.sharedBy != null) {
      sharedBy = _parseAtsign(key.sharedBy!, KeyRefusal.sharedByInvalid);
      if (sharedBy != own) {
        throw InvalidKeyException(KeyRefusal.sharedByMismatch);
      }
    } else {
      sharedBy = own.toAtsign();
    }
    if (!_isKeySegment(key.key)) {
      throw InvalidKeyException(KeyRefusal.keyName);
    }
    String? namespace;
    if (!key.noNamespace) {
      final rawNs = key.namespace ?? _namespace;
      if (!_isKeySegment(rawNs) || !_notifyNamespacePattern.hasMatch(rawNs)) {
        throw InvalidKeyException(KeyRefusal.namespace);
      }
      namespace = foldNamespace(rawNs);
    }
    final AtKey atKey;
    final String serialized;
    try {
      // Not namespace-aware: at_client would otherwise fold the session's
      // namespace into [namespace] (`rpc.tally` -> `rpc.tally.<app>`).
      final builder =
          AtKey.shared(key.key, namespace: namespace, sharedBy: sharedBy)
            ..sharedWith(sharedWith);
      atKey = builder.build()..metadata.namespaceAware = false;
      serialized = atKey.toString();
    } on AtException {
      throw InvalidKeyException(KeyRefusal.atKey);
    }
    final validation = AtKeyValidators.get().validate(
      serialized,
      ValidationContext()
        ..atSign = sharedBy
        ..validateOwnership = true
        ..enforceNamespace = false,
    );
    if (!validation.isValid) {
      throw InvalidKeyException(KeyRefusal.atKey);
    }
    return atKey;
  }

  @override
  Future<bool> notify(NotifyKey key, String value) async {
    _open();
    final atKey = _atKey(key);
    var remembered = false;
    final result = await _client.notificationService
        .notify(NotificationParams.forUpdate(atKey, value: value),
            onSentToSecondary: (sent) {
      remembered = true;
      _remember(sent.notificationID);
    });
    if (!remembered && result.atClientException == null) {
      _remember(result.notificationID);
    }
    if (result.notificationStatusEnum == NotificationStatusEnum.delivered) {
      return true;
    }
    _open();
    if (result.atClientException case final cause?) throw cause;
    return false;
  }

  void _remember(String id) {
    if (id.isEmpty) return;
    _sent.add(id);
    if (_sent.length > sentIdLimit) _sent.remove(_sent.first);
  }

  /// The canonical atSign that sent [n], or null when [n.key] is malformed,
  /// targets another recipient, or its owner does not match [n.from].
  static String? _verifiedSender(AtNotification n, {required String own}) {
    final from = _canonical(n.from);
    if (from == null) return null;
    if (n.key.isEmpty || _notifInvalidChars.hasMatch(n.key)) return null;
    final colonParts = n.key.split(':');
    if (colonParts.length > 3) return null;
    final String keyBody;
    if (colonParts.length == 3) {
      if (colonParts[0] != 'cached') return null;
      final target = colonParts[1];
      if (target != 'public' &&
          (!target.startsWith('@') || _canonical(target) == null)) {
        return null;
      }
      keyBody = colonParts[2];
    } else if (colonParts.length == 2) {
      final prefix = colonParts[0];
      if (prefix != 'public' &&
          (!prefix.startsWith('@') || _canonical(prefix) == null)) {
        return null;
      }
      keyBody = colonParts[1];
    } else {
      keyBody = colonParts[0];
    }
    final at = keyBody.indexOf('@');
    if (at <= 0 || at != keyBody.lastIndexOf('@') || at == keyBody.length - 1) {
      return null;
    }
    final namePart = keyBody.substring(0, at);
    if (namePart.startsWith('.') ||
        namePart.endsWith('.') ||
        namePart.contains('..')) {
      return null;
    }
    final AtKey parsed;
    try {
      parsed = AtKey.fromString(n.key);
    } on Exception {
      return null;
    } on Error {
      return null;
    }
    if (parsed.key.isEmpty) return null;
    final rawOwner = parsed.sharedBy;
    if (rawOwner == null) return null;
    final owner = _canonical(rawOwner);
    if (owner == null || owner != from) return null;
    if (!parsed.metadata.isPublic && parsed.sharedWith != null) {
      final recipient = _canonical(parsed.sharedWith!);
      if (recipient != own) return null;
    }
    return from;
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
      String regex, void Function(ReceivedNotification) onEvent,
      {required void Function(Object error) onError}) {
    _open();
    // The one place the regex is compiled. at_client matches by its own
    // text, so the compiled pattern is handed on as its source.
    final RegExp pattern;
    try {
      pattern = RegExp(regex);
    } on FormatException {
      throw InvalidArgumentException('regex');
    }
    final service = _client.notificationService;
    final own = _canonical(_client.getCurrentAtSign()!)!;
    var done = false;
    late final StreamSubscription<ReceivedNotification?> subscription;
    subscription = service
        .subscribe(regex: pattern.pattern, shouldDecrypt: true)
        .map((n) {
          final from = _verifiedSender(n, own: own);
          if (from == null) {
            // Never the value: it is the sender's, decrypted for this client.
            _warn('Dropped notification ${sanitizeLogText(n.id)}: its sender '
                'is not the owner of its key');
            return null;
          }
          if (from == own && _sent.contains(n.id)) return null;
          return (
            id: n.id,
            from: from,
            key: n.key,
            value: n.value,
            epochMillis: n.epochMillis,
            operation:
                n.operation?.endsWith('delete') == true ? 'delete' : 'update',
          );
        })
        .where((e) => e != null)
        .cast<ReceivedNotification>()
        .listen(
          (event) {
            if (_closed) return;
            onEvent(event);
          },
          onError: (Object error) {
            if (_closed) return;
            onError(error);
          },
          onDone: () {
            done = true;
            _subscriptions.remove(subscription);
          },
        );
    try {
      service.startListening();
    } catch (_) {
      _cancelQuietly(subscription);
      rethrow;
    }
    if (!done) _subscriptions.add(subscription);
    return () {
      if (_subscriptions.remove(subscription)) _cancelQuietly(subscription);
    };
  }

  /// Cancels [subscription] without waiting, warning when it fails, whether
  /// `cancel` throws or its future fails.
  void _cancelQuietly(StreamSubscription<Object?> subscription) {
    unawaited(() async {
      try {
        await subscription.cancel();
      } on Object catch (_) {
        _warn('Failed to cancel notification subscription');
      }
    }());
  }

  @override
  Future<String> otp() async {
    await _requireManage();
    _open();
    return (await _managed(() => _client.enrollments.otp())).value;
  }

  @override
  Future<List<JsEnrollment>> pendingEnrollments() async {
    await _requireManage();
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
  Future<void> approve(String id) => _decideExclusively(
      id, () => _managed(() => _client.enrollments.approve(id)));

  @override
  Future<void> deny(String id) => _decideExclusively(
      id, () => _managed(() => _client.enrollments.deny(id)));

  Future<void> _decideExclusively(
      String id, Future<void> Function() action) async {
    _open();
    if (!_deciding.add(id)) {
      throw EnrollmentInFlightException();
    }
    try {
      await _requirePending(id);
      _open();
      await action();
    } finally {
      _deciding.remove(id);
    }
  }

  /// The result of [call], with the atServer's refusal of a session that
  /// holds no `__manage` as a [ManageAccessRequiredException].
  Future<T> _managed<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on UnAuthorizedException {
      throw ManageAccessRequiredException();
    }
  }

  /// Throws a [ManageAccessRequiredException] unless this session's enrollment
  /// holds `__manage` read-write. The primary enrollment, which has no
  /// grants to read, holds it.
  Future<void> _requireManage() async {
    _open();
    final grants = await _managed(() => ownGrantsOf(_client));
    if (grants != null &&
        grants[EnrollmentConstants.enrollManageNamespace] != 'rw') {
      throw ManageAccessRequiredException();
    }
  }

  Future<List<Enrollment>> _pending() =>
      _managed(() => _client.enrollments.pending());

  Future<void> _requirePending(String id) async {
    await _requireManage();
    if (!(await _pending()).any((e) => e.enrollmentId == id)) {
      throw AtEnrollmentException(
          '${_client.getCurrentAtSign()} has no pending enrollment');
    }
  }

  @override
  Future<void> close() => _closing ??= _tearDown().catchError((Object e) {
        // A failed teardown may be tried again; the next close() re-runs it.
        _closing = null;
        throw e;
      });

  Future<void> _tearDown() async {
    _closed = true;
    _itemLocks.clear();
    _statusListeners.clear();
    for (final cancel in [_connection.cancel, _network?.cancel]) {
      try {
        await cancel?.call();
      } on Object catch (_) {
        _warn('Failed to cancel status subscription on close');
      }
    }
    for (final subscription in [..._subscriptions]) {
      try {
        await subscription.cancel();
      } on Object catch (_) {
        _warn('Failed to cancel notification subscription on close');
      }
    }
    _subscriptions.clear();
    for (final cancelWatch in [..._watchCancels]) {
      try {
        await cancelWatch();
      } on Object catch (_) {
        _warn('Failed to cancel collection watch on close');
      }
    }
    _watchCancels.clear();
    await _stop();
  }
}

class SessionBoundCollection implements ItemCollection {
  SessionBoundCollection(this._session, this._inner);

  final AtClientSession _session;
  final ItemCollection _inner;

  @override
  Future<JsItem> create(Map<String, dynamic> data,
      {String? id, List<String> sharedWith = const []}) async {
    _session._open();
    return _inner.create(data, id: id, sharedWith: sharedWith);
  }

  @override
  Future<JsItem?> get(JsItemAddress address) async {
    _session._open();
    return _inner.get(address);
  }

  @override
  Future<JsListing> list() async {
    _session._open();
    return _inner.list();
  }

  @override
  Future<JsListing> query(List<JsWhereClause> clauses) async {
    _session._open();
    return _inner.query(clauses);
  }

  @override
  Future<JsItem> update(
      JsItemAddress address, Map<String, dynamic> data) async {
    _session._open();
    return _inner.update(address, data);
  }

  @override
  Future<JsItem> share(JsItemAddress address, List<String> atSigns) async {
    _session._open();
    return _inner.share(address, atSigns);
  }

  @override
  Future<void> remove(JsItemAddress address, {bool cascade = false}) async {
    _session._open();
    return _inner.remove(address, cascade: cascade);
  }

  @override
  Future<void> Function() watch(
    void Function(JsEvent event) onEvent, {
    required void Function(JsCollectionsError error) onError,
  }) {
    _session._open();
    late final Future<void> Function() cancel;
    cancel = _inner.watch(
      (event) {
        if (_session.isClosed) return;
        onEvent(event);
      },
      onError: (error) {
        if (_session.isClosed) return;
        onError(error);
      },
    );
    _session._watchCancels.add(cancel);
    return () async {
      _session._watchCancels.remove(cancel);
      await cancel();
    };
  }
}
