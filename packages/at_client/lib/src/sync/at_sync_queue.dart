import 'dart:collection';
import 'dart:convert';

import 'package:at_utils/at_utils.dart';
import 'package:hive/hive.dart';
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
/// Hive must already have been initialised (via the keystore's
/// `HiveAtPersistenceFactory.initialize(...)`); this class never calls
/// `Hive.init` itself.
class AtSyncQueue {
  static const String _boxNamePrefix = 'syncqueue_';

  final String _atSign;
  final AtSignLogger _logger;

  /// Test seam. Production callers should use the default constructor —
  /// the box is opened against the global Hive instance via [open].
  /// Tests can pass an already-opened `Box<String>` to bypass the
  /// production `Hive.openBox` call (useful for in-memory test boxes
  /// or to share a box across test fixtures).
  Box<String>? _box;

  final LinkedHashSet<String> _inMemoryQueue = LinkedHashSet<String>();

  bool _opened = false;

  AtSyncQueue({required String atSign})
      : _atSign = atSign,
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
  /// Hive.init must already have been called by the surrounding
  /// keystore initialisation. If [injectedBox] is supplied (test
  /// seam), it is used instead of opening one via Hive — letting
  /// tests provide an in-memory box without calling Hive.init at all.
  Future<void> open({Box<String>? injectedBox}) async {
    if (_opened) return;
    if (injectedBox != null) {
      _box = injectedBox;
    } else {
      _box = await Hive.openBox<String>(boxNameForAtSign(_atSign));
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
    final box = _box!;
    for (final atKey in box.keys.cast<String>()) {
      final raw = box.get(atKey);
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
    await _box?.close();
    _box = null;
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
    await _box!.put(atKey, entry._serialise());
    _inMemoryQueue.add(atKey);
  }

  /// Reads the persisted record for [atKey], or `null` if no record
  /// exists. Callers draining the queue use this to retrieve the
  /// (op, ts) before building the wire command.
  SyncQueueEntry? readEntry(String atKey) {
    _ensureOpen();
    final raw = _box!.get(atKey);
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
    await _box!.delete(atKey);
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
    final raw = _box!.get(atKey);
    if (raw == null) return false;
    if (SyncQueueEntry._deserialise(atKey, raw).seq != seq) return false;
    _inMemoryQueue.remove(atKey);
    await _box!.delete(atKey);
    return true;
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
    return _box!.keys.cast<String>();
  }

  void _ensureOpen() {
    if (!_opened) {
      throw StateError(
        'AtSyncQueue ($_atSign) used before open() — call open() first',
      );
    }
  }
}
