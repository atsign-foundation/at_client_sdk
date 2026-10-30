import 'dart:async';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'at_lookup_test_utils.dart';
import 'fake_at_server_transport.dart';

/// Catalogue: features/at_lookup/authenticator_swap.feature
void main() {
  const host = '127.0.0.1';
  const port = 12345;

  late _AnsweringServer server;
  late MockSecondaryAddressFinder addressFinder;

  /// The enrollment each authenticator run logged in as, in order.
  late List<String> runs;

  setUp(() {
    server = _AnsweringServer();
    runs = [];
    addressFinder = MockSecondaryAddressFinder();
    when(() => addressFinder.findSecondary('@alice'))
        .thenAnswer((_) async => SecondaryAddress(host, port));
  });

  /// Logs in as [enrollmentId] with `from:` and `pkam:`, as at_auth's does.
  AtAuthenticator loggingInAs(String enrollmentId) => (executor) async {
        runs.add(enrollmentId);
        await executor.sendSync('from:@alice\n');
        final answer =
            await executor.sendSync('pkam:enrollmentId:$enrollmentId:c2ln\n');
        return answer == 'data:success';
      };

  Future<AtLookupMuxable> loggedInAs(String enrollmentId) async {
    final atLookup = AtLookUp.withSecureSocket(
      atSign: '@alice',
      rootDomain: const AtRootDomain(host, 64),
      authenticator: loggingInAs(enrollmentId),
      secondaryAddressFinder: addressFinder,
      transport: AtLookupTransport(transportFactory: server),
    );
    expect(await atLookup.pkamAuthenticate(), isTrue);
    expect(atLookup.connection!.getMetaData()!.authenticatedAsEnrollmentId,
        enrollmentId,
        reason: 'the premise: the connection is logged in as $enrollmentId');
    return atLookup;
  }

  test('An authenticator installed over a login logs in for itself', () async {
    final atLookup = await loggedInAs('E1');

    atLookup.authenticator = loggingInAs('E2');
    expect(await atLookup.pkamAuthenticate(), isTrue);

    expect(runs, ['E1', 'E2'], reason: 'the installed authenticator runs');
    expect(
        atLookup.connection!.getMetaData()!.authenticatedAsEnrollmentId, 'E2');
    expect(server.connections, hasLength(2));
    expect(server.connections.first.destroyed, isTrue,
        reason: 'the connection logged in as E1 is closed');
    await atLookup.stop();
  });

  test('A command after a change of authenticator runs on the new login',
      () async {
    final atLookup = await loggedInAs('E1');

    atLookup.authenticator = loggingInAs('E2');
    expect(await atLookup.executeCommand('scan\n', auth: true), 'data:ok');

    expect(runs, ['E1', 'E2']);
    expect(server.connections, hasLength(2));
    expect(server.connections.first.written, isNot(contains('scan\n')),
        reason: 'nothing runs on the login E1 made once E2 is installed');
    expect(server.connections.last.written,
        ['from:@alice\n', 'pkam:enrollmentId:E2:c2ln\n', 'scan\n']);
    expect(
        atLookup.connection!.getMetaData()!.authenticatedAsEnrollmentId, 'E2');
    await atLookup.stop();
  });

  test('The authenticator that made a login keeps using it', () async {
    final atLookup = await loggedInAs('E1');
    final installed = atLookup.authenticator;

    atLookup.authenticator = installed;
    expect(await atLookup.pkamAuthenticate(), isTrue);
    expect(await atLookup.executeCommand('scan\n', auth: true), 'data:ok');

    expect(runs, ['E1'], reason: 'its own login is reused, never repeated');
    expect(server.connections, hasLength(1));
    expect(server.connections.single.written.last, 'scan\n');
    await atLookup.stop();
  });

  test('A command with no authenticator does not use the old login', () async {
    final atLookup = await loggedInAs('E1');
    final written = server.connections.single.written.length;

    atLookup.authenticator = null;
    await expectLater(atLookup.executeCommand('scan\n', auth: true),
        throwsA(isA<UnAuthenticatedException>()));

    expect(server.connections, hasLength(1));
    expect(server.connections.single.written, hasLength(written),
        reason: 'nothing is sent on the login the removed authenticator made');
    await atLookup.stop();
  });
}

/// An atServer that answers `from:` with a challenge, `pkam:` with success,
/// and anything else with `data:ok`.
class _AnsweringServer implements AtTransportFactory {
  /// Every connection made to this server, oldest first.
  final List<FakeAtServerTransport> connections = [];

  @override
  Future<AtTransport> connect(String host, String port,
      {Duration? timeout}) async {
    final transport = _AnsweringTransport(description: '$host:$port');
    connections.add(transport);
    return transport;
  }
}

class _AnsweringTransport extends FakeAtServerTransport {
  _AnsweringTransport({required super.description});

  @override
  void add(List<int> bytes) {
    super.add(bytes);
    final command = written.last;
    final reply = command.startsWith('from:')
        ? 'data:challenge\n@'
        : command.startsWith('pkam:')
            ? 'data:success\n@alice@'
            : 'data:ok\n@alice@';
    unawaited(serverSends(reply));
  }
}
