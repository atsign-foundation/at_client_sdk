import 'package:at_client/src/storage/hive/hive_box_sync_queue_store.dart';
import 'package:at_client/src/sync/at_sync_queue.dart';

// NOTE: the one file outside the Hive backend that names it. Everything else
// in the client works with whatever AtClientStorage it is given.

/// [atSign]'s sync queue for a local secondary built around a bare keystore,
/// which has no storage of its own to hold one: a Hive queue box under
/// [storagePath].
Future<AtSyncQueue> openDefaultSyncQueue(String atSign,
        {required String storagePath}) =>
    openHiveSyncQueue(atSign, storagePath: storagePath);
