import 'dart:async';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/memory.dart';
// ignore: implementation_imports
import 'package:at_client/src/preference/posture_floor.dart';
import 'package:at_utils/at_utils.dart';

/// How a session's connections reach atServers: [lookUps] builds each
/// connection, [finder] resolves an atSign to its atServer.
typedef SessionTransport = ({
  AtLookUpFactory lookUps,
  SecondaryAddressFinder finder,
});

/// [atSign] trimmed and in `@name` form.
String normalizeAtSign(String atSign) => AtUtils.fixAtSign(atSign.trim());

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

  SessionKeysIo(String atSign, this._keys) : _atSign = normalizeAtSign(atSign);

  @override
  FutureOr<AtKeys> read(String atsign) => normalizeAtSign(atsign) == _atSign
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
/// [app] is the client's namespace. [prefs], when given, is used as it is;
/// otherwise the preference names [app] and [root] and leaves the monitor
/// off. Keys that carry ML-DSA-65 signing or namespace key material throw
/// [UnsupportedKeyMaterialException] before any connection is made. An open
/// that does not come online, a PKAM the atServer refuses included, stops the
/// client and throws [PortalSessionOfflineException]: `Atsign.open` returns an
/// offline client rather than throwing. Anything else that throws once the
/// client is built stops it and is rethrown, so a retry for the same atSign
/// builds afresh.
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
  final normalized = normalizeAtSign(atSign);
  if (floorOfKeyMaterial(keys, keys.enrollmentToAuthenticateAs()) != null) {
    throw UnsupportedKeyMaterialException(normalized);
  }
  final preference = prefs ??
      (AtClientPreference()
        ..namespace = app
        ..rootDomain = root.rootDomain
        ..rootPort = root.rootPort
        ..monitorAutoStart = false);
  final client = await Atsign(normalized).open(
    keys: keysIo ?? SessionKeysIo(normalized, keys),
    preference: preference,
    namespace: app,
    storage: InMemoryAtClientStorage(atSign: normalized, closedByClient: true),
    lookUps: transport.lookUps,
    secondaryAddressFinder: transport.finder,
  );
  try {
    final state = client.connection.current;
    if (!state.isOnline) {
      throw PortalSessionOfflineException(normalized, state);
    }
    return client;
  } catch (_) {
    await client.stop();
    rethrow;
  }
}
