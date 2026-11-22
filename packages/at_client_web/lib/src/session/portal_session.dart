import 'dart:async';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
// ignore: implementation_imports
import 'package:at_client/src/preference/posture_floor.dart';

import 'session_open.dart' show openOnline;
import 'session_queue.dart';

/// How a session's connections reach atServers: [lookUps] builds each
/// connection, [finder] resolves an atSign to its atServer, and [root] is the
/// root domain every connection is built for.
///
/// [root] must be the root [lookUps] and [finder] were built for, since
/// at_lookup sends `from:<atSign>` first only for a `proxy:` root; the
/// transport `sessionTransport()` builds is made that way.
typedef SessionTransport = ({
  AtLookUpFactory lookUps,
  SecondaryAddressFinder finder,
  AtRootDomain root,
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
      'with an in-memory AtKeys store cannot hold';
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
/// [app] is the client's namespace. [prefs], when given, is used as it is,
/// so it must not be changed once passed, and one that names a root other
/// than [transport]'s throws an [ArgumentError] before any connection is
/// made. Hosts are compared ignoring case; ports, and whether each is a
/// `proxy:` root, exactly. Otherwise the preference
/// names [app] and [transport]'s root, routes reads and writes to the
/// atServer ([RemoteLocalPref.remoteOnly]) and leaves the monitor off.
/// Sync runs under every preference and starts at every open, pulling the
/// atServer's records into the in-memory store without the caller asking. A
/// put or delete goes to the atServer under [RemoteLocalPref.remoteOnly]
/// unless its request options set `useRemoteAtServer = false` explicitly.
/// Only that keeps a write local, queued for sync; options that leave it
/// unset do not. A `local:` key's write always stays on the device.
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
/// Opens for one atSign as one enrollment run one at a time: an open started
/// while another for the same atSign and enrollment is running waits for it
/// to end, then fails as it would after it (a [StateError] while that client
/// is live) or builds afresh. Opens for different enrollments of an atSign,
/// which at_client allows side by side, do not wait on each other.
///
/// [keysIo] is the key store the client runs on, by default a [SessionKeysIo]
/// over [keys].
Future<AtClient> portalSession({
  required String atSign,
  required String app,
  required AtKeys keys,
  required SessionTransport transport,
  AtClientPreference? prefs,
  SessionKeysIo? keysIo,
}) async {
  final normalized = atSign.toAtsign();
  final enrollmentId = keys.enrollmentToAuthenticateAs();
  if (floorOfKeyMaterial(keys, enrollmentId) != null) {
    throw UnsupportedKeyMaterialException(normalized);
  }
  // `buildAtClient` checks for a live client and registers its own across
  // awaits, so two opens running together would both pass the check. It
  // files clients by (atSign, enrollment), so that is what opens queue on.
  return queuedOpen(openLock(normalized, enrollmentId), () async {
    if (prefs != null) _checkRoot(prefs, transport.root);
    return openOnline(
        atSign: normalized,
        app: app,
        keys: keysIo ?? SessionKeysIo(normalized, keys),
        transport: transport,
        prefs: prefs,
        logger: 'portalSession');
  });
}

/// Throws an [ArgumentError] naming `prefs` when [prefs] names a root other
/// than [root]: a host that differs other than in case, another port, or one
/// that is a `proxy:` root where the other is not.
void _checkRoot(AtClientPreference prefs, AtRootDomain root) {
  final asked = AtRootDomain(prefs.rootDomain, prefs.rootPort);
  if (asked.isProxyAddress != root.isProxyAddress ||
      asked.rootDomain.toLowerCase() != root.rootDomain.toLowerCase() ||
      asked.rootPort != root.rootPort) {
    throw ArgumentError.value(
        '${asked.rootDomain}:${asked.rootPort}',
        'prefs',
        "names a root other than the transport's "
            '(${root.rootDomain}:${root.rootPort})');
  }
}
