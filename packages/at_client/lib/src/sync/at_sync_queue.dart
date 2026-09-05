import 'dart:collection';
import 'dart:convert';

import 'package:at_client/src/sync/sync_queue_store.dart';
import 'package:at_utils/at_utils.dart';
import 'package:hive/hive.dart';
import 'package:at_persistence_secondary_server/hive.dart';
import 'package:meta/meta.dart';

/// On-the-wire op carried in the sync queue's persisted record. The
/// names map 1:1 to [CommitOp] (from `at_persistence_secondary_server`)
/// — we use a separate enum here so the sync queue stays decoupled from
/// the commit-log type system. The string form on disk is the enum
/// `name` (e.g. `"updateAll"`).
enum SyncQueueOp { update, updateAll, updateMeta, delete }

/// A single persisted entry on the sync queue. There is at most one
/// record per atKey by construction (the persisted box is keyed by the
/// atKey string and a second write overwrites the first).
class SyncQueueEntry {
  /// AtKey string in canonical form, e.g. `@bob:foo.bar.demos@alice`.
  /// This is also the persistence key.
  final String atKey;

  /// The most recent op for [atKey].
  final SyncQueueOp op;

  /// `DateTime.now().millisecondsSinceEpoch` at the moment of the most
  /// recent enqueue for [atKey]. Used for ordering on startup replay.
  final int ts;

  /// Monotonic per-queue enqueue counter, stamped by [AtSyncQueue.enqueue].
  ///
  /// This is the identity a drain uses to remove exactly the version it
  /// pushed. `ts` cannot serve: it is milliseconds, and an update followed by
  /// a delete of the same key lands well inside one millisecond — the exact
  /// pair the removal must tell apart. Entries persisted before this field
  /// existed read back as 0.
  final int seq;

  SyncQueueEntry({
    required this.atKey,
    required this.op,
    required this.ts,
    this.seq = 0,
  });

  Map<String, dynamic> _toJson() =>
      <String, dynamic>{'op': op.name, 'ts': ts, 'seq': seq};

  String _serialise() => jsonEncode(_toJson());

  static SyncQueueEntry _deserialise(String atKey, String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    final opName = map['op'] as String;
    final op = SyncQueueOp.values.firstWhere(
      (e) => e.name == opName,
      orElse: () => throw FormatException(
        'Unknown SyncQueueOp "$opName" for $atKey in sync queue',
      ),
    );
    return SyncQueueEntry(
      atKey: atKey,
      op: op,
      ts: map['ts'] as int,
      seq: (map['seq'] as int?) ?? 0,
    );
  }
}

/// Persisted + in-memory queue of pending client→server writes for one
/// atSign.
///
/// **Persistence**: a Hive box named `syncqueue_<sha256(atSign)>` in
/// the same Hive directory the keystore uses
/// ([AtClientPreference.hiveStoragePath]). The box is keyed by the
/// AtKey's canonical string form; values are JSON-encoded
/// `{"op": "<SyncQueueOp.name>", "ts": <ms>}`. By construction at most
/// one record exists per atKey — a second [enqueue] for the same key
/// overwrites the first (per-key dedup; UPDATE→DELETE collapses to
/// DELETE).
///
/// **In-memory**: a [LinkedHashSet] of atKey strings, giving FIFO
/// iteration order with O(1) dedup. On [open] the in-memory queue is
/// populated by reading every persisted entry, sorting by `ts`, and
/// inserting in ascending order — preserving the original write
/// order across restarts.
///
/// Lifecycle: construct → [open] → use → [close]. [open] is idempotent.
/// The box is opened on the Hive instance owning the storage path this queue
/// is constructed with, so two clients of one atSign in one process keep
/// separate queues when they are given separate paths.
class AtSyncQueue {
  static const String _boxNamePrefix = 'syncqueue_';

  final String _atSign;
  final AtSignLogger _logger;

  /// Test seam. Production callers should use the default constructor —
  /// the box is opened against the global Hive instance via [open].
  /// Tests can pass an already-opened `Box<String>` to bypass the
  /// production `Hive.openBox` call (useful for in-memory test boxes
  /// or to share a box across test fixtures).
  SyncQueueStore? _store;

  final LinkedHashSet<String> _inMemoryQueue = LinkedHashSet<String>();

  bool _opened = false;

