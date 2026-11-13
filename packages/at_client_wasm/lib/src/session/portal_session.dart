import 'dart:async';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/memory.dart';
// ignore: implementation_imports
import 'package:at_client/src/preference/posture_floor.dart';

/// How a session's connections reach atServers: [lookUps] builds each
/// connection, [finder] resolves an atSign to its atServer.
typedef SessionTransport = ({
  AtLookUpFactory lookUps,
  SecondaryAddressFinder finder,
});

/// Thrown by [portalSession] when the client did not come online.
class PortalSessionOfflineException implements Exception {
  final String atSign;

  /// The connection state the open ended in.
  final AtConnectionState state;

  PortalSessionOfflineException(this.atSign, this.state);

  @override
  String toString() => 'PortalSessionOfflineException: $atSign did not come '
      'online (${state.cause?.name})'
      '${state.error == null ? '' : ': ${state.error}'}';
}

/// Thrown by [portalSession], before any connection is made, for keys that
/// carry ML-DSA-65 signing or namespace key material.
///
/// This is a stopgap: a session's key store is in memory, so a client that
/// raised its posture on such keys would file new material nowhere that
/// survives. The passkey-onboarding gate replaces this check.
class UnsupportedKeyMaterialException implements Exception {
  final String atSign;

  UnsupportedKeyMaterialException(this.atSign);

  @override
  String toString() => 'UnsupportedKeyMaterialException: the keys for $atSign '
      'carry ML-DSA-65 signing or namespace key material, which a session '
      'with an in-memory key store cannot hold';
}

/// The key store of a [portalSession]: [keys] for [atSign], in memory, and
/// nothing else.
///
/// [write] and [flush] throw a [StateError] and count the attempt, as a
/// backstop behind [portalSession]'s refusal of keys that would make a client
/// file new material: anything written here would be lost with the page. The
/// passkey-onboarding gate, which persists keys elsewhere, replaces this
/// stopgap.
class SessionKeysIo extends WrittenAtKeysIo {
  final String _atSign;
  final AtKeys _keys;

  /// How many times [write] and [flush] were called.
  var refusedWrites = 0;
  var refusedFlushes = 0;

  SessionKeysIo(String atSign, this._keys) : _atSign = atSign.toAtsign();

  @override
  FutureOr<AtKeys> read(String atsign) => atsign.toAtsign() == _atSign
      ? _keys
      : throw AtKeysNotInMemoryException('$atsign not found in memory');

  @override
  Future<void> write(String atsign, AtKeys atKeys) async {
    refusedWrites++;
    throw StateError('a session key store takes no writes ($atsign)');
  }

  @override
  FutureOr<void> flush(Atsign atsign, AtKeys atKeys) {
    refusedFlushes++;
    throw StateError('a session key store takes no flushes ($atsign)');
  }
}

/// Opens an at_client for [atSign] on [keys], with in-memory storage and
/// every connection over [transport], and returns it once it has
/// authenticated to the atServer.
///
/// [atSign] is put in `@name` form by `toAtsign()`, which throws an
/// [InvalidAtSignException] for one it cannot take, whitespace included.
/// [app] is the client's namespace. [prefs], when given, is used as it is;
/// otherwise the preference names [app] and [root], routes reads and writes
/// to the atServer ([RemoteLocalPref.remoteOnly]) and leaves the monitor off.
/// Sync runs under every preference: a put or delete that passes request
/// options leaves `useRemoteAtServer` false, which routes it to local storage
/// even under [RemoteLocalPref.remoteOnly], and only sync carries it to the
/// atServer.
/// Keys that carry ML-DSA-65 signing or namespace key material throw
/// [UnsupportedKeyMaterialException] before any connection is made. The
/// storage is always fresh, so every open is a first open on the device, and
/// `Atsign.open` throws:
///
/// - [AtOpenRefusedException] when the atServer refuses the open (a revoked
///   or unauthenticated credential, an unapproved or expired enrollment) or
///   there is no atServer for the atSign;
/// - [AtEnrollmentPendingException] for keys that hold only a pending
///   enrollment, with no credential to authenticate with.
///
/// Any other open that does not come online, such as a PKAM that fails
/// without being classed as a refusal, stops the client and throws
/// [PortalSessionOfflineException]. Anything else that throws once the
/// client is built stops it and is rethrown, so a retry for the same atSign
/// builds afresh.
///
/// Opens for one atSign run one at a time: an open started while another
/// for the same atSign is running waits for it to end, then fails as it
/// would after it (a [StateError] while that client is live) or builds
/// afresh.
///
/// [keysIo] is the key store the client runs on, by default a [SessionKeysIo]
/// over [keys].
Future<AtClient> portalSession({
  required String atSign,
  required String app,
  required AtKeys keys,
  required SessionTransport transport,
  AtRootDomain root = AtRootDomain.atsignDomain,
  AtClientPreference? prefs,
  SessionKeysIo? keysIo,
}) async {
  final normalized = atSign.toAtsign();
  if (floorOfKeyMaterial(keys, keys.enrollmentToAuthenticateAs()) != null) {
    throw UnsupportedKeyMaterialException(normalized);
  }
  // `buildAtClient` checks for a live client and registers its own across
  // awaits, so two opens running together would both pass the check.
  final previous = _opening[normalized];
  final done = Completer<void>();
  _opening[normalized] = done;
  try {
    if (previous != null) await previous.future;
    return await _open(normalized, app, keys, transport, root, prefs, keysIo);
  } finally {
    done.complete();
    if (identical(_opening[normalized], done)) {
      _opening.remove(normalized);
    }
  }
}

/// Completed when the newest open running for each atSign ends, however it
/// ends; it never completes with an error.
final _opening = <String, Completer<void>>{};

Future<AtClient> _open(
  String atSign,
  String app,
  AtKeys keys,
  SessionTransport transport,
  AtRootDomain root,
  AtClientPreference? prefs,
  SessionKeysIo? keysIo,
) async {
  final preference = prefs ??
      (AtClientPreference()
        ..namespace = app
        ..rootDomain = root.rootDomain
        ..rootPort = root.rootPort
        ..remoteLocalPref = RemoteLocalPref.remoteOnly
        ..monitorAutoStart = false);
  final client = await Atsign(atSign).open(
    keys: keysIo ?? SessionKeysIo(atSign, keys),
    preference: preference,
    namespace: app,
    storage: InMemoryAtClientStorage(atSign: atSign, closedByClient: true),
    lookUps: transport.lookUps,
    secondaryAddressFinder: transport.finder,
  );
  try {
    final state = client.connection.current;
    if (!state.isOnline) {
      throw PortalSessionOfflineException(atSign, state);
    }
    return client;
  } catch (_) {
    // The open's own error is the one the caller needs, not a teardown's.
    try {
      await client.stop();
    } catch (e, st) {
      AtSignLogger('portalSession')
          .warning('stopping the client of $atSign failed', e, st);
    }
    rethrow;
  }
}
