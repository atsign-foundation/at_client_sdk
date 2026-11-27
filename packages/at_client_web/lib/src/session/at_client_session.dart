import 'dart:async';

import 'package:at_client/at_client.dart';

import '../collections/js_collections_adapter.dart';
import '../collections/item_locks.dart';
import '../exceptions.dart';
import '../log_text.dart';
import 'session_namespace.dart';
import 'session_queue.dart';

/// The parts of a notification's key, parsed once from its text: [name] and
/// its [namespace], the [sharedWith] recipient and the [sharedBy] owner, both
/// canonical atSigns, and whether the key is `public:` or `cached:`.
typedef KeyParts = ({
  String name,
  String? namespace,
  String? sharedWith,
  String sharedBy,
  bool isPublic,
  bool isCached,
});

/// A decrypted notification as a subscriber receives it; [operation] is
/// `update` or `delete`, and [keyParts] the parsed parts of [key].
typedef ReceivedNotification = ({
  String id,
  String from,
  String key,
  String? value,
  int epochMillis,
  String operation,
  KeyParts keyParts,
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

  /// Notifies the recipient of the atKey [key] (for example
  /// `@bob:note.wavi@alice`) of [value]; true only once the atServer reports
  /// it delivered. Throws an [InvalidKeyException] for key text that cannot
  /// be sent, `public:` and `cached:` included, and a
  /// [NotifyFailedException] when sending it or waiting for its status fails.
  Future<bool> notify(String key, String value);

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

  /// Stops the client and every subscription. The first call starts the
  /// teardown; every later call, concurrent or sequential, returns that same
  /// future, whether it succeeded or failed, so nothing re-runs and a close
  /// whose teardown failed stays failed and returns the same error.
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
  /// one. [lock], when given, is the open queue key the client was opened
  /// under: [close] runs its teardown inside that queue, so an open queued
  /// after it starts only once the client has left it. Null leaves the
  /// teardown unqueued, for a session a caller builds itself.
  AtClientSession(this._client,
      {required String namespace,
      void Function(String message)? warn,
      bool Function()? isNavigatorOnline,
      Stream<void>? networkChanges,
      Future<void> Function()? stop,
      ItemLocks? itemLocks,
      Set<StreamSubscription<Object?>>? subscriptions,
      String? lock})
      : _namespace = normalizeSessionNamespace(namespace),
        _itemLocks = itemLocks ?? ItemLocks(),
        _subscriptions = subscriptions ?? {},
        _warn = warn ?? _logger.warning,
        _isNavigatorOnline = isNavigatorOnline ?? (() => true),
        _stop = stop ?? _client.stop,
        _lock = lock {
    _status = _statusOf(_client.connection.current) ?? 'connecting';
    _connection =
        _client.connection.changes.listen((state) => _reportStatusOf(state));
    _network = networkChanges
        ?.listen((_) => _reportStatusOf(_client.connection.current));
  }

  static final _logger = AtSignLogger('AtClientSession');

  /// How long a collection keeps an item when the caller names no expiration.
  static const defaultExpirationMs = 7 * 24 * 3600 * 1000;

  /// How many delivered notification ids are remembered for dropping echoes.
  static const sentIdLimit = 1024;

  static final _keySegmentInvalidChars = RegExp(r'[:@\s\x00-\x1f\x7f-\x9f]');
  static final _collectionNameAllowed =
      RegExp('^(?:${Regexes.charsInEntity}|${Regexes.allowedEmoji})+\$');
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
  final String? _lock;
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

  /// [keyText] as the [AtKey] `notify` sends on: atKey text parsed once with
  /// [AtKey.fromString] and checked with [AtKeyValidators], as an incoming
  /// notification's key is (D-44). `public:` and `cached:` text is refused
  /// before the parse.
  AtKey _atKey(String keyText) {
    final parts = keyText.split(':');
    if (parts.length > 3) {
      throw InvalidKeyException(KeyRefusal.atKey);
    }
    if (parts.length == 3) {
      if (parts[0] != 'cached') {
        throw InvalidKeyException(KeyRefusal.atKey);
      }
      if (parts[1] == 'public') {
        throw InvalidKeyException(KeyRefusal.publicKey);
      }
      throw InvalidKeyException(KeyRefusal.cachedKey);
    }
    if (parts.length == 2) {
      switch (parts[0]) {
        case 'public':
          throw InvalidKeyException(KeyRefusal.publicKey);
        case 'cached':
          throw InvalidKeyException(KeyRefusal.cachedKey);
      }
    }
    final AtKey atKey;
    try {
      atKey = AtKey.fromString(keyText);
    } on Exception {
      throw InvalidKeyException(KeyRefusal.atKey);
    } on Error {
      throw InvalidKeyException(KeyRefusal.atKey);
    }
    if (atKey.sharedWith == null) {
      throw InvalidKeyException(KeyRefusal.sharedWithMissing);
    }
    // NOTE: checked as written: the parser adds a missing `@` to the
    // recipient and drops an empty namespace.
    if (!parts.first.startsWith('@') ||
        !_isKeySegment(parts.last.split('@').first)) {
      throw InvalidKeyException(KeyRefusal.atKey);
    }
    final sharedWith = _canonical(atKey.sharedWith!);
    if (sharedWith == null) {
      throw InvalidKeyException(KeyRefusal.sharedWithInvalid);
    }
    final own = _canonical(_client.getCurrentAtSign()!)!;
    final rawSharedBy = atKey.sharedBy;
    if (rawSharedBy == null || _canonical(rawSharedBy) == null) {
      throw InvalidKeyException(KeyRefusal.sharedByInvalid);
    }
    if (_canonical(rawSharedBy) != own) {
      throw InvalidKeyException(KeyRefusal.sharedByMismatch);
    }
    // Canonical forms, so the validators see what notify will send.
    atKey
      ..sharedWith = sharedWith
      ..sharedBy = own.toAtsign();
    // Not namespace-aware: at_client would otherwise fold the session's
    // namespace into the key text's namespace (`note.wavi` ->
    // `note.wavi.<app>`).
    atKey.metadata.namespaceAware = false;
    final validation = AtKeyValidators.get().validate(
      atKey.toString(),
      ValidationContext()
        ..atSign = own.toAtsign()
        ..validateOwnership = true
        ..enforceNamespace = false,
    );
    if (!validation.isValid) {
      throw InvalidKeyException(KeyRefusal.atKey);
    }
    return atKey;
  }

  @override
  Future<bool> notify(String key, String value) async {
    _open();
    final atKey = _atKey(key);
    final params = NotificationParams.forUpdate(atKey, value: value);
    // Remembered before the send: an echo can arrive before the atServer
    // reports the send, and only this client knows the id it minted.
    final rememberedId = params.id;
    _remember(rememberedId);
    final NotificationResult result;
    try {
      result = await _client.notificationService.notify(params,
          finalStatusBudget: AtNetworkTimeouts.effectiveDefault);
    } on AtException catch (e) {
      // A send that threw has no echo coming, and repeated failures must not
      // grow the set past its bound.
      _forget(rememberedId);
      _pruneSent();
      final kind = _unreached(e);
      if (kind == null) rethrow;
      throw NotifyFailedException(kind);
    }
    // A budget that ran out leaves the status queued but unknown: an echo may
    // still arrive, so the id stays. This must come before the undelivered
    // branch, which would forget it.
    if (result.unconfirmed) {
      _pruneSent();
      return false;
    }
    if (result.notificationStatusEnum == NotificationStatusEnum.delivered) {
      _pruneSent();
      return true;
    }
    // An undelivered send has no echo coming, so its id must not hold a slot
    // or suppress a later notification that reuses it. Any other status is
    // unknown, and an echo may still arrive, so the id stays. Either way the
    // prune keeps the set within its bound.
    if (result.notificationStatusEnum == NotificationStatusEnum.undelivered) {
      _forget(rememberedId);
    }
    _pruneSent();
    _open();
    if (result.atClientException != null) {
      throw NotifyFailedException(NotifyFailure.sendFailed);
    }
    return false;
  }

  /// The kind of a notify that failed with [error] because the atServer was
  /// not reached or did not answer in time; null for any other failure.
  ///
  /// Only a classification whose cause is [AtConnectionCause.unreachable] is
  /// offline: an atServer that answered, even to refuse the credentials, did
  /// reach the client.
  static NotifyFailure? _unreached(AtException error) {
    if (error is AtTimeoutException) return NotifyFailure.timeout;
    final state = classifyConnectionFailure(error);
    return state?.cause == AtConnectionCause.unreachable
        ? NotifyFailure.offline
        : null;
  }

  /// Remembers [id] until the send's outcome is known: an echo can arrive
  /// before [notify] resolves, and only a delivered send is bounded.
  void _remember(String id) {
    if (id.isEmpty) return;
    _sent.add(id);
  }

  /// Drops the ids of sends known not to be echoed: a delivered send fills a
  /// slot, so the oldest beyond [sentIdLimit] are dropped.
  void _pruneSent() {
    while (_sent.length > sentIdLimit) {
      _sent.remove(_sent.first);
    }
  }

  void _forget(String id) => _sent.remove(id);

  /// Whether [key] is longer than [maxNotificationKeyLength] UTF-16 units or
  /// holds control text, either of which stops it being delivered.
  static bool _unsafeKey(String key) =>
      key.length > maxNotificationKeyLength || hasControlText(key);

  /// The canonical atSign that sent [n] and the parts of its key, or null when
  /// [n.key] is malformed, targets another recipient, or its owner does not
  /// match [n.from]. The parts are built from the one [AtKey] parsed here, so
  /// `sharedBy` is [from]'s canonical spelling.
  static ({String from, KeyParts keyParts})? _verified(AtNotification n,
      {required String own}) {
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
    final rawRecipient = parsed.sharedWith;
    final recipient = rawRecipient == null ? null : _canonical(rawRecipient);
    if (!parsed.metadata.isPublic && rawRecipient != null) {
      if (recipient != own) return null;
    }
    return (
      from: from,
      keyParts: (
        name: parsed.key,
        namespace: parsed.namespace,
        sharedWith: recipient,
        sharedBy: owner,
        isPublic: parsed.metadata.isPublic,
        isCached: parsed.metadata.isCached,
      ),
    );
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
          if (_unsafeKey(n.key)) {
            _warn('Dropped notification ${sanitizeLogText(n.id)}: its key is '
                'too long or holds control characters');
            return null;
          }
          final verified = _verified(n, own: own);
          if (verified == null) {
            // Never the value: it is the sender's, decrypted for this client.
            _warn('Dropped notification ${sanitizeLogText(n.id)}: its sender '
                'is not the owner of its key');
            return null;
          }
          final (:from, :keyParts) = verified;
          if (from == own && _sent.contains(n.id)) return null;
          return (
            id: n.id,
            from: from,
            key: n.key,
            value: n.value,
            epochMillis: n.epochMillis,
            operation:
                n.operation?.endsWith('delete') == true ? 'delete' : 'update',
            keyParts: keyParts,
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
  /// is approved and holds `__manage` read-write. The primary enrollment,
  /// which has no record to read, holds it.
  ///
  /// An enrollment the atServer does not know, and a refusal from the
  /// atServer reading it, are refused with that exception too; every other
  /// failure reading the record reaches the caller unchanged.
  Future<void> _requireManage() async {
    _open();
    final id = _client.enrollmentId;
    if (id == null ||
        id.isEmpty ||
        id == EnrollmentConstants.primaryEnrollmentId) {
      return;
    }
    final Enrollment? record;
    try {
      record = await _managed(() => _client.enrollments.fetch(id));
    } on KeyNotFoundException {
      throw ManageAccessRequiredException();
    }
    if (record == null ||
        record.enrollmentStatus != EnrollmentStatus.approved ||
        record.namespace?[EnrollmentConstants.enrollManageNamespace] != 'rw') {
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

  /// Stops the client and every subscription. The first call starts the
  /// teardown; every later call, concurrent or sequential, returns that same
  /// future, whether it succeeded or failed, so nothing re-runs and a close
  /// whose stop failed stays failed.
  ///
  /// A keys session's close makes no time bound of its own: it awaits the
  /// client's `stop()`, whatever that takes. A passkey session's close is
  /// bounded by D-30's vault settle, the client's stop plus 10 seconds plus
  /// `AtServerAtKeysIo.lockWaitBound`.
  ///
  /// A session opened by the bridge runs its teardown inside the (atSign,
  /// enrollment) open queue it was opened under, so an open started after
  /// this close waits for it and never finds this client live. A session
  /// built without a lock closes unqueued.
  @override
  Future<void> close() => _closing ??= _tearDown();

  Future<void> _tearDown() {
    final lock = _lock;
    if (lock == null) return _tearDownNow();
    // NOTE: queuedOpen registers the teardown on the lock synchronously,
    // before _tearDownNow's first await, so a later open sees it in order.
    return queuedOpen(lock, _tearDownNow);
  }

  Future<void> _tearDownNow() async {
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
