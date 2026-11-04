import 'dart:async';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'at_lookup_test_utils.dart';
import 'fake_at_server_transport.dart';

/// Starts of notifications that overlap, on one lookup.
///
/// Catalogue: features/at_lookup/start_notifications_once.feature
void main() {
  const host = '127.0.0.1';
  const port = 12345;
  const watermark = 1755600000000;

  late _AnsweringServer server;
  late MockSecondaryAddressFinder addressFinder;

  /// Completed by the test, as the caller's watermark read.
  late Completer<int?> pendingWatermark;

  /// Completes when the first start asks the caller for its watermark.
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

  /// Every `monitor:` the server received, on any connection.
  List<String> monitorsSent() => [
        for (final connection in server.connections)
          ...connection.written.where((c) => c.startsWith('monitor:'))
      ];

  test('Two starts at once send one monitor:', () async {
    final atLookup = build();
    final first = atLookup.startNotifications(getLastNotificationTime: () {
      asked.complete();
      return pendingWatermark.future;
    });
    await asked.future;

    final second =
        atLookup.startNotifications(getLastNotificationTime: () async => 0);
    pendingWatermark.complete(watermark);
    await Future.wait([first, second]);

    expect(monitorsSent(), ['monitor:selfNotifications:$watermark\n'],
        reason: 'a start made while another is starting joins it');
  });

  test('A start after a stop sends its own monitor:', () async {
    final atLookup = build();
    final first = atLookup.startNotifications(getLastNotificationTime: () {
      asked.complete();
      return pendingWatermark.future;
    });
    await asked.future;

    await atLookup.stopNotifications();
    final second = atLookup.startNotifications(
        getLastNotificationTime: () async => watermark + 1);
    pendingWatermark.complete(watermark);
    await Future.wait([first, second]);

    expect(monitorsSent(), ['monitor:selfNotifications:${watermark + 1}\n'],
        reason: 'a start the stop ended is not joined, so the second start '
            'sends monitor: itself');
  });
}

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
