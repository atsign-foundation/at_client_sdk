import 'package:at_client/at_client.dart';
import 'package:at_client/memory.dart';
import 'package:test/test.dart';

import 'test_utils/fake_at_server.dart';

/// Catalogue: features/at_lookup/close_and_stop.feature
void main() {
  test('A stopped client opens no connection', () async {
    final server = FakeAtServer(atSign: '@stopped');
    final client = await AtClientImpl.create(
        '@stopped', 'wavi', AtClientPreference()..monitorAutoStart = false,
        lookUps: server.lookUps,
        storage: InMemoryAtClientStorage(
            atSign: '@stopped', closedByClient: true)) as AtClientImpl;
    final remote = client.getRemoteSecondary()!;
    expect(await remote.executeCommand('scan\n'), 'data:ok',
        reason: 'the premise: the client reached its atServer');

    await client.stop();
    final connects = server.connectCount;

    await expectLater(
        remote.executeCommand('scan\n'), throwsA(isA<StoppedException>()));
    await expectLater(client.getRemoteSecondary()!.executeCommand('scan\n'),
        throwsA(isA<StoppedException>()));
    expect(server.connectCount, connects,
        reason: 'a stopped client must not open a connection, and so cannot '
            'authenticate for its atSign again');
  });
}
