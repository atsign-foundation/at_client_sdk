import 'package:at_client/at_client.dart';
import 'package:at_client/memory.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/fake_at_server.dart';
import 'test_utils/no_keys.dart';
import 'test_utils/transport.dart';

/// An [AtLookUp] that is not an [AtLookupMuxable]: it carries no
/// notifications, and stops like any other.
class _PlainLookUp extends Mock implements AtLookUp {}

/// Catalogue: features/at_lookup/close_and_stop.feature
void main() {
  test('A stopped client opens no connection', () async {
    final server = FakeAtServer(atSign: '@stopped');
    final client = await AtClientImpl.create(
        '@stopped', 'wavi', AtClientPreference()..monitorAutoStart = false,
        secondaryAddressFinder: defaultAtDirectory,
        atKeysIo: noKeysFor('@stopped'),
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

  test(
      'A stopped client opens no connection, through an AtLookUp that is '
      'not an AtLookupMuxable', () async {
    final server = FakeAtServer(atSign: '@plain');
    final plain = _PlainLookUp();
    when(() => plain.executeCommand(any(), auth: any(named: 'auth')))
        .thenAnswer((_) async => 'data:ok');
    when(plain.stop).thenAnswer((_) async {});
    when(plain.close).thenAnswer((_) async {});
    final client = await AtClientImpl.create(
            '@plain', 'wavi', AtClientPreference()..monitorAutoStart = false,
            secondaryAddressFinder: defaultAtDirectory,
            atKeysIo: noKeysFor('@plain'),
            atLookUp: plain,
            lookUps: server.lookUps,
            storage:
                InMemoryAtClientStorage(atSign: '@plain', closedByClient: true))
        as AtClientImpl;
    final remote = client.getRemoteSecondary()!;
    expect(await remote.executeCommand('scan\n'), 'data:ok',
        reason: 'the premise: the client reached its atServer');

    await client.stop();

    await expectLater(
        remote.executeCommand('scan\n'), throwsA(isA<StoppedException>()));
    await expectLater(remote.sync(0), throwsA(isA<StoppedException>()));
    verify(() => plain.executeCommand(any(), auth: any(named: 'auth')))
        .called(1);
    verify(plain.stop).called(1);
  });
}
