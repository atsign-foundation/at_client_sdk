import 'dart:async';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'at_lookup_test_utils.dart';
import 'fake_at_server_socket.dart';

/// Catalogue: features/at_lookup/close_and_stop.feature
void main() {
  const host = '127.0.0.1';
  const port = 12345;

  late List<FakeAtServerSocket> sockets;
  late MockSecondaryAddressFinder addressFinder;
  late MockSecureSocketFactory socketFactory;
  late List<AtCommandExecutor> authentications;

  /// While set, a socket is not handed out until it completes.
  Completer<void>? connectGate;

  setUp(() {
    sockets = [];
    authentications = [];
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
        authenticator: (executor) async {
          authentications.add(executor);
          return true;
        },
        secondaryAddressFinder: addressFinder,
        transport: AtLookupTransport(
          secureSocketConfig: SecureSocketConfig(),
          socketFactory: socketFactory,
        ),
      );

  /// Sends [command] and answers it the way the atServer would.
  Future<String?> answered(AtLookupMuxable atLookup, String command,
      {bool auth = false}) async {
    final response = atLookup.executeCommand(command, auth: auth);
    await Future.delayed(const Duration(milliseconds: 50));
    await sockets.last.serverSends('data:ok\n@alice@');
    return response;
  }

  /// Starts [command] on [atLookup] and returns what it throws, once it does.
  ({Future<void> settled, Object? Function() thrown}) inFlight(
      AtLookupMuxable atLookup, String command) {
    Object? thrown;
    final settled = atLookup
        .executeCommand(command)
        .then<void>((_) {}, onError: (Object e) => thrown = e);
    return (settled: settled, thrown: () => thrown);
  }

  Future<void> eventually(bool Function() condition, String what) async {
    for (var i = 0; i < 100 && !condition(); i++) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
    expect(condition(), isTrue, reason: what);
  }

  test('A call after close() reconnects', () async {
    final atLookup = build();
    expect(await answered(atLookup, 'scan\n', auth: true), 'data:ok');
    expect(authentications, hasLength(1));

    await atLookup.close();

    expect(sockets.single.destroyed, isTrue);
    expect(await answered(atLookup, 'scan\n', auth: true), 'data:ok');
    expect(sockets, hasLength(2),
        reason: 'the command after close() opened a new connection');
    expect(authentications, hasLength(2),
        reason: 'the new connection authenticated with the authenticator the '
            'lookup was built with, the only credentials it holds');
    verify(() => addressFinder.findSecondary('@alice')).called(2);
    await atLookup.stop();
  });

  test('close() fails a request in flight at once', () async {
    final atLookup = build();
    final request = inFlight(atLookup, 'noop:0\n');
    await Future.delayed(const Duration(milliseconds: 50));

    await atLookup.close();
    await request.settled.timeout(const Duration(seconds: 2),
        onTimeout: () => fail('the request waited for its timeout'));

    expect(request.thrown(), isA<ConnectionInvalidException>());
    expect(await answered(atLookup, 'noop:0\n'), 'data:ok');
    expect(sockets, hasLength(2),
        reason: 'the next command opened a new connection');
    await atLookup.stop();
  });

  test('Nothing reconnects by itself after close()', () async {
    final atLookup = build()..heartbeatInterval = const Duration(hours: 1);
    await atLookup.startNotifications();
    final notificationsDone = Completer<void>();
    atLookup.notifications.listen(null, onDone: notificationsDone.complete);

    await atLookup.close();
    // Past the first reconnect delay, which is one second.
    await Future.delayed(const Duration(milliseconds: 1400));

    expect(atLookup.isNotifying, isFalse);
    expect(notificationsDone.isCompleted, isTrue,
        reason: 'notifications stopped, and their stream says so');
    expect(sockets, hasLength(1),
        reason: 'no connection opens until the caller runs a command');

    expect(await answered(atLookup, 'noop:0\n'), 'data:ok');
    expect(sockets, hasLength(2));
    await atLookup.stop();
  });

  test('close() ends a reconnect loop sleeping on its backoff', () async {
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
    await atLookup.stop();
  });

  test('stop() ends the lookup', () async {
    final atLookup = build()..heartbeatInterval = const Duration(hours: 1);
    await atLookup.startNotifications();
    final notificationsDone = Completer<void>();
    atLookup.notifications.listen(null, onDone: notificationsDone.complete);
    final request = inFlight(atLookup, 'noop:0\n');
    await Future.delayed(const Duration(milliseconds: 50));

    await atLookup.stop();
    await request.settled.timeout(const Duration(seconds: 2),
        onTimeout: () => fail('the request in flight was never failed'));

    expect(request.thrown(), isA<StoppedException>());
    expect(atLookup.isNotifying, isFalse);
    expect(notificationsDone.isCompleted, isTrue);
    expect(sockets.single.destroyed, isTrue);
    await expectLater(
        atLookup.executeCommand('noop:0\n'),
        throwsA(isA<StoppedException>().having(
            (e) => e.message, 'message', contains('has been stopped'))));
    await expectLater(
        atLookup.startNotifications(), throwsA(isA<StoppedException>()));
    expect(sockets, hasLength(1),
        reason: 'a stopped lookup opens no connection to refuse a call');
  });

  test('stop() wins over a reconnect in flight', () async {
    final atLookup = build();
    await answered(atLookup, 'noop:0\n');
    await atLookup.close();
    connectGate = Completer<void>();
    final request = inFlight(atLookup, 'noop:0\n');
    await Future.delayed(const Duration(milliseconds: 50));
    expect(sockets, hasLength(2), reason: 'the reconnect must be in flight');

    await atLookup.stop();
    connectGate!.complete();
    await request.settled.timeout(const Duration(seconds: 5),
        onTimeout: () => fail('the request on the reconnect was never failed'));

    expect(request.thrown(), isA<StoppedException>());
    await eventually(() => sockets.last.destroyed,
        'the socket the reconnect opened is closed');
    expect(sockets.last.written, isEmpty);
  });

  test('close() after stop() changes nothing', () async {
    final atLookup = build();
    await answered(atLookup, 'noop:0\n');
    await atLookup.stop();

    await atLookup.close();

    await expectLater(
        atLookup.executeCommand('noop:0\n'), throwsA(isA<StoppedException>()));
    expect(sockets, hasLength(1));
  });
}
