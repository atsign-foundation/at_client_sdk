import 'package:at_client/src/storage/at_client_storage.dart';
import 'package:at_client/src/storage/hive/hive_at_client_storage.dart';
import 'package:at_client/src/storage/hive/hive_box_sync_queue_store.dart';
import 'package:at_client/src/sync/at_sync_queue.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';

// NOTE: the one file outside the Hive backend that names it. Everything else
// in the client works with whatever AtClientStorage it is given.

/// The storage a client opens for [atSign] when it is given none: Hive under
/// [storagePath], which the client closes when it stops.
AtClientStorage defaultStorageFor(String atSign, String storagePath) =>
    HiveAtClientStorage(
        atSign: atSign, storagePath: storagePath, closedByClient: true);

/// Where [defaultStorageFor] puts [atSign]'s store, read without creating
/// anything on disk.
String defaultStorageLocation(String atSign, String storagePath) =>
    HiveAtClientStorage.locationOf(atSign, storagePath, create: false);

/// The persistence bundle [storage] holds when it is the default storage,
/// else null.
AtPersistenceBundle? defaultStorageBundle(AtClientStorage? storage) =>
    storage is HiveAtClientStorage ? storage.bundle : null;

/// [atSign]'s sync queue for a client built around a bare keystore, which has
/// no storage of its own to hold one: on the default storage's queue box
/// under [storagePath], or on Hive's global instance when that is null.
Future<AtSyncQueue> openDefaultSyncQueue(String atSign,
        {required String? storagePath}) =>
    openHiveSyncQueue(atSign, storagePath: storagePath);
