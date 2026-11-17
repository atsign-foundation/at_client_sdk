import 'package:at_client/at_client.dart';
import 'package:at_client/memory.dart';
import 'package:at_lookup/at_lookup.dart' show AtLookupMuxable;

import 'portal_session.dart';
import 'session_queue.dart';

/// Opens the client for [atSign] as [enrollmentId], on [lookUp]: the
/// connection that already authenticated as it. The client takes over
/// [lookUp], reads its @keys from [keysIo] and persists every change through
/// it.
///
/// Stopping the client stops [lookUp] and closes [keysIo] when it is flagged
/// `closedByClient`, which releases what the session holds for the client.
///
/// The client has in-memory storage, reads and writes go to the atServer
/// ([RemoteLocalPref.remoteOnly]), the monitor is off, and every other
/// connection runs over [transport]. It throws as `Atsign.open` does, and
/// throws a [PortalSessionOfflineException], after stopping the client, when
/// it did not come online. Opens for one atSign as one enrollment run one at
/// a time, with those of `portalSession`.
Future<AtClient> openSession({
  required AtLookupMuxable lookUp,
  required String atSign,
  required String enrollmentId,
  required WrittenAtKeysIo keysIo,
  required String app,
  required SessionTransport transport,
}) {
  final normalized = atSign.toAtsign();
  return queuedOpen(
      openLock(normalized, enrollmentId),
      () => openOnline(
          atSign: normalized,
          app: app,
          keys: keysIo,
          transport: transport,
          atLookUp: lookUp,
          logger: 'openSession'));
}

/// Builds the client for [atSign] on [keys] and [transport], with in-memory
/// storage, and returns it once online; shared by [openSession] and
/// `portalSession`. [prefs] defaults to a remote-only, monitor-off
/// preference for [app] and [transport]'s root; [atLookUp], when given, is
/// the connection the client takes over. [logger] names the caller in the
/// teardown warning.
Future<AtClient> openOnline({
  required String atSign,
  required String app,
  required WrittenAtKeysIo keys,
  required SessionTransport transport,
  AtClientPreference? prefs,
  AtLookupMuxable? atLookUp,
  required String logger,
}) async {
  final preference = prefs ??
      (AtClientPreference()
        ..namespace = app
        ..rootDomain = transport.root.rootDomain
        ..rootPort = transport.root.rootPort
        ..remoteLocalPref = RemoteLocalPref.remoteOnly
        ..monitorAutoStart = false);
  final client = await Atsign(atSign).open(
    keys: keys,
    preference: preference,
    namespace: app,
    storage: InMemoryAtClientStorage(atSign: atSign, closedByClient: true),
    atLookUp: atLookUp,
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
      AtSignLogger(logger)
          .warning('stopping the client of $atSign failed', e, st);
    }
    rethrow;
  }
}
