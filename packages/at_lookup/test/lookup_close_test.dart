import 'dart:async';

import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_utils.dart' show AtSignLogger, LoggingHandler;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'at_lookup_test_utils.dart';
import 'fake_at_server_socket.dart';

class _RecordedLogs implements LoggingHandler {
  final List<({String level, String message})> records = [];

  @override
  void call(dynamic record) => records
      .add((level: '${record.level.name}', message: '${record.message}'));

  Iterable<String> at(String level) =>
      records.where((r) => r.level == level).map((r) => r.message);
}

/// `close()` ends a lookup and `dropConnection()` does not, over a real
/// connection and listener on a [FakeAtServerSocket].
void main() {
  const host = '127.0.0.1';
  const port = 12345;
  final recorded = _RecordedLogs();

  setUpAll(() {
    AtSignLogger.defaultLoggingHandler = recorded;
  });

  late List<FakeAtServerSocket> sockets;
  late MockSecondaryAddressFinder addressFinder;
  late MockSecureSocketFactory socketFactory;

  /// While set, a socket is not handed out until it completes.
  Completer<void>? connectGate;

  setUp(() {
    recorded.records.clear();
    sockets = [];
    connectGate = null;
    addressFinder = MockSecondaryAddressFinder();
    socketFactory = MockSecureSocketFactory();
    registerFallbackValue(SecureSocketConfig());
    when(() => addressFinder.findSecondary('@alice'))
        .thenAnswer((_) async => SecondaryAddress(host, port));
    when(() => socketFactory.createSocket(host, '$port', any()))
        .thenAnswer((_) async {
      final s = FakeAtServerSocket();
      sockets.add(s);
      await connectGate?.future;
      return s;
    });
  });

  AtLookupMuxable build() => AtLookUp.withSecureSocket(
        atSign: '@alice',
        rootDomain: const AtRootDomain(host, 64),
        authenticator: (_) async => true,
        secondaryAddressFinder: addressFinder,
        transport: AtLookupTransport(
          secureSocketConfig: SecureSocketConfig(),
          socketFactory: socketFactory,
        ),
      );

  /// Sends [command] and answers it the way the atServer would.
  Future<String?> answered(AtLookupMuxable atLookup, String command) async {
    final response = atLookup.executeCommand(command);
    await Future.delayed(const Duration(milliseconds: 50));
    await sockets.last.serverSends('data:ok\n@alice@');
    return response;
  }

  group('close()', () {
    test('fails a request in flight as stopped, and logs nothing at severe',
        () async {
      final atLookup = build();
      Object? thrown;
      final pending = atLookup
          .executeCommand('noop:0\n')
          .then<void>((_) {}, onError: (Object e) => thrown = e);
      await Future.delayed(const Duration(milliseconds: 50));

      await atLookup.close();
      await pending.timeout(const Duration(seconds: 5),
          onTimeout: () => fail('the request in flight was never failed'));

      expect(thrown, isA<StoppedException>(),
          reason: 'the request failed because its owner closed the lookup, '
              'and a caller has to be able to tell that from a network fault');
      expect(recorded.at('SEVERE'), isEmpty,
          reason: 'a close the owner asked for is not an error');
    });

    test('refuses every later call, and opens no connection', () async {
      final atLookup = build();
      await answered(atLookup, 'noop:0\n');
      expect(sockets, hasLength(1));
      await atLookup.close();

      final calls = <String, Future<Object?> Function()>{
        'executeCommand': () => atLookup.executeCommand('noop:0\n'),
        'executeVerb': () => atLookup.executeVerb(StatsVerbBuilder()),
        'llookup': () => atLookup.llookup('phone'),
        'lookup(verifyData)': () =>
            atLookup.lookup('phone', '@bob', verifyData: true),
        'pkamAuthenticate': () => atLookup.pkamAuthenticate(),
        'cramAuthenticate': () => atLookup.cramAuthenticate('secret'),
        'sendSync': () => (atLookup as AtCommandExecutor).sendSync('noop:0\n'),
        'readResponse': () => atLookup.readResponse(),
        'startNotifications': () => atLookup.startNotifications(),
      };
      for (final call in calls.entries) {
        await expectLater(call.value(), throwsA(isA<StoppedException>()),
            reason: '${call.key} after close()');
      }
      expect(sockets, hasLength(1),
          reason: 'a closed lookup must not reconnect to report its refusal');
    });

    test('destroys a socket that arrives after it', () async {
      final atLookup = build();
      connectGate = Completer<void>();
      Object? thrown;
      final pending = atLookup
          .executeCommand('noop:0\n')
          .then<void>((_) {}, onError: (Object e) => thrown = e);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(sockets, hasLength(1), reason: 'the connect must be in flight');

      await atLookup.close();
      connectGate!.complete();
      await pending.timeout(const Duration(seconds: 5),
          onTimeout: () => fail('the request on the late socket was never '
              'failed'));

      expect(thrown, isA<StoppedException>());
      expect(sockets.single.destroyed, isTrue,
          reason: 'nothing else holds this socket, so a late one left open '
              'keeps the process alive');
      expect(sockets.single.written, isEmpty);
    });

    test('fails a connect in flight at once, without waiting for it', () async {
      final atLookup = build();
      connectGate = Completer<void>();
      final pending = atLookup.executeCommand('noop:0\n');
      await Future.delayed(const Duration(milliseconds: 50));
      expect(sockets, hasLength(1), reason: 'the connect must be in flight');

      final closing = atLookup.close();

      await expectLater(
          pending.timeout(const Duration(seconds: 2),
              onTimeout: () => fail('the request waited for its connect, '
                  'which a silent peer never completes')),
          throwsA(isA<StoppedException>()));
      await closing;
      connectGate!.complete();
    });

    test('ends a reconnect loop sleeping on its backoff', () async {
      final atLookup = build()..heartbeatInterval = const Duration(hours: 1);
      await atLookup.startNotifications();
      await sockets.single.serverCloses();
      await Future.delayed(const Duration(milliseconds: 50));
      expect(atLookup.isReconnectingNotifications, isTrue);

      await atLookup.close();
      await Future.delayed(const Duration(milliseconds: 1400));

      expect(sockets, hasLength(1),
          reason: 'a reconnect after close() reopens what its owner closed');
      expect(atLookup.isNotifying, isFalse);
    });

    test('ends notifications and their streams', () async {
      final atLookup = build()
        ..heartbeatInterval = const Duration(milliseconds: 40);
      await atLookup.startNotifications();
      final notificationsDone = Completer<void>();
      atLookup.notifications.listen(null, onDone: notificationsDone.complete);

      await atLookup.close();
      await Future.delayed(const Duration(milliseconds: 150));

      expect(atLookup.isNotifying, isFalse);
      expect(notificationsDone.isCompleted, isTrue);
      expect(sockets.single.written, isNot(contains('noop:0\n')),
          reason: 'the heartbeat must not outlive the close');
      await expectLater(atLookup.notifications, emitsDone,
          reason: 'a stream read after close() can never produce anything');
      await expectLater(atLookup.notificationConnectionUp, emitsDone);
    });
  });

  group('stopNotifications()', () {
    test('landing while notifications start, leaves them stopped', () async {
      final atLookup = build()
        ..heartbeatInterval = const Duration(milliseconds: 40);
      connectGate = Completer<void>();
      final starting = atLookup.startNotifications();
      await Future.delayed(const Duration(milliseconds: 50));

      await atLookup.stopNotifications();
      connectGate!.complete();
      await starting;
      await Future.delayed(const Duration(milliseconds: 150));

      expect(atLookup.isNotifying, isFalse,
          reason: 'the stop came after the start, so it wins');
      expect(sockets.single.written, isEmpty,
          reason: 'no monitor: on a connection nobody is listening to');
      expect(sockets.single.destroyed, isTrue,
          reason: 'the connection the start opened is closed, not left open');
      await atLookup.close();
    });

    test('with a heartbeat in flight, the heartbeat ends quietly', () async {
      final atLookup = build()
        ..heartbeatInterval = const Duration(milliseconds: 40)
        ..heartbeatResponseTimeout = const Duration(seconds: 5);
      await atLookup.startNotifications();
      for (var i = 0;
          i < 50 && !sockets.single.written.contains('noop:0\n');
          i++) {
        await Future.delayed(const Duration(milliseconds: 10));
      }
      expect(sockets.single.written, contains('noop:0\n'),
          reason: 'the probe must be out before the stop');

      await atLookup.stopNotifications();
      await Future.delayed(const Duration(milliseconds: 150));

      expect(recorded.records.map((r) => r.message),
          isNot(contains(contains('heartbeat failed'))),
          reason: 'a probe the stop cut short is not a failed connection');
      expect(sockets, hasLength(1));
      await atLookup.close();
    });
  });

  group('dropConnection()', () {
    test('leaves the lookup usable', () async {
      final atLookup = build();
      await answered(atLookup, 'noop:0\n');

      await atLookup.dropConnection();

      expect(sockets.single.destroyed, isTrue);
      expect(await answered(atLookup, 'noop:0\n'), 'data:ok',
          reason: 'the next call opens a new connection');
      expect(sockets, hasLength(2));
      await atLookup.close();
    });

    test('while notifying, reconnects', () async {
      final atLookup = build()..heartbeatInterval = const Duration(hours: 1);
      await atLookup.startNotifications();

      await atLookup.dropConnection();
      await Future.delayed(const Duration(milliseconds: 1400));

      expect(sockets, hasLength(2));
      expect(sockets.last.written.single, startsWith('monitor:'));
      expect(atLookup.isNotifying, isTrue);
      await atLookup.close();
    });
  });
}
