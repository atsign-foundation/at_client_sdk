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
}

/// The claim rules every [AtClientStorage] shares; a backend supplies
/// [openBackend] and [clearData].
abstract class AtClientStorageBase implements AtClientStorage {
  AtClient? _owner;
  String? _lastPrincipal;

  /// The `(atSign, enrollmentId)` a client acts as.
  static String principalOf(AtClient client) =>
      '${client.getCurrentAtSign()}|${client.enrollmentId ?? 'legacy'}';

  bool get isAttached => _owner != null;

  @override
  Future<void> attach(AtClient owner) async {
    if (identical(_owner, owner)) return;
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
    await openBackend();
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

  /// Opens the backend. Idempotent.
  @protected
  Future<void> openBackend();

  /// Empties keystore and queue.
  @protected
  Future<void> clearData();

  @protected
  void dropClaim() => _owner = null;
}
