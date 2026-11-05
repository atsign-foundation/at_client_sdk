import 'dart:async';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'at_lookup_test_utils.dart';
import 'fake_at_server_transport.dart';

/// Catalogue: features/at_lookup/close_and_stop.feature
void main() {
  const host = '127.0.0.1';
  const port = 12345;

  late List<FakeAtServerTransport> sockets;
  late MockSecondaryAddressFinder addressFinder;
  late _TransportFactory transportFactory;
  late List<AtCommandExecutor> authentications;

  /// While set, the atServer's address is not answered until it completes.
  Completer<void>? findGate;

  /// While set, a transport is not handed out until it completes.
  Completer<void>? connectGate;

  /// While set, every new transport's flushes wait for it.
  Completer<void>? flushGate;

  /// Past the first notification reconnect delay of one second.
  const pastFirstReconnect = Duration(milliseconds: 1400);

  setUp(() {
    sockets = [];
    authentications = [];
    findGate = null;
    connectGate = null;
    flushGate = null;
    addressFinder = MockSecondaryAddressFinder();
    transportFactory = _TransportFactory((h, p) async {
      expect('$h:$p', '$host:$port');
      final s = FakeAtServerTransport()..flushGate = flushGate;
      sockets.add(s);
      await connectGate?.future;
      return s;
    });
    when(() => addressFinder.findSecondary('@alice')).thenAnswer((_) async {
      await findGate?.future;
      return SecondaryAddress(host, port);
    });
  });

  AtLookupMuxable build({AtAuthenticator? authenticator}) =>
      AtLookUp.withSecureSocket(
        atSign: '@alice',
        rootDomain: const AtRootDomain(host, 64),
        authenticator: authenticator ??
            (executor) async {
              authentications.add(executor);
              return true;
            },
        secondaryAddressFinder: addressFinder,
        transport: AtLookupTransport(transportFactory: transportFactory),
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
    await Future.delayed(pastFirstReconnect);

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
    await Future.delayed(pastFirstReconnect);

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
  test('close() fails a connect in flight at once, and its late socket closes',
      () async {
    final atLookup = build();
    connectGate = Completer<void>();
    final request = inFlight(atLookup, 'noop:0\n');
    await Future.delayed(const Duration(milliseconds: 50));
    expect(sockets, hasLength(1), reason: 'the connect must be in flight');

    await atLookup.close();
    await request.settled.timeout(const Duration(seconds: 2),
        onTimeout: () => fail('the request waited for its connect'));
    expect(request.thrown(), isA<ConnectionInvalidException>());

    connectGate!.complete();
    await eventually(() => sockets.first.destroyed,
        'the socket the abandoned connect opened is closed');
    expect(sockets.first.written, isEmpty);
    connectGate = null;
    expect(await answered(atLookup, 'noop:0\n'), 'data:ok',
        reason: 'the lookup stays usable after close()');
    await atLookup.stop();
  });

  test('close() while the atServer is being looked up opens no connection',
      () async {
    final atLookup = build();
    findGate = Completer<void>();
    final request = inFlight(atLookup, 'noop:0\n');
    await Future.delayed(const Duration(milliseconds: 50));
    verify(() => addressFinder.findSecondary('@alice')).called(1);

    await atLookup.close();
    await request.settled.timeout(const Duration(seconds: 2),
        onTimeout: () => fail('the request waited for its lookup'));
    expect(request.thrown(), isA<ConnectionInvalidException>());

    findGate!.complete();
    await Future.delayed(const Duration(milliseconds: 50));
    expect(sockets, isEmpty,
        reason: 'a connect close() abandoned opens no socket once the '
            "atServer's address comes back");
    findGate = null;
    expect(await answered(atLookup, 'noop:0\n'), 'data:ok',
        reason: 'the lookup stays usable after close()');
    await atLookup.stop();
  });

  test('stop() while the atServer is being looked up opens no connection',
      () async {
    final atLookup = build();
    findGate = Completer<void>();
    final request = inFlight(atLookup, 'noop:0\n');
    await Future.delayed(const Duration(milliseconds: 50));
    verify(() => addressFinder.findSecondary('@alice')).called(1);

    await atLookup.stop();
    findGate!.complete();
    await request.settled.timeout(const Duration(seconds: 2),
        onTimeout: () => fail('the request on the lookup was never failed'));
    expect(request.thrown(), isA<StoppedException>());

    await Future.delayed(const Duration(milliseconds: 50));
    expect(sockets, isEmpty,
        reason: "a stopped lookup opens no socket once the atServer's address "
            'comes back');
  });

  test('close() during a notification start authenticates nothing', () async {
    final atLookup = build()..heartbeatInterval = const Duration(hours: 1);
    connectGate = Completer<void>();
    Object? thrown;
    final starting = atLookup
        .startNotifications()
        .then<void>((_) {}, onError: (Object e) => thrown = e);
    await Future.delayed(const Duration(milliseconds: 50));
    expect(sockets, hasLength(1), reason: 'the start must be connecting');

    await atLookup.close();
    connectGate!.complete();
    await starting.timeout(const Duration(seconds: 2),
        onTimeout: () => fail('the start waited for its connect'));
    await Future.delayed(const Duration(milliseconds: 100));

    expect(thrown, isA<ConnectionInvalidException>());
    expect(authentications, isEmpty,
        reason: 'a start the owner closed under must not authenticate');
    expect(atLookup.isNotifying, isFalse);
    expect(sockets.single.destroyed, isTrue);
    expect(sockets.single.written, isEmpty);
    await atLookup.stop();
  });

  test(
      'close() while a notification reconnect is connecting authenticates '
      'nothing', () async {
    final atLookup = build()..heartbeatInterval = const Duration(hours: 1);
    await atLookup.startNotifications();
    expect(authentications, hasLength(1));
    connectGate = Completer<void>();
    await sockets.single.serverCloses();
    await Future.delayed(pastFirstReconnect);
    expect(sockets, hasLength(2), reason: 'the reconnect must be connecting');

    await atLookup.close();
    connectGate!.complete();
    await Future.delayed(const Duration(milliseconds: 200));

    expect(authentications, hasLength(1),
        reason: 'a reconnect the owner closed under must not authenticate');
    expect(atLookup.isNotifying, isFalse);
    expect(sockets.last.destroyed, isTrue);
    expect(sockets.last.written, isEmpty);
    await atLookup.stop();
  });

  test('close() while monitor: is being written leaves notifications off',
      () async {
    final atLookup = build()
      ..heartbeatInterval = const Duration(milliseconds: 40);
    flushGate = Completer<void>();
    final starting = atLookup
        .startNotifications()
        .then<void>((_) {}, onError: (Object _) {});
    await eventually(
        () =>
            sockets.isNotEmpty &&
            sockets.single.written.any((w) => w.startsWith('monitor:')),
        'monitor: must be on its way out');

    await atLookup.close();
    flushGate!.complete();
    await starting;
    await Future.delayed(const Duration(milliseconds: 200));

    expect(atLookup.isNotifying, isFalse,
        reason: 'the close came after the start, so it wins');
    expect(sockets, hasLength(1),
        reason: 'nothing reconnects by itself after close()');
    expect(sockets.single.written.where((w) => w == 'noop:0\n'), isEmpty,
        reason: 'no heartbeat runs for notifications the owner closed');
    await atLookup.stop();
  });
  test(
      'stopNotifications() while a notification reconnect is connecting '
      'authenticates nothing', () async {
    final atLookup = build()..heartbeatInterval = const Duration(hours: 1);
    await atLookup.startNotifications();
    expect(authentications, hasLength(1));
    connectGate = Completer<void>();
    await sockets.single.serverCloses();
    await Future.delayed(pastFirstReconnect);
    expect(sockets, hasLength(2), reason: 'the reconnect must be connecting');

    await atLookup.stopNotifications();
    connectGate!.complete();
    await Future.delayed(const Duration(milliseconds: 200));

    expect(authentications, hasLength(1),
        reason: 'a reconnect retired before it authenticated must not');
    expect(atLookup.isNotifying, isFalse);
    expect(sockets.last.destroyed, isTrue);
    await atLookup.stop();
  });

  test('close() between a challenge and its answer sends the answer nowhere',
      () async {
    final challenged = Completer<void>();
    final answering = Completer<void>();
    Object? answerFailed;
    final atLookup = build(authenticator: (executor) async {
      await executor.sendSync('from:@alice\n');
      challenged.complete();
      await answering.future;
      try {
        await executor.sendSync('pkam:answer\n');
      } on Exception catch (e) {
        answerFailed = e;
        rethrow;
      }
      return true;
    });
    Object? thrown;
    final request = atLookup
        .executeCommand('scan\n', auth: true)
        .then<void>((_) {}, onError: (Object e) => thrown = e);
    await Future.delayed(const Duration(milliseconds: 50));
    await sockets.single.serverSends('data:challenge\n@');
    await challenged.future.timeout(const Duration(seconds: 2));

    await atLookup.close();
    await request.timeout(const Duration(seconds: 2),
        onTimeout: () => fail('the request waited for its answer'));
    answering.complete();
    await Future.delayed(const Duration(milliseconds: 100));

    expect(thrown, isA<ConnectionInvalidException>());
    expect(answerFailed, isA<ConnectionInvalidException>());
    expect(sockets, hasLength(1),
        reason: 'the answer must not open a connection of its own');
    expect(sockets.single.written, ['from:@alice\n']);
    await atLookup.stop();
  });

  test('close() during authentication sends the command nowhere', () async {
    final authenticating = Completer<void>();
    final authenticated = Completer<void>();
    final atLookup = build(authenticator: (executor) async {
      authenticating.complete();
      await authenticated.future;
      return true;
    });
    Object? thrown;
    final request = atLookup
        .executeCommand('scan\n', auth: true)
        .then<void>((_) {}, onError: (Object e) => thrown = e);
    await authenticating.future.timeout(const Duration(seconds: 2));

    await atLookup.close();
    await request.timeout(const Duration(seconds: 2),
        onTimeout: () => fail('the request waited for its authentication'));
    authenticated.complete();
    await Future.delayed(const Duration(milliseconds: 100));

    expect(thrown, isA<ConnectionInvalidException>());
    expect(sockets, hasLength(1),
        reason: 'the command must not open a connection of its own');
    expect(sockets.single.written, isEmpty);
    await atLookup.stop();
  });

  test('A late authentication marks only its own connection', () async {
    final authenticating = Completer<void>();
    final authenticated = Completer<void>();
    final atLookup = build(authenticator: (executor) async {
      authentications.add(executor);
      if (authentications.length == 1) {
        authenticating.complete();
        await authenticated.future;
      }
      return true;
    });
    Object? thrown;
    final late = atLookup
        .pkamAuthenticate()
        .then<void>((_) {}, onError: (Object e) => thrown = e);
    await authenticating.future.timeout(const Duration(seconds: 2));
    await atLookup.close();
    await late.timeout(const Duration(seconds: 2),
        onTimeout: () => fail('the authentication outlived the close'));
    final response = atLookup.executeCommand('scan\n', auth: true);
    await eventually(() => sockets.length == 2, 'the command reconnected');
    await Future.delayed(const Duration(milliseconds: 50));

    authenticated.complete();
    await Future.delayed(const Duration(milliseconds: 50));
    await sockets.last.serverSends('data:ok\n@alice@');

    expect(thrown, isA<ConnectionInvalidException>());
    expect(await response, 'data:ok');
    expect(authentications, hasLength(2),
        reason: 'the new connection authenticates itself, whatever an '
            'authentication on the old one reports');
    await atLookup.stop();
  });
}

/// Connects through [onConnect], so each test decides what a new connection
/// is.
class _TransportFactory implements AtTransportFactory {
  final Future<AtTransport> Function(String host, String port) onConnect;

  _TransportFactory(this.onConnect);

  @override
  Future<AtTransport> connect(String host, String port, {Duration? timeout}) =>
      onConnect(host, port);
}
