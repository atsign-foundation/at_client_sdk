@TestOn('browser')
library;

import 'dart:async';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup_web.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

/// Catalogue: features/at_lookup/transports.feature
///
/// Over `ws` and plain HTTP: that [webSocketLookUps] uses `wss` and an
/// HTTPS atDirectory is `web_socket_lookups_test.dart`'s.
void main() {
  /// Spawns [server], which sends its port first and then, for the fake
  /// atDirectory, each path it was asked for, kept in [paths].
  Future<(StreamChannel, int)> spawn(String server,
      [List<String>? paths]) async {
    final channel = spawnHybridUri(server);
    final port = Completer<int>();
    channel.stream.listen((event) => port.isCompleted
        ? paths?.add(event as String)
        : port.complete((event as num).toInt()));
    return (channel, await port.future);
  }

  group('against an atDirectory and its atServer', () {
    late StreamChannel channel;
    late int port;
    final paths = <String>[];

    setUpAll(() async {
      (channel, port) = await spawn('atserver_fake.dart', paths);
    });

    tearDownAll(() => channel.sink.close());

    setUp(paths.clear);

    AtLookupMuxable lookUpFor(String atSign) => AtLookUp.withTransport(
        atSign: atSign,
        rootDomain: AtRootDomain('127.0.0.1', port),
        authenticator: null,
        transport: webSocketTransport(scheme: 'ws'),
        secondaryAddressFinder:
            HttpsSecondaryAddressFinder('127.0.0.1', port: port, scheme: 'http'));

    test(
        'A browser lookup finds its atServer through the atDirectory\'s '
        'HTTPS face', () async {
      final lookUp = lookUpFor('@alice');
      addTearDown(lookUp.stop);

      expect(await lookUp.executeCommand('scan\n'), 'data:ok:scan');

      expect(paths, ['/@alice', '/ws'],
          reason: 'it asked the atDirectory, then opened /ws at the host '
              'and port the answer named, and ran the command there');
    });

    test('A browser lookup asks for the atSign in canonical form', () async {
      final lookUp = lookUpFor('@Alice');
      addTearDown(lookUp.stop);

      await lookUp.executeCommand('scan\n');

      expect(paths.first, '/@alice');
    });
  });

  test('A WebSocket connect that never opens gives up', () async {
    final (channel, port) = await spawn('silent_server.dart');
    addTearDown(() => channel.sink.close());
    final previous = AtNetworkTimeouts.defaultTimeout;
    AtNetworkTimeouts.defaultTimeout = const Duration(milliseconds: 300);
    addTearDown(() => AtNetworkTimeouts.defaultTimeout = previous);
    final lookUp = AtLookUp.withTransport(
        atSign: '@alice',
        rootDomain: const AtRootDomain('127.0.0.1', 64),
        authenticator: null,
        transport: webSocketTransport(scheme: 'ws'),
        secondaryAddressFinder: FixedSecondaryAddressFinder('127.0.0.1', port));
    addTearDown(lookUp.stop);

    await expectLater(
        lookUp.executeCommand('scan\n'),
        throwsA(isA<SecondaryConnectException>().having(
            (e) => e.message, 'message', contains('no answer within'))));
  }, timeout: const Timeout(Duration(seconds: 10)));
}
