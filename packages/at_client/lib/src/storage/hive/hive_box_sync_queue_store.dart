import 'package:at_client/src/storage/hive/open_reporting_once.dart';
import 'package:at_client/src/sync/at_sync_queue.dart';
import 'package:at_client/src/sync/sync_queue_store.dart';
import 'package:at_persistence_secondary_server/hive.dart';
import 'package:at_utils/at_utils.dart';
import 'package:hive/hive.dart';

/// A [SyncQueueStore] on a Hive box.
class HiveBoxSyncQueueStore implements SyncQueueStore {
  HiveBoxSyncQueueStore(this._box);
  final Box<String> _box;

  /// The box [atSign]'s sync queue lives in, beside its keystore.
  static String boxNameFor(String atSign) =>
      'syncqueue_${AtUtils.getShaForAtSign(atSign)}';

  @override
  Iterable<String> get keys => _box.keys.cast<String>();
  @override
  String? get(String atKey) => _box.get(atKey);
  @override
  Future<void> put(String atKey, String record) => _box.put(atKey, record);
  @override
  Future<void> delete(String atKey) => _box.delete(atKey);
  @override
  Future<void> clear() => _box.clear();
  @override
  Future<void> close() => _box.close();
}

/// [atSign]'s sync queue, open on its box under [storagePath], or on Hive's
/// global instance when that is null.
Future<AtSyncQueue> openHiveSyncQueue(String atSign,
    {required String? storagePath}) async {
  final HiveInterface hive =
      storagePath == null ? Hive : HiveInstances.forPath(storagePath);
  final box = await openReportingOnce(
      () => hive.openBox<String>(HiveBoxSyncQueueStore.boxNameFor(atSign)));
  final queue = AtSyncQueue(atSign: atSign);
  await queue.open(store: HiveBoxSyncQueueStore(box));
  return queue;
}
