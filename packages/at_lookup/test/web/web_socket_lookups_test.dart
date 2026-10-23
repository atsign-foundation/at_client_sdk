@TestOn('browser')
library;

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup_web.dart';
import 'package:test/test.dart';

void main() {
  const rootDomain = AtRootDomain('root.example.org', 64);

  AtLookupImpl build(AtLookUpFactory lookUps,
          {SecondaryAddressFinder? secondaryAddressFinder}) =>
      lookUps(
          atSign: '@alice',
          rootDomain: rootDomain,
          authenticator: null,
          secondaryAddressFinder: secondaryAddressFinder) as AtLookupImpl;

  group('webSocketLookUps', () {
    test(
        'resolves through the root domain\'s HTTPS atDirectory and connects '
        'to wss://<atServer>/ws', () {
      final lookUp = build(webSocketLookUps());
      expect(
          lookUp.secondaryAddressFinder,
          isA<HttpsSecondaryAddressFinder>()
              .having((f) => f.host, 'host', 'root.example.org')
              .having((f) => f.port, 'port', 443)
              .having((f) => f.scheme, 'scheme', 'https'));
      expect(
          lookUp.transportFactory,
          isA<WebSocketTransportFactory>()
              .having((f) => f.path, 'path', '/ws')
              .having((f) => f.scheme, 'scheme', 'wss'));
      expect(lookUp.onConnect, isNull);
    });

    test('a caller\'s secondaryAddressFinder wins', () {
      final own = ProxySecondaryAddressFinder('h', 1);
      expect(
          build(webSocketLookUps(), secondaryAddressFinder: own)
              .secondaryAddressFinder,
          same(own));
    });
  });

  group('proxyWebSocketLookUps', () {
    test('every atSign resolves to the proxy', () async {
      final lookUp = build(proxyWebSocketLookUps(host: 'proxy', port: 8443));
      final address =
          await lookUp.secondaryAddressFinder.findSecondary('@anyone');
      expect('$address', 'proxy:8443');
    });

    test('each connection opens with from:<atSign> and nothing else', () async {
      final executor = RecordingExecutor();
      await build(proxyWebSocketLookUps(host: 'proxy', port: 8443))
          .onConnect!(executor);
      expect(executor.sent, ['from:@alice\n']);
    });

    test('onConnect replaces the from: preamble', () {
      Future<void> own(AtCommandExecutor _) async {}
      expect(
          build(proxyWebSocketLookUps(
                  host: 'proxy', port: 8443, onConnect: own))
              .onConnect,
          same(own));
    });
  });
}

class RecordingExecutor implements AtCommandExecutor {
  final sent = <String>[];

  @override
  Future<String> sendSync(String command,
      {int? maxWaitMilliSeconds, int? transientWaitTimeMillis}) async {
    sent.add(command);
    return 'data:ok';
  }
}