  /// The directory this queue's box lives in, or null for the package-global
  /// Hive instance.
  ///
  /// **Required but nullable**, and both halves are deliberate. Required so
  /// the compiler names every call site: a default would be silently wrong for
  /// the caller that most needs it — a second client of one atSign — and
  /// nothing would go red, because a box resolved from the wrong place still
  /// opens and still works.
  ///
  /// Nullable because a caller may legitimately have no directory to name. A
  /// `LocalSecondary` built around an injected keystore has no
  /// `hiveStoragePath` and never needed one; refusing it would withdraw a
  /// capability those callers already have. Null keeps exactly the behaviour
  /// they have today — the global instance — and with it the collision:
  /// a caller that names no directory cannot be separated from another that
  /// names none either.
  final String? _storagePath;

  bool get isOpen => _opened;

  AtSyncQueue({required String atSign, String? storagePath})
      : _atSign = atSign,
        _storagePath = storagePath,
        _logger = AtSignLogger('AtSyncQueue ($atSign)');

  /// Returns the Hive box name this queue uses, derived
  /// deterministically from the atSign. Exposed as a static so callers
  /// (e.g. `StorageManager` cleanup paths, or tests that want to wipe
  /// state without a live `AtSyncQueue` instance) can compute it
  /// without constructing the class.
  static String boxNameForAtSign(String atSign) =>
      '$_boxNamePrefix${AtUtils.getShaForAtSign(atSign)}';

  /// Opens the persisted box and replays it into the in-memory queue
  /// in `ts`-ascending order. Idempotent — calling [open] twice is a
  /// no-op after the first.
  ///
  /// The box is opened on the instance owning this queue's storage path, not
  /// on the package-global `Hive`. The box name derives from the atSign alone,
  /// and Hive resolves open boxes by name within an instance — so opening on
  /// the global meant two clients of one atSign in one process shared one sync
  /// queue however different the paths they were given. A [store] supplied by
  /// a storage bundle is used as is; an [injectedBox] (test seam) is wrapped.
  Future<void> open({Box<String>? injectedBox, SyncQueueStore? store}) async {
    if (_opened) return;
    if (store != null) {
      _store = store;
    } else if (injectedBox != null) {
      _store = HiveBoxSyncQueueStore(injectedBox);
    } else {
      final path = _storagePath;
      final hive = path == null ? Hive : HiveInstances.forPath(path);
      _store = HiveBoxSyncQueueStore(
          await hive.openBox<String>(boxNameForAtSign(_atSign)));
    }
    _replayIntoMemory();
    _opened = true;
    _logger
        .info('opened: ${_inMemoryQueue.length} entry(ies) replayed in order');
  }

  /// Reads every persisted entry, sorts by `ts` ascending, and inserts
  /// into [_inMemoryQueue] in that order. The LinkedHashSet preserves
  /// insertion order, so subsequent FIFO iteration yields entries in
  /// `ts`-ascending order — the order they were originally written.
  void _replayIntoMemory() {
    final entries = <SyncQueueEntry>[];
    final store = _store!;
    for (final atKey in store.keys.toList()) {
      final raw = store.get(atKey);
      if (raw == null) continue;
      try {
        entries.add(SyncQueueEntry._deserialise(atKey, raw));
      } on FormatException catch (e) {
        _logger.warning('skipping malformed sync queue entry $atKey: $e');
      }
    }
    entries.sort((a, b) => a.ts.compareTo(b.ts));
    for (final e in entries) {
      // Seed the enqueue counter past everything persisted, so a restart
      // cannot stamp a seq an in-flight drain from the previous process
      // already read — removeIfUnchanged's comparison depends on seqs never
      // being reissued.
      if (e.seq >= _nextSeq) _nextSeq = e.seq + 1;
      _inMemoryQueue.add(e.atKey);
    }
  }

  /// Closes the persisted box. After [close], further calls throw
  /// [StateError]. Mainly used in tests; production callers can leave
  /// the box open for the AtClient's lifetime.
  Future<void> close() async {
    if (!_opened) return;
    await _store?.close();
    _store = null;
    _inMemoryQueue.clear();
    _opened = false;
  }

