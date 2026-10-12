import 'package:at_client/src/client/remote_secondary.dart';
import 'package:at_client/src/storage/at_client_storage.dart';
import 'package:at_client/src/storage/remote_write_through_keystore.dart';
import 'package:at_client/src/sync/at_sync_queue.dart';
import 'package:at_client/src/sync/sync_queue_store.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';

/// The Mode E `AtClientStorage`: no local database, every read/write a round
/// trip to the atServer via the injected [remoteSecondary].
///
/// Composes stage2a's [NoopSyncQueueStore] (nothing to redeliver — delivery
/// already happened synchronously in the keystore's own retry) with stage2b's
/// [RemoteWriteThroughKeyStore].
class RemoteOnlyAtClientStorage extends AtClientStorageBase {
  RemoteOnlyAtClientStorage({
    required this.atSign,
    required this.remoteSecondary,
    this.keyStoreMaxAttempts = 3,
    super.closedByClient,
  });

  final String atSign;
  final RemoteSecondary remoteSecondary;
  final int keyStoreMaxAttempts;

  RemoteWriteThroughKeyStore? _keyStore;
  AtSyncQueue? _queue;

  /// One path per atSign, per D-13: production isolates storage by atSign
  /// alone, not by enrollment — a second storage for the same atSign is one
  /// store, not two, and [AtClientStorageBase] refuses it rather than
  /// sharing silently.
  @override
  String get location => 'remote:$atSign';

  @override
  AtKeyValueStore<String, AtData, AtMetaData?> get keyStore =>
      _keyStore ?? (throw StateError('storage for $atSign is not open'));

  @override
  AtSyncQueue get syncQueue =>
      _queue ?? (throw StateError('storage for $atSign is not open'));

  @override
  Future<void> openBackend() async {
    if (_keyStore != null) return;
    final keyStore = RemoteWriteThroughKeyStore(remoteSecondary,
        maxAttempts: keyStoreMaxAttempts);
    await keyStore.initialize();
    final queue = AtSyncQueue(atSign: atSign);
    await queue.open(store: const NoopSyncQueueStore());
    _keyStore = keyStore;
    _queue = queue;
  }

  @override
  Future<void> closeBackend() async {
    // remoteSecondary is injected, not owned by this storage — it is the
    // caller's to close, not ours.
    await _queue?.close();
  }

  @override
  Future<void> clearData() async {
    throw UnsupportedError(
        'RemoteOnlyAtClientStorage.clearData: clearing a live atServer is a '
        'destructive remote operation, not implemented in this slice');
  }
}
