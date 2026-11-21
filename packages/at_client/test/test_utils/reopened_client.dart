import 'package:at_client/at_client.dart';
import 'package:at_client/memory.dart';
import 'package:at_client/src/client/remote_secondary.dart';
import 'package:at_commons/at_builders.dart';

import 'fake_at_server.dart';

/// Opens [atSign] on [keys] against [server], over [storage], giving its
/// first attempt [connectBudget].
Future<AtClient> openOn(FakeAtServer server, String atSign, AtKeysIo keys,
        AtClientStorage storage,
        {Duration connectBudget = AtConnection.defaultBudget}) =>
    Atsign(atSign).open(
        keys: keys,
        preference: AtClientPreference()
          ..namespace = 'wavi'
          ..rootDomain = '127.0.0.1',
        storage: storage,
        lookUps: server.lookUps,
        secondaryAddressFinder: server.addressFinder,
        connectBudget: connectBudget);

/// A store in which [atSign] has been online on this device: one open of it
/// against [server], which the atServer accepted, then stopped.
Future<AtClientStorage> storeOnceOnline(
    FakeAtServer server, String atSign, AtKeysIo keys) async {
  final storage = InMemoryAtClientStorage(atSign: atSign);
  final client = await openOn(server, atSign, keys, storage);
  if (!client.connection.current.isOnline) {
    throw StateError('the first open of $atSign is not online: '
        '${client.connection.current}');
  }
  await client.stop();
  return storage;
}

/// A [RemoteSecondary] of [atSign] on [keys] against [server], as
/// [enrollmentId], reporting into a connection whose state a verb that is
/// answered makes online.
({RemoteSecondary remote, AtConnection connection}) remoteReportingOn(
    FakeAtServer server, String atSign, AtKeysIo keys,
    {String? enrollmentId}) {
  final connection = AtConnection(
      atSign: atSign,
      attempt: (_) async =>
          AtConnectionState.offline(AtConnectionCause.unattempted));
  final remote = RemoteSecondary(
      atSign,
      AtClientPreference()
        ..namespace = 'wavi'
        ..rootDomain = '127.0.0.1',
      atKeysIo: keys,
      enrollmentId: enrollmentId,
      connection: connection,
      lookUps: server.lookUps,
      secondaryAddressFinder: server.addressFinder);
  return (remote: remote, connection: connection);
}

/// An `llookup:` of [atSign]'s own `phone`.
LLookupVerbBuilder llookupOf(String atSign) => LLookupVerbBuilder()
  ..atKey = (AtKey()
    ..key = 'phone'
    ..sharedBy = atSign);
