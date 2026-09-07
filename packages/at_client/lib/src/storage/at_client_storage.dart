import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/sync/at_sync_queue.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:meta/meta.dart';

/// The local storage one [AtClient] holds: its keystore and its sync queue.
abstract class AtClientStorage {
  /// Claims this storage for [owner].
  ///
  /// Throws [StateError] if a different client holds it, or if a different
  /// principal held it last and neither [forgetPrincipal] nor [clear] has run
  /// since. The same client attaching again is a no-op.
  Future<void> attach(AtClient owner);

  /// Drops [owner]'s claim, keeping the backend open.
  Future<void> detach(AtClient owner);

  /// Whether [client] is the one currently holding this storage.
  bool isHeldBy(AtClient client);

  AtKeyValueStore<String, AtData, AtMetaData?> get keyStore;

  AtSyncQueue get syncQueue;

  /// Forgets which principal last held this storage, keeping the data.
  ///
  /// Throws [StateError] while a client is attached.
  Future<void> forgetPrincipal();

  /// Empties keystore and queue and forgets the last principal. Idempotent.
  ///
  /// A holder that clears and then writes is stamped again by [detach].
  Future<void> clear();

  /// Closes the backend. Idempotent.
  Future<void> close();

  /// Whether the client that attaches to this storage closes it on [AtClient.stop].
  ///
  /// False by default: the storage is borrowed, the client only detaches, and
  /// closing it is the caller's job. True hands the lifetime to the client,
  /// which is what an app with no teardown of its own wants — it still chooses
  /// the backend and the location, without having to close anything.
  bool get closedByClient;
}

/// The claim rules every [AtClientStorage] shares; a backend supplies
/// [location], [openBackend], [closeBackend] and [clearData].
abstract class AtClientStorageBase implements AtClientStorage {
  AtClientStorageBase({this.closedByClient = false});

  @override
  final bool closedByClient;

  AtClient? _owner;
  String? _lastPrincipal;
  bool _closed = false;

  /// The storages whose backend is open, keyed by [location].
  ///
  /// Two storages over one location are one store on disk, so the second is
  /// refused rather than left to share silently. Keyed by location and not by
  /// atSign: several clients of one atSign are legitimate so long as each was
  /// given its own location, which is how two enrollments stay isolated.
  static final Map<String, AtClientStorageBase> _openByLocation =
      <String, AtClientStorageBase>{};

  /// The `(atSign, enrollmentId)` a client acts as.
  static String principalOf(AtClient client) =>
      '${client.getCurrentAtSign()}|${client.enrollmentId ?? 'legacy'}';

  bool get isAttached => _owner != null;

  @override
  bool isHeldBy(AtClient client) => identical(_owner, client);

  /// The store this points at, in a form two storages over the same records
  /// report identically — everything that decides which records they resolve
  /// to, not only where the files sit: a backend keyed by atSign within a
  /// directory includes the atSign, since two atSigns there share nothing. An
  /// instance whose data is private to itself reports a token unique to it.
  String get location;

  @override
  Future<void> attach(AtClient owner) async {
    if (identical(_owner, owner)) return;
    if (_closed) {
      throw StateError('this storage has been closed and cannot be reopened');
    }
    final holder = _owner;
    if (holder != null) {
      throw StateError('this storage is held by ${principalOf(holder)}; a '
          'client cannot attach to storage another client holds');
    }
    final principal = principalOf(owner);
    final last = _lastPrincipal;
    if (last != null && last != principal) {
      throw StateError('this storage was last held by $last and $principal '
          'now asks for it; call forgetPrincipal() to hand it over '
          'deliberately, or clear() to empty it first');
    }
    final here = location;
    final occupant = _openByLocation[here];
    if (occupant != null && !identical(occupant, this)) {
      final held = occupant._lastPrincipal;
      throw StateError('another storage is already open at $here'
          '${held == null ? '' : ', last held by $held'}; close it before '
          'opening a second there, or give this one its own location');
    }
    // Claimed before the await, not after: two attach() calls for the same
    // location can otherwise both read no occupant and both pass the check
    // above while the first is still suspended inside openBackend().
    _openByLocation[here] = this;
    try {
      await openBackend();
    } catch (_) {
      if (identical(_openByLocation[here], this)) _openByLocation.remove(here);
      rethrow;
    }
    _owner = owner;
    _lastPrincipal = principal;
  }

  @override
  Future<void> detach(AtClient owner) async {
    if (!identical(_owner, owner)) return;
    _lastPrincipal = principalOf(owner);
    _owner = null;
  }

  @override
  Future<void> forgetPrincipal() async {
    if (_owner != null) {
      throw StateError('this storage is attached; detach the client before '
          'forgetting its principal');
    }
    _lastPrincipal = null;
  }

  @override
  Future<void> clear() async {
    await clearData();
    _lastPrincipal = null;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _owner = null;
    final here = location;
    if (identical(_openByLocation[here], this)) _openByLocation.remove(here);
    await closeBackend();
  }

  /// Opens the backend. Idempotent.
  @protected
  Future<void> openBackend();

  /// Closes the backend. Called at most once, by [close].
  @protected
  Future<void> closeBackend();

  /// Empties keystore and queue.
  @protected
  Future<void> clearData();
}
