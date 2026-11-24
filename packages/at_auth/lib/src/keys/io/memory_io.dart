import 'dart:async';
import 'dart:convert';

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

  /// The zone key under which a change carries the updates of this store it
  /// runs inside.
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

  /// Replaces the keys held for [atsign] with [atKeys]; unlike the file,
  /// keychain and server-held stores, it does not first check that nothing
  /// held is lost.
  @override
  FutureOr<void> flush(Atsign atsign, AtKeys atKeys) {
    _internal[atsign.toAtsign()] = atKeys;
  }

  /// Runs [mutate] on a copy of the stored keys, and stores the copy through
  /// [flush] only when [mutate] returns true, so a false return or a throw
  /// leaves the stored keys as they were.
  ///
  /// Updates of one Atsign run one at a time, and an update started from
  /// inside a change on the same Atsign, while that change's update runs,
  /// throws [StateError]. A change must not wait on an update of this store
  /// that waits, in turn, on the change's own Atsign.
  ///
  /// The copy of keys that record no Atsign records [atsign]. Keys that record
  /// another Atsign keep it, where the file, keychain and server-held stores
  /// refuse them.
  @override
  Future<void> update(
      Atsign atsign, FutureOr<bool> Function(AtKeys keys) mutate) async {
    final key = atsign.toAtsign();
    final enclosing = Zone.current[_updating] as List<_Change>? ?? const [];
    if (enclosing.any((change) => change.live && change.atsign == key)) {
      throw StateError('an update for $key was started from inside a change '
          'to $key on the same store');
    }
    final before = _updates[key]?.future;
    final ended = _updates[key] = Completer<void>();
    final change = _Change(key);
    try {
      await before;
      final copy = _copy(await read(atsign.toString()), key);
      final changed = await runZoned(() => mutate(copy), zoneValues: {
        _updating: [...enclosing, change]
      });
      if (changed == false) return;
      await flush(atsign, copy);
    } finally {
      change.live = false;
      ended.complete();
      if (identical(_updates[key], ended)) _updates.remove(key);
    }
  }

  /// A copy of [stored] that shares nothing with it and records [atsign] when
  /// [stored] records no Atsign, leaving [stored] as it was.
  static AtKeys _copy(AtKeys stored, Atsign atsign) {
    final had = stored.atsign;
    final Map<String, dynamic> json;
    try {
      stored.atsign = had ?? atsign;
      json = stored.toJson();
    } finally {
      stored.atsign = had;
    }
    return AtKeys.fromJson(jsonDecode(jsonEncode(json)) as Map<String, dynamic>)
      ..atsign = had ?? atsign;
  }
}

/// One update's change on an [InMemoryAtKeysIo], live until that update ends.
class _Change {
  _Change(this.atsign);

  final Atsign atsign;
  bool live = true;
}
