import 'package:at_client/src/storage/at_client_storage.dart';
import 'package:at_client/src/storage/hive_at_client_storage.dart';
import 'package:at_client/src/sync/at_sync_queue.dart';
import 'package:at_client/src/sync/hive_box_sync_queue_store.dart';
import 'package:at_client/src/sync/sync_queue_store.dart';
import 'package:at_persistence_secondary_server/hive.dart';
import 'package:hive/hive.dart';

/// A [HiveAtClientStorage] under [storagePath].
AtClientStorage defaultAtClientStorage(
        {required String atSign,
        required String storagePath,
        bool closedByClient = false}) =>
    HiveAtClientStorage(
        atSign: atSign,
        storagePath: storagePath,
        closedByClient: closedByClient);

/// The [HiveAtClientStorage.location] of [defaultAtClientStorage].
String? defaultStorageLocation(
        {required String atSign, required String storagePath}) =>
    HiveAtClientStorage(atSign: atSign, storagePath: storagePath).location;

/// Whether [storage] is the Hive default.
bool isDefaultStorage(AtClientStorage storage) =>
    storage is HiveAtClientStorage;

/// A Hive box named for [atSign], on the instance owning [storagePath], or on
/// the package-global `Hive` when [storagePath] is null.
Future<SyncQueueStore> defaultSyncQueueStore(
    {required String atSign, String? storagePath}) async {
  final hive = storagePath == null ? Hive : HiveInstances.forPath(storagePath);
  return HiveBoxSyncQueueStore(
      await hive.openBox<String>(AtSyncQueue.boxNameForAtSign(atSign)));
}
