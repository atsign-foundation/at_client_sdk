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
      final own = FixedSecondaryAddressFinder('h', 1);
      expect(
          build(webSocketLookUps(), secondaryAddressFinder: own)
              .secondaryAddressFinder,
          same(own));
    });
  });

  group('fixedAddressWebSocketLookUps', () {
    test(
        'every atSign resolves to the one atServer, reached at '
        'wss://<host>:<port>/ws', () async {
      final lookUp =
          build(fixedAddressWebSocketLookUps(host: 'atserver', port: 8443));
      final address =
          await lookUp.secondaryAddressFinder.findSecondary('@anyone');

      expect('$address', 'atserver:8443');
      expect(
          lookUp.transportFactory,
          isA<WebSocketTransportFactory>()
              .having((f) => f.path, 'path', '/ws')
              .having((f) => f.scheme, 'scheme', 'wss'));
    });

    test('sends no preamble unless given an onConnect', () {
      Future<void> own(AtCommandExecutor _) async {}

      expect(
          build(fixedAddressWebSocketLookUps(host: 'atserver', port: 8443))
              .onConnect,
          isNull);
      expect(
          build(fixedAddressWebSocketLookUps(
                  host: 'atserver', port: 8443, onConnect: own))
              .onConnect,
          same(own));
    });
  });
}
