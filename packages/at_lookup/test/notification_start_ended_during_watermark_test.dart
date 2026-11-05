import 'dart:async';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'at_lookup_test_utils.dart';
import 'fake_at_server_transport.dart';

/// A notification start whose read of the caller's watermark is still pending
/// when the caller ends notifications.
void main() {
  const host = '127.0.0.1';
  const port = 12345;
  const watermark = 1755600000000;

  late _AnsweringServer server;
  late MockSecondaryAddressFinder addressFinder;

  /// Completed by the test, as the caller's watermark read.
  late Completer<int?> pendingWatermark;

  /// Completes when the start asks the caller for its watermark.
  late Completer<void> asked;

  setUp(() {
    server = _AnsweringServer();
    pendingWatermark = Completer<int?>();
    asked = Completer<void>();
    addressFinder = MockSecondaryAddressFinder();
    when(() => addressFinder.findSecondary('@alice'))
        .thenAnswer((_) async => SecondaryAddress(host, port));
  });

  AtLookupMuxable build() {
    final atLookup = AtLookUp.withSecureSocket(
      atSign: '@alice',
      rootDomain: const AtRootDomain(host, 64),
      authenticator: (executor) async {
        await executor.sendSync('from:@alice\n');
        return await executor.sendSync('pkam:enrollmentId:E1:c2ln\n') ==
            'data:success';
      },
      secondaryAddressFinder: addressFinder,
      transport: AtLookupTransport(transportFactory: server),
    )..heartbeatInterval = const Duration(hours: 1);
    addTearDown(atLookup.stop);
    return atLookup;
  }

  /// Starts notifications with a watermark read that stays pending until the
  /// test completes [pendingWatermark]; [asked] completes once it is read.
  Future<void> startAwaitingWatermark(AtLookupMuxable atLookup) {
    final start = atLookup.startNotifications(getLastNotificationTime: () {
      asked.complete();
      return pendingWatermark.future;
    });
    // NOTE: a close() fails the start at once; what it did is read from the
    // wire, not from this future.
    start.ignore();
    return start;
  }

  /// Every `monitor:` the server received, on any connection.
  List<String> monitorsSent() => [
        for (final connection in server.connections)
          ...connection.written.where((c) => c.startsWith('monitor:'))
      ];

  /// Opens and logs in a new connection on [atLookup], as another caller of
  /// the lookup does while the start waits on the watermark.
  Future<void> logInAgain(AtLookupMuxable atLookup) async {
    final before = server.connections.length;
    expect(await atLookup.pkamAuthenticate(), isTrue);
    expect(server.connections, hasLength(before + 1),
        reason: 'the premise: a new, logged-in connection is open when the '
            'watermark arrives');
  }

  group('Given a notification start waiting on the caller\'s watermark', () {
    test('when the watermark arrives, then monitor: carries it', () async {
      final atLookup = build();
      final start = startAwaitingWatermark(atLookup);
      await asked.future;

      pendingWatermark.complete(watermark);
      await start;

      expect(monitorsSent(), ['monitor:selfNotifications:$watermark\n'],
          reason: 'the control: this rig sees the monitor: a start sends once '
              'its watermark arrives');
    });

    test(
        'when the caller stops notifications and the lookup logs in again '
        'before the watermark arrives, then no monitor: is sent', () async {
      final atLookup = build();
      final start = startAwaitingWatermark(atLookup);
      await asked.future;

      await atLookup.stopNotifications();
      await logInAgain(atLookup);
      pendingWatermark.complete(watermark);
      await start;

      expect(monitorsSent(), isEmpty,
          reason: 'a start that stopNotifications() ended while it read the '
              'watermark sends monitor: on no connection');
    });

    test(
        'when the caller stops notifications and the lookup logs in again '
        'before the watermark arrives, then the new connection stays open',
        () async {
      final atLookup = build();
      final start = startAwaitingWatermark(atLookup);
      await asked.future;

      await atLookup.stopNotifications();
      await logInAgain(atLookup);
      final loggedInAgain = server.connections.last;
      pendingWatermark.complete(watermark);
      await start;

      expect(loggedInAgain.isOpen, isTrue,
          reason: 'the ended start closes only the connection it logged in');
      expect(await atLookup.executeCommand('scan\n', auth: true), 'data:ok');
      expect(server.connections.last, same(loggedInAgain),
          reason: 'the next command runs on that connection, with no '
              'reconnect and no second login');
    });

    test(
        'when the caller closes the lookup and it logs in again before the '
        'watermark arrives, then no monitor: is sent', () async {
      final atLookup = build();
      unawaited(startAwaitingWatermark(atLookup));
      await asked.future;

      await atLookup.close();
      await logInAgain(atLookup);
      pendingWatermark.complete(watermark);
      // NOTE: the start holds the lookup's request mutex until it lets go, so
      // this command runs only once the start has finished.
      expect(await atLookup.executeCommand('scan\n', auth: true), 'data:ok');

      expect(monitorsSent(), isEmpty,
          reason: 'a start that close() ended while it read the watermark '
              'sends monitor: on no connection');
    });
  });
}

/// An atServer that answers `from:` with a challenge, `pkam:` with success,
/// `monitor:` with nothing, and anything else with `data:ok`.
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
    if (command.startsWith('monitor:')) return;
    final reply = command.startsWith('from:')
        ? 'data:challenge\n@'
        : command.startsWith('pkam:')
            ? 'data:success\n@alice@'
            : 'data:ok\n@alice@';
    unawaited(serverSends(reply));
  }
}
