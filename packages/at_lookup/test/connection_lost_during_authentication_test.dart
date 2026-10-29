import 'dart:async';

import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_lookup/src/connection/at_connection.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'at_lookup_test_utils.dart';
import 'fake_at_server_transport.dart';

/// Catalogue: features/at_lookup/connection_lost_during_authentication.feature
void main() {
  const host = '127.0.0.1';
  const port = 12345;

  late _AnsweringServer server;
  late MockSecondaryAddressFinder addressFinder;
  late int runs;

  setUp(() {
    server = _AnsweringServer();
    runs = 0;
    addressFinder = MockSecondaryAddressFinder();
    when(() => addressFinder.findSecondary('@alice'))
        .thenAnswer((_) async => SecondaryAddress(host, port));
  });

  /// A lookup whose authenticator sends `from:` and then `pkam:`, as at_auth's
  /// does, running [beforeFrom] and [beforeAnswer] first.
  AtLookupMuxable build(
          {Future<void> Function()? beforeFrom,
          Future<void> Function()? beforeAnswer}) =>
      AtLookUp.withSecureSocket(
        atSign: '@alice',
        rootDomain: const AtRootDomain(host, 64),
        authenticator: (executor) async {
          runs++;
          await beforeFrom?.call();
          await executor.sendSync('from:@alice\n');
          await beforeAnswer?.call();
          final answer = await executor.sendSync('pkam:answer\n');
          if (answer != 'data:success') {
            throw UnAuthenticatedException('Failed connecting to @alice. '
                '$answer');
          }
          return true;
        },
        secondaryAddressFinder: addressFinder,
        transport: AtLookupTransport(transportFactory: server),
      );

  test("A connection lost before the authenticator's first command is replaced",
      () async {
    var closes = 1;
    final atLookup = build(beforeFrom: () async {
      if (closes-- > 0) await server.connections.last.serverCloses();
    });

    expect(await atLookup.pkamAuthenticate(), isTrue);

    expect(server.connections, hasLength(2));
    expect(server.connections.first.written, isEmpty,
        reason: 'nothing is written to a connection that has closed');
    expect(server.connections.last.written, ['from:@alice\n', 'pkam:answer\n']);
    expect(runs, 2);
    expect(atLookup.connection!.getMetaData()!.isAuthenticated, isTrue);
    await atLookup.stop();
  });

  test('A connection lost between the challenge and its answer is replaced',
      () async {
    late final AtLookupMuxable atLookup;
    AtConnection? lost;
    var closes = 1;
    atLookup = build(beforeAnswer: () async {
      if (closes-- > 0) {
        lost = atLookup.connection;
        await server.connections.last.serverCloses();
      }
    });

    expect(await atLookup.pkamAuthenticate(), isTrue);

    expect(server.connections, hasLength(2));
    expect(server.connections.first.written, ['from:@alice\n'],
        reason: 'the answer to the first challenge is sent nowhere');
    expect(server.connections.last.written, ['from:@alice\n', 'pkam:answer\n'],
        reason: 'the fresh connection answers a challenge of its own');
    expect(lost!.getMetaData()!.isAuthenticated, isFalse);
    expect(identical(atLookup.connection, lost), isFalse);
    expect(atLookup.connection!.getMetaData()!.isAuthenticated, isTrue);
    await atLookup.stop();
  });

  test('A second lost connection fails as a lost connection, not a refusal',
      () async {
    final atLookup =
        build(beforeFrom: () async => server.connections.last.serverCloses());

    await expectLater(atLookup.pkamAuthenticate(),
        throwsA(isA<ConnectionInvalidException>()));
    expect(server.connections, hasLength(2),
        reason: 'an authentication opens one fresh connection, and no more');
    expect(runs, 2);

    await expectLater(
        atLookup.executeVerb(ScanVerbBuilder()..auth = true),
        throwsA(isA<AtLookUpException>()
            .having((e) => e.errorCode, 'errorCode', isNot('AT0401'))));
    expect(server.connections, hasLength(4));
    expect(server.connections.every((c) => c.written.isEmpty), isTrue);
    await atLookup.stop();
  });

  test('A refused authentication is not run again', () async {
    final atLookup = build();
    server.refusing = true;

    await expectLater(
        atLookup.pkamAuthenticate(), throwsA(isA<UnAuthenticatedException>()));
    expect(runs, 1);
    expect(server.connections, hasLength(1));
    await atLookup.stop();
  });

  test(
      'A command waiting behind a lost authentication runs on the fresh '
      'connection', () async {
    final waiting = Completer<void>();
    var closes = 1;
    final atLookup = build(beforeFrom: () async {
      if (closes-- > 0) {
        await waiting.future;
        await server.connections.last.serverCloses();
      }
    });
    final authenticated = atLookup.pkamAuthenticate();
    await Future.delayed(const Duration(milliseconds: 50));
    final command = atLookup.executeCommand('scan\n', auth: true);
    await Future.delayed(const Duration(milliseconds: 50));
    waiting.complete();

    expect(await authenticated, isTrue);
    expect(await command, 'data:ok');
    expect(runs, 2,
        reason: 'the first run and its one replacement; the command finds '
            'the fresh connection authenticated');
    expect(server.connections, hasLength(2));
    expect(server.connections.last.written,
        ['from:@alice\n', 'pkam:answer\n', 'scan\n']);
    await atLookup.stop();
  });
}

/// An atServer that answers as one does: `from:` with a challenge, `pkam:`
/// with success or, while [refusing], with a refusal, and anything else with
/// `data:ok`.
class _AnsweringServer implements AtTransportFactory {
  /// Every connection made to this server, oldest first.
  final List<_AnsweringTransport> connections = [];

  bool refusing = false;

  @override
  Future<AtTransport> connect(String host, String port,
      {Duration? timeout}) async {
    final transport = _AnsweringTransport(this, description: '$host:$port');
    connections.add(transport);
    return transport;
  }
}

class _AnsweringTransport extends FakeAtServerTransport {
  final _AnsweringServer _server;

  _AnsweringTransport(this._server, {required super.description});

  @override
  void add(List<int> bytes) {
    super.add(bytes);
    final command = written.last;
    final String reply;
    if (command.startsWith('from:')) {
      reply = 'data:challenge\n@';
    } else if (command.startsWith('pkam:')) {
      reply = _server.refusing
          ? 'error:AT0401-Client authentication failed\n@'
          : 'data:success\n@alice@';
    } else {
      reply = 'data:ok\n@alice@';
    }
    unawaited(serverSends(reply));
  }
}