  /// Persists `{op, ts: now}` for [atKey] (overwriting any prior
  /// record) and adds [atKey] to the in-memory FIFO queue. If [atKey]
  /// is already present in the in-memory queue its existing position
  /// is preserved (LinkedHashSet semantics) — the persisted record's
  /// `ts` reflects the latest write, but FIFO drain order tracks
  /// first-insertion-time. On startup [open] resorts in-memory by
  /// `ts`, so post-restart order matches the latest enqueue.
  ///
  /// Use [DateTime.now().millisecondsSinceEpoch] as the timestamp
  /// unless [ts] is supplied (for tests).
  /// Monotonic enqueue counter for this queue instance, seeded past the
  /// highest persisted `seq` by [open] so a restart cannot reissue one.
  int _nextSeq = 1;

  Future<void> enqueue(
    String atKey,
    SyncQueueOp op, {
    int? ts,
  }) async {
    _ensureOpen();
    final entry = SyncQueueEntry(
      atKey: atKey,
      op: op,
      ts: ts ?? DateTime.now().millisecondsSinceEpoch,
      seq: _nextSeq++,
    );
    await _store!.put(atKey, entry._serialise());
    _inMemoryQueue.add(atKey);
  }

  /// Reads the persisted record for [atKey], or `null` if no record
  /// exists. Callers draining the queue use this to retrieve the
  /// (op, ts) before building the wire command.
  SyncQueueEntry? readEntry(String atKey) {
    _ensureOpen();
    final raw = _store!.get(atKey);
    if (raw == null) return null;
    return SyncQueueEntry._deserialise(atKey, raw);
  }

  /// Removes [atKey] from both the in-memory queue and the persisted
  /// box. Called after a successful push to the server, or when a
  /// drain attempt finds the underlying keystore value missing
  /// (race-tolerated removal: a queue write may have committed
  /// without the keystore write landing, e.g. across a crash).
  Future<void> remove(String atKey) async {
    _ensureOpen();
    _inMemoryQueue.remove(atKey);
    await _store!.delete(atKey);
  }

  /// Removes [atKey] only while its entry is still the one stamped [seq];
  /// returns whether it removed.
  ///
  /// This is the drain's success-path removal. Between a drain reading an
  /// entry and the server accepting the push, a new local write to the same
  /// atKey replaces the entry — an update superseded by a delete, or by a
  /// newer value. An unconditional remove at that point discards the newer
  /// op with nothing left to retry it: the server keeps what was pushed, the
  /// queue reads empty, and the client reports itself in sync. Removing only
  /// the pushed version leaves a superseded entry queued for the next round.
  Future<bool> removeIfUnchanged(String atKey, int seq) async {
    _ensureOpen();
    final raw = _store!.get(atKey);
    if (raw == null) return false;
    if (SyncQueueEntry._deserialise(atKey, raw).seq != seq) return false;
    _inMemoryQueue.remove(atKey);
    await _store!.delete(atKey);
    return true;
  }

  /// Drops every entry, keeping the box open.
  Future<void> clear() async {
    _ensureOpen();
    _inMemoryQueue.clear();
    await _store!.clear();
  }

  /// Returns up to [limit] atKey strings from the front of the
  /// in-memory queue, in FIFO order. Does NOT remove them — the
  /// caller is expected to call [remove] per atKey after a successful
  /// push. If [limit] is null returns the entire queue snapshot.
  List<String> peek({int? limit}) {
    _ensureOpen();
    if (limit == null || limit >= _inMemoryQueue.length) {
      return _inMemoryQueue.toList(growable: false);
    }
    return _inMemoryQueue.take(limit).toList(growable: false);
  }

  /// Number of pending entries in the in-memory queue. Cheap; reads
  /// from the LinkedHashSet length, no Hive I/O.
  int get size {
    _ensureOpen();
    return _inMemoryQueue.length;
  }

  /// True if the queue is empty.
  bool get isEmpty => size == 0;

  /// True if the queue has any pending entries.
  bool get isNotEmpty => size > 0;

  /// Test-only iterator over the persisted box keys. Production sync
  /// reads via [peek] (in-memory FIFO).
  @visibleForTesting
  Iterable<String> get persistedKeys {
    _ensureOpen();
    return _store!.keys;
  }

  void _ensureOpen() {
    if (!_opened) {
      throw StateError(
        'AtSyncQueue ($_atSign) used before open() — call open() first',
      );
    }
  }
}
