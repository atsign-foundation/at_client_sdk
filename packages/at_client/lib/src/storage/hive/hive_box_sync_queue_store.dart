import 'package:at_client/src/storage/hive/open_reporting_once.dart';
import 'package:at_client/src/sync/at_sync_queue.dart';
import 'package:at_client/src/sync/sync_queue_store.dart';
import 'package:at_persistence_secondary_server/hive.dart';
import 'package:at_utils/at_utils.dart';
import 'package:hive/hive.dart';

/// A [SyncQueueStore] on a Hive box.
class HiveBoxSyncQueueStore implements SyncQueueStore {
  HiveBoxSyncQueueStore(this._box, {void Function()? onClose})
      : _onClose = onClose;
  final Box<String> _box;
  final void Function()? _onClose;

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
  Future<void> close() async {
    try {
      await _box.close();
    } finally {
      _onClose?.call();
    }
  }
}

/// The queue boxes open in this process, by directory and box name.
final Set<String> _claimed = <String>{};

/// [atSign]'s sync queue, open on its box under [storagePath].
///
/// Refused with a [StateError] while that box is open for another queue in
/// this process: two queues over one box each replay the other's writes, and
/// closing either closes both.
Future<AtSyncQueue> openHiveSyncQueue(String atSign,
    {required String storagePath}) async {
  final name = HiveBoxSyncQueueStore.boxNameFor(atSign);
  final claim = '${HiveInstances.canonicalPathFor(storagePath)}::$name';
  if (!_claimed.add(claim)) {
    throw StateError('the sync queue of $atSign under $storagePath is already '
        'open for another client; give this one storage of its own, or stop '
        'that client first');
  }
  try {
    final box = await openReportingOnce(
        () => HiveInstances.forPath(storagePath).openBox<String>(name));
    final queue = AtSyncQueue(atSign: atSign);
    await queue.open(
        store:
            HiveBoxSyncQueueStore(box, onClose: () => _claimed.remove(claim)));
    return queue;
  } catch (_) {
    _claimed.remove(claim);
    rethrow;
  }
}
