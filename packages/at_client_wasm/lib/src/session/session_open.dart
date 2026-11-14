import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/memory.dart';

import 'portal_session.dart';

/// Opens an at_client for [atSign] (already atSign) on [keys] as
/// [portalSession] does, without its refusal of ML-DSA-65 and namespace key
/// material: the caller vouches that [keys] came from its own login path.
///
/// Opens for one (atSign, [enrollmentId]) run one at a time, whichever path
/// they come from: `buildAtClient` checks for a live client and registers its
/// own across awaits, so two opens running together would both pass the check.
/// It files clients by (atSign, enrollment), so that is what opens queue on.
/// An open started while another for the same pair is running waits for it to
/// end, then fails as it would after it or builds afresh; another enrollment
/// of the same atSign is not held up by it.
Future<AtClient> openSession({
  required String atSign,
  required String enrollmentId,
  required String app,
  required AtKeys keys,
  required SessionTransport transport,
  required AtRootDomain root,
  AtClientPreference? prefs,
  SessionKeysIo? keysIo,
}) async {
  final lock = '$atSign $enrollmentId';
  final previous = _opening[lock];
  final done = Completer<void>();
  _opening[lock] = done;
  try {
    if (previous != null) await previous.future;
    return await _open(atSign, app, keys, transport, root, prefs, keysIo);
  } finally {
    done.complete();
    if (identical(_opening[lock], done)) {
      _opening.remove(lock);
    }
  }
}

/// Completed when the newest open running for each (atSign, enrollment) ends,
/// however it ends; it never completes with an error.
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
    await stopQuietly(client, atSign);
    rethrow;
  }
}

/// Stops [client] of [atSign] on a path that already has an error to raise.
/// A failed stop is logged, never thrown: the error in flight is the one the
/// caller needs, not a teardown's.
Future<void> stopQuietly(AtClient client, String atSign) async {
  try {
    await client.stop();
  } catch (e, st) {
    AtSignLogger('portalSession')
        .warning('stopping the client of $atSign failed', e, st);
  }
}
