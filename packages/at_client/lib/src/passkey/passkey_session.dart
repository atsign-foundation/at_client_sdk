import 'dart:async';

import 'package:at_auth/passkey.dart' show PasskeyVault;
import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_client/src/lifecycle/at_connection.dart';
import 'package:at_utils/at_logger.dart' show AtSignLogger;

import 'at_server_at_keys_io.dart';

/// A client opened with a passkey, with the key store it runs on and the
/// passkey vault that store seals with.
///
/// The session closes the store and then the vault once the client has
/// stopped, whether through [stop] or by the client's own `stop()`. It learns
/// of a stop from the client's connection changes ending, which they do as
/// the stop begins, and then waits for that stop to finish and, up to its
/// bound, for a @keys write already queued on the store to end.
class PasskeySession {
  /// The session of [client], running on [store], which seals with [vault].
  ///
  /// [settleWithin] bounds the wait for a queued @keys write once the client
  /// has stopped; the vault then closes under a write still running.
  PasskeySession(this.client, AtServerAtKeysIo store, PasskeyVault vault,
      {Duration settleWithin = defaultSettleWithin})
      : _store = store,
        _vault = vault,
        _settleWithin = settleWithin {
    _changes = client.connection.changes.listen(null, onDone: _releaseQuietly);
  }

  /// How long a session waits by default for a queued @keys write once its
  /// client has stopped.
  static const defaultSettleWithin = Duration(seconds: 10);

  static final _logger = AtSignLogger('PasskeySession');

  /// The client running as the passkey's enrollment.
  final AtClient client;

  final AtServerAtKeysIo _store;
  final PasskeyVault _vault;
  final Duration _settleWithin;
  late final StreamSubscription<AtConnectionState> _changes;
  Future<void>? _stopping;
  Future<void>? _releasing;

  /// Stops the client, then closes the key store and the vault, even when the
  /// client's stop throws; that error then propagates.
  ///
  /// A second call waits for the first and does nothing else, throwing
  /// nothing.
  Future<void> stop() {
    final running = _stopping;
    if (running != null) return running.then((_) {}, onError: (Object _) {});
    return _stopping = _stop();
  }

  Future<void> _stop() async {
    try {
      await client.stop();
    } finally {
      await _release();
    }
  }

  void _releaseQuietly() {
    unawaited(_release().catchError((Object e, StackTrace st) {
      _logger.warning('closing the passkey vault failed', e, st);
    }));
  }

  Future<void> _release() => _releasing ??= _releaseOnce();

  Future<void> _releaseOnce() async {
    unawaited(_changes.cancel());
    // NOTE: a client's stop is shared, so this waits for the stop in flight.
    await client.stop().then((_) {}, onError: (Object _) {});
    try {
      await _store.settled.timeout(_settleWithin);
    } on TimeoutException {
      _logger.warning('a @keys write was still running '
          '${_settleWithin.inMilliseconds} ms after the client stopped; the '
          'passkey vault closes under it');
    }
    try {
      _store.close();
    } finally {
      _vault.close();
    }
  }
}
