import 'dart:async';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'at_lookup_test_utils.dart';
import 'fake_at_server_transport.dart';

/// Authentications that overlap on one lookup.
void main() {
  const host = '127.0.0.1';
  const port = 12345;

  late _AnsweringServer server;
  late MockSecondaryAddressFinder addressFinder;

  /// Released by the test once both authentications are in flight.
  late Completer<void> gate;

  /// The enrollment each authenticator run logged in as, in order.
  late List<String> runs;

  setUp(() {
    server = _AnsweringServer();
    gate = Completer<void>();
    runs = [];
    addressFinder = MockSecondaryAddressFinder();
    when(() => addressFinder.findSecondary('@alice'))
        .thenAnswer((_) async => SecondaryAddress(host, port));
  });

  /// Logs in as [enrollmentId] with `from:` and `pkam:`, once [gate] opens.
  AtAuthenticator loggingInAs(String enrollmentId) => (executor) async {
        runs.add(enrollmentId);
        await gate.future;
        await executor.sendSync('from:@alice\n');
        final answer =
            await executor.sendSync('pkam:enrollmentId:$enrollmentId:c2ln\n');
        return answer == 'data:success';
      };

  AtLookupMuxable build(AtAuthenticator authenticator) =>
      AtLookUp.withSecureSocket(
        atSign: '@alice',
        rootDomain: const AtRootDomain(host, 64),
        authenticator: authenticator,
        secondaryAddressFinder: addressFinder,
        transport: AtLookupTransport(transportFactory: server),
      );

  /// Every `from:` the server received, on any connection.
  List<String> handshakes() => [
        for (final connection in server.connections)
          ...connection.written.where((c) => c.startsWith('from:'))
      ];

  /// Lets the event loop run until [condition] holds, or fails naming [what].
  Future<void> until(bool Function() condition, String what) async {
    for (var i = 0; i < 100 && !condition(); i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(condition(), isTrue, reason: what);
  }

  group('Given a lookup that has not logged in', () {
    test(
        'when two callers authenticate it at once, then one from: handshake '
        'logs in for both', () async {
      final atLookup = build(loggingInAs('E1'));
      addTearDown(atLookup.stop);

      final first = atLookup.pkamAuthenticate();
      final second = atLookup.pkamAuthenticate();
      var secondSettled = false;
      unawaited(second.whenComplete(() => secondSettled = true));
      await until(() => runs.isNotEmpty, 'the first authentication starts');
      await Future<void>.delayed(Duration.zero);
      expect(secondSettled, isFalse,
          reason: 'the premise: the second authentication is still in flight '
              'while the first is inside its authenticator');
      gate.complete();

      expect(await Future.wait([first, second]), [true, true]);
      expect(handshakes(), hasLength(1),
          reason: 'the second authentication waits for the first and uses the '
              'login it made, so one from: handshake is sent');
      expect(runs, ['E1']);
      expect(server.connections, hasLength(1));
      expect(atLookup.connection!.getMetaData()!.authenticatedAsEnrollmentId,
          'E1');
    });

    test(
        'when two callers authenticate it at once with different '
        'authenticators, then each logs in on its own connection', () async {
      final atLookup = build(loggingInAs('E1'));
      addTearDown(atLookup.stop);

      final first = atLookup.pkamAuthenticate();
      await until(() => runs.isNotEmpty, 'the first authentication starts');
      atLookup.authenticator = loggingInAs('E2');
      final second = atLookup.pkamAuthenticate();
      gate.complete();

      expect(await Future.wait([first, second]), [true, true]);
      expect(handshakes(), hasLength(2),
          reason: 'the control: two logins under two authenticators are two '
              'handshakes, so the count above can read more than one');
      expect(runs, ['E1', 'E2']);
      expect(atLookup.connection!.getMetaData()!.authenticatedAsEnrollmentId,
          'E2');
    });
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
