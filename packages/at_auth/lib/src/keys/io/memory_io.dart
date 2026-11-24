import 'dart:async';

import 'package:at_auth/at_auth.dart';
import 'package:at_commons/atsign.dart';
import 'package:meta/meta.dart';

/// Stores [AtKeys] in process memory, for tests.
///
/// ⚠️ **Nothing it holds survives the process, so an application never runs a
/// client on it.** A client files key material into its keyfile that exists
/// nowhere else: a fully privileged client at a post-quantum posture mints the
/// atSign's signing root there, and a root whose private key is lost can never
/// be replaced. Keep an application's keys in a durable [WrittenAtKeysIo], such
/// as [FileAtKeysIo]. A subclass escapes the analyzer's warning, not this.
class InMemoryAtKeysIo extends WrittenAtKeysIo {
  /// Keys are indexed by normalized [Atsign] (via `toAtsign()`), so the
  /// `String`-typed [read]/[write] and the [Atsign]-typed [flush] all resolve
  /// to the same entry.
  final Map<Atsign, AtKeys> _internal = {};

  /// Completes when the last update queued for each Atsign ends; removed
  /// once it has.
  final Map<Atsign, Completer<void>> _updates = {};

  /// The zone key under which an update records the Atsigns it is changing
  /// on this store.
  final Object _updating = Object();

  @visibleForTesting
  InMemoryAtKeysIo();

  /// An in-memory store already holding [atKeys] for [atsign].
  ///
  /// For a caller that has a key set in hand and needs a *source* to
  /// authenticate from, which is what [AtAuthRequest] takes. at_auth and
  /// at_client wrap a fixed key set this way internally for one handshake or
  /// authentication; it is never the store a client runs on.
  @visibleForTesting
  factory InMemoryAtKeysIo.holding(String atsign, AtKeys atKeys) {
    final io = InMemoryAtKeysIo();
    io._internal[atsign.toAtsign()] = atKeys;
    return io;
  }

  /// Returns the keys for [atsign], or throws if nothing has been loaded into
  /// memory for that atsign.
  @override
  FutureOr<AtKeys> read(String atsign) {
    return _internal[atsign.toAtsign()] ??
        (throw AtKeysNotInMemoryException('$atsign not found in memory'));
  }

  /// Create-only, like every [WrittenAtKeysIo.write]: throws
  /// [AtKeysFileOverwriteException] when keys for [atsign] are already
  /// loaded. Use [update] to change keys already stored.
  ///
  /// Throwing as the file store does keeps this an honest stand-in: code that
  /// writes twice fails here as it would against the file.
  @override
  Future<void> write(String atsign, AtKeys atKeys) async {
    final key = atsign.toAtsign();
    if (_internal.containsKey(key)) {
      throw AtKeysFileOverwriteException(
          'Keys for $atsign are already loaded; write is create-only — '
          'use update to change them');
    }
    _internal[key] = atKeys;
  }

  /// Literal mirror to write as there is no need to flush to memory.
  @override
  FutureOr<void> flush(Atsign atsign, AtKeys atKeys) {
    _internal[atsign.toAtsign()] = atKeys;
  }

  /// Runs [mutate] on a copy of the stored keys, and stores the copy through
  /// [flush] only when [mutate] returns true, so a false return or a throw
  /// leaves the stored keys as they were.
  ///
  /// Updates of one Atsign run one at a time, and an update started from
  /// inside a change on the same Atsign throws [StateError].
  ///
  /// Stored keys that record no Atsign are given [atsign] before the copy is
  /// made; keys that record one keep it.
  @override
  Future<void> update(
      Atsign atsign, FutureOr<bool> Function(AtKeys keys) mutate) async {
    final key = atsign.toAtsign();
    final changing = Zone.current[_updating] as Set<Atsign>? ?? const {};
    if (changing.contains(key)) {
      throw StateError('an update for $key was started from inside a change '
          'to $key on the same store');
    }
    final before = _updates[key]?.future;
    final ended = _updates[key] = Completer<void>();
    try {
      await before;
      final stored = await read(atsign.toString());
      stored.atsign ??= key;
      final copy = AtKeys.fromJson(stored.toJson())..atsign = stored.atsign;
      final changed = await runZoned(() => mutate(copy), zoneValues: {
        _updating: {...changing, key}
      });
      if (changed == false) return;
      await flush(atsign, copy);
    } finally {
      ended.complete();
      if (identical(_updates[key], ended)) _updates.remove(key);
    }
  }
}
