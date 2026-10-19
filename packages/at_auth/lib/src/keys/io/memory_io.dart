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
  /// loaded. Use [flush] (or [update]) for later mutations.
  ///
  /// This double used to replace silently, which made it lie as a stand-in:
  /// code that double-wrote passed against memory and threw against the
  /// file store.
  @override
  Future<void> write(String atsign, AtKeys atKeys) async {
    final key = atsign.toAtsign();
    if (_internal.containsKey(key)) {
      throw AtKeysFileOverwriteException(
          'Keys for $atsign are already loaded; write is create-only — '
          'flush persists mutations');
    }
    _internal[key] = atKeys;
  }

  /// Literal mirror to write as there is no need to flush to memory.
  @override
  FutureOr<void> flush(Atsign atsign, AtKeys atKeys) {
    _internal[atsign.toAtsign()] = atKeys;
  }
}
