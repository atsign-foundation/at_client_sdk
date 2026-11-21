import 'dart:isolate';

import 'package:at_client/at_client.dart';
import 'package:at_client/memory.dart';

import '../test_utils/fake_at_server.dart';
import '../test_utils/ml_dsa_keyfile.dart';
import '../test_utils/recorded_logs.dart';
import '../test_utils/test_keypairs.dart';

/// Opens a client for `@alice`, as an app that sets no appName or appVersion,
/// over a [FakeAtServer] that runs its authenticator; then sends [results] the
/// `from:` commands the client's own connection sent and every warning it
/// logged, or what went wrong.
Future<void> openUnnamedClientAndReport(SendPort results) async {
  final logs = RecordedLogs()..installOn(level: 'warning');
  const atSign = '@alice';
  final server = FakeAtServer(atSign: atSign, runsClientAuthenticator: true);
  AtClient? client;
  try {
    client = await Atsign(atSign).open(
        keys: keysHoldingApkam(atSign, null, pkamKeyPairFor(atSign, null)),
        preference: AtClientPreference()..namespace = 'wavi',
        storage: InMemoryAtClientStorage(atSign: atSign, closedByClient: true),
        lookUps: server.lookUps,
        secondaryAddressFinder: server.addressFinder);
    results.send({
      'froms': server.fromsOn(client.getRemoteSecondary()!.atLookUp),
      'warnings': logs.at('WARNING').toList(),
    });
  } catch (e, stackTrace) {
    results.send({'error': '$e\n$stackTrace'});
  } finally {
    await client?.stop();
  }
}
