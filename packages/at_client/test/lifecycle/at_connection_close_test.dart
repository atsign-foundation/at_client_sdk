import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../test_utils/mocks.dart';
import '../test_utils/no_op_services.dart';

/// A stopping client fails its own in-flight requests by closing their
/// connections, and what those requests fail with says nothing about the
/// atServer: the connection state stops recording before the stop begins.
void main() {
  AtConnectionState offline() =>
      AtConnectionState.offline(AtConnectionCause.unreachable,
          error: 'The connection was closed by this client before a response '
              'arrived');

  group('AtConnection', () {
    test('a report after close is not recorded and not emitted', () async {
      final connection = AtConnection(
          atSign: '@closed', attempt: (_) async => AtConnectionState.online());
      final emitted = <AtConnectionState>[];
      connection.changes.listen(emitted.add);
      await connection.report(AtConnectionState.online());
      final before = connection.current;

      await connection.close();
      await connection.report(offline());

      expect(before.isOnline, isTrue);
      expect(connection.current.cause, AtConnectionCause.stopped,
          reason: 'a reader still holding the client finds why nothing is '
              'connected; a stop-induced failure is not a transition');
      expect(emitted.map((s) => s.cause), [null, AtConnectionCause.stopped],
          reason: 'the stop is the last change emitted');
    });

    test('the same report before close is recorded (control)', () async {
      final connection = AtConnection(
          atSign: '@open', attempt: (_) async => AtConnectionState.online());
      await connection.report(AtConnectionState.online());

      await connection.report(offline());

      expect(connection.current.isOffline, isTrue);
      expect(connection.current.cause, AtConnectionCause.unreachable);
    });
  });

  group('AtClientImpl.stop', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('connection_close_');
      AtClientManager.getInstance().reset();
    });

    tearDown(() async {
      for (final c
          in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
        await c.stop();
      }
      AtClientManager.getInstance().reset();
      dir.deleteSync(recursive: true);
    });

    test('a request the stop itself fails is not recorded as unreachable',
        () async {
      final lookUp = MockAtLookupImpl();
      when(() => lookUp.isConnectionAvailable()).thenReturn(false);
      late AtClient client;
      // What the remote does when the stop closes its lookup underneath a
      // request in flight: classifies the failure and reports it.
      when(() => lookUp.close()).thenAnswer((_) async {
        await client.connection.report(offline());
      });
      client = await buildAtClient(
          atSign: '@stopquiet',
          namespace: 'wavi',
          preference: AtClientPreference()
            ..hiveStoragePath = dir.path
            ..monitorAutoStart = false,
          atLookUp: lookUp,
          syncServiceBuilder: (_) => NoOpSyncService());
      final before = client.connection.current;

      await client.stop();

      verify(() => lookUp.close()).called(greaterThan(0));
      expect(before.cause, isNot(AtConnectionCause.stopped));
      expect(client.connection.current.cause, AtConnectionCause.stopped,
          reason: 'the connection state is closed before the services and '
              'the remote are, so a failure the stop caused is not filed '
              'as the atServer being unreachable');
    });
  });
}
