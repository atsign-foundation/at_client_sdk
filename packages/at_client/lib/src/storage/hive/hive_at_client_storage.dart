import 'dart:io';

import 'package:at_client/src/storage/at_client_storage.dart';
import 'package:at_client/src/storage/hive/hive_box_sync_queue_store.dart';
import 'package:at_client/src/storage/hive/open_reporting_once.dart';
import 'package:at_client/src/sync/at_sync_queue.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_persistence_secondary_server/hive.dart';
import 'package:at_utils/at_utils.dart';
import 'package:hive/hive.dart';
// ignore: implementation_imports
import 'package:hive/src/hive_impl.dart';

/// The default storage: a Hive keystore and sync queue under [storagePath].
///
/// Opening one also takes in this atSign's sync queue from where an earlier
/// release may have left it: those releases opened the queue on Hive's
/// global instance, which put it in whichever directory that instance last
/// pointed at, another atSign's store or a directory the app gave Hive. A
/// stray queue is found in a directory this process has opened a store in,
/// or the one Hive's global instance pointed at before this store opened; a
/// store that opens holding another atSign's stray queue hands it to that
/// atSign's open store. One that cannot be read is left where it is, with a
/// warning, and the store opens without it.
class HiveAtClientStorage extends AtClientStorageBase {
  HiveAtClientStorage(
      {required this.atSign, required this.storagePath, super.closedByClient});

  final String atSign;
  final String storagePath;

  static final AtSignLogger _logger = AtSignLogger('HiveAtClientStorage');

  /// Every directory a store has opened in, in this process.
  static final Set<String> _directoriesOpened = <String>{};

  /// The stores whose backend is open now, in this process.
  static final Set<HiveAtClientStorage> _open = <HiveAtClientStorage>{};

  final HiveAtPersistenceFactory _factory = HiveAtPersistenceFactory();
  AtPersistenceBundle? _bundle;
  AtSyncQueue? _queue;

  /// The store this points at: the canonical directory `HiveInstances.forPath`
  /// resolves the instance by, plus the atSign the box is named from. Both
  /// halves are needed — two atSigns under one directory are two boxes and
  /// share nothing, while one atSign under one directory is a single box
  /// however many of these point at it.
  @override
  String get location => locationOf(atSign, storagePath);

  /// The [location] of a store for [atSign] under [storagePath]. With
  /// [create] false a missing directory is not created, and gives a location
  /// no open store holds.
  static String locationOf(String atSign, String storagePath,
          {bool create = true}) =>
      '${HiveInstances.canonicalPathFor(storagePath, create: create)}::$atSign';

  /// The persistence bundle, or `null` before the first [attach].
  AtPersistenceBundle? get bundle => _bundle;

  @override
  AtKeyValueStore<String, AtData, AtMetaData?> get keyStore =>
      _openBundle.keyValueStore;

  @override
  AtSyncQueue get syncQueue {
    final q = _queue;
    if (q == null) throw StateError('storage for $atSign is not open');
    return q;
  }

  AtPersistenceBundle get _openBundle {
    final b = _bundle;
    if (b == null) throw StateError('storage for $atSign is not open');
    return b;
  }

  @override
  Future<void> openBackend() async {
    if (_bundle != null) return;
    // NOTE: read before the store opens, which re-points Hive's global
    // instance at [storagePath]. hive marks the field for tests, and nothing
    // public names the directory its global instance points at.
    // ignore: invalid_use_of_visible_for_testing_member
    final globalHome = (Hive as HiveImpl).homePath;
    final bundle = await openReportingOnce(() => _factory.initialize(atSign,
        HivePersistenceConfig.clientDefaults(storagePath: storagePath)));
    final AtSyncQueue queue;
    try {
      queue = await openHiveSyncQueue(atSign, storagePath: storagePath);
    } catch (_) {
      await bundle.close();
      rethrow;
    }
    _bundle = bundle;
    _queue = queue;

    final here = HiveInstances.canonicalPathFor(storagePath);
    final elsewhere = {
      ..._directoriesOpened,
      if (globalHome != null) HiveInstances.canonicalPathFor(globalHome),
    }..remove(here);
    for (final directory in elsewhere) {
      await _adoptStrayQueueIn(directory);
    }
    _directoriesOpened.add(here);
    _open.add(this);
    await _handOnStrayQueuesIn(here);
  }

  /// The sha this atSign's keystore and queue boxes are named from.
  String get _sha => AtUtils.getShaForAtSign(atSign);

  /// Whether [directory] holds a queue box for the atSign named by [sha] but
  /// no keystore for it, which a store of that atSign never leaves.
  static bool _holdsStrayQueue(String directory, String sha) =>
      File('$directory/syncqueue_$sha.hive').existsSync() &&
      !File('$directory/$sha.hive').existsSync();

  /// Takes in this atSign's stray queue in [directory], if there is one.
  ///
  /// A stray that cannot be opened or read is left where it is: the store
  /// opening is worth more than the writes it might hold, and the next open
  /// tries again.
  Future<void> _adoptStrayQueueIn(String directory) async {
    if (!_holdsStrayQueue(directory, _sha)) return;
    try {
      final name = HiveBoxSyncQueueStore.boxNameFor(atSign);
      final HiveInterface hive = _directoriesOpened.contains(directory)
          ? HiveInstances.forPath(directory)
          : (HiveImpl()..init(directory));
      if (hive.isBoxOpen(name)) return;
      final stray = await openReportingOnce(() => hive.openBox<String>(name));
      final taken = await syncQueue.adopt(HiveBoxSyncQueueStore(stray),
          keep: _agreesWithKeyStore);
      await stray.deleteFromDisk();
      _logger.info('$atSign: took $taken pending write(s) from a sync queue '
          'an earlier release left in $directory');
    } catch (e) {
      // NOTE: hive's own failures are Errors, so this catches everything.
      _logger.warning('$atSign: could not take in the sync queue an earlier '
          'release left in $directory, so it stays there: $e');
    }
  }

  /// Hands each stray queue in [directory] to the open store of the atSign it
  /// belongs to, when exactly one store of that atSign is open.
  Future<void> _handOnStrayQueuesIn(String directory) async {
    for (final other in _open.toList()) {
      if (identical(other, this) || !_holdsStrayQueue(directory, other._sha)) {
        continue;
      }
      if (_open.where((s) => s.atSign == other.atSign).length != 1) continue;
      await other._adoptStrayQueueIn(directory);
    }
  }

  /// Whether this store's keystore still says what [entry] would push: the
  /// record is there for an update, and gone for a delete.
  Future<bool> _agreesWithKeyStore(SyncQueueEntry entry) async {
    final exists = await keyStore.exists(entry.atKey);
    return entry.op == SyncQueueOp.delete ? !exists : exists;
  }

  @override
  Future<void> clearData() async {
    await _openBundle.clear();
    await syncQueue.clear();
  }

  @override
  Future<void> closeBackend() async {
    _open.remove(this);
    await _queue?.close();
    await _bundle?.close();
  }
}
