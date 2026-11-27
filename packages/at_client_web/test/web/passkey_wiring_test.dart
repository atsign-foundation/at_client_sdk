@TestOn('browser')
library;

import 'package:at_client/passkey.dart';
import 'package:at_client_web/at_client_web_web.dart';
import 'package:at_client_web/src/session/passkey_wiring.dart';
import 'package:at_lookup/at_lookup_web.dart';
import 'package:test/test.dart';

import '../session/wire_fakes.dart';
import '../test_utils.dart';

LookupEnrollmentPointerReader _reader(PasskeyServerSide s) =>
    s.pointerReader as LookupEnrollmentPointerReader;

PasskeyServerSide _wire(SessionTransportOptions? options) =>
    passkeyServerSide(options: options, app: 'wavi', device: 'browser');

/// Where [finder] sends [atSign].
Future<(String, int)> _address(SecondaryAddressFinder finder) async {
  final a = await finder.findSecondary('@bob');
  return (a.host, a.port);
}

void main() {
  group('the passkey entry points reach atServers as the options say', () {
    test(
        'a proxy is the root, connections and finder of the reader, the '
        'gateway and the clients it opens', () async {
      final s = _wire(
          SessionTransportOptions(proxyHost: 'proxy.example', proxyPort: 443));
      final reader = _reader(s);
      final gateway = s.gateway;

      for (final root in [reader.rootDomain, gateway.root, s.transport.root]) {
        expect((root.rootDomain, root.rootPort), ('proxy:proxy.example', 443));
      }
      expect(reader.lookUps, same(s.transport.lookUps));
      expect(gateway.lookUps, same(s.transport.lookUps));
      expect(reader.secondaryAddressFinder, same(s.transport.finder));
      expect(gateway.finder, same(s.transport.finder));
      expect(s.transport.finder, isA<FixedSecondaryAddressFinder>());
      expect(await _address(gateway.finder), ('proxy.example', 443));
    });

    test('a root is looked up over HTTPS by the reader and the gateway',
        () async {
      final s = _wire(
          SessionTransportOptions(root: AtRootDomain('root.example', 6464)));
      final reader = _reader(s);

      for (final root in [reader.rootDomain, s.gateway.root]) {
        expect((root.rootDomain, root.rootPort), ('root.example', 6464));
      }
      expect(s.gateway.finder, isA<HttpsSecondaryAddressFinder>());
      expect(reader.secondaryAddressFinder, same(s.gateway.finder));
      expect(
          s.gateway.finder,
          isA<HttpsSecondaryAddressFinder>()
              .having((f) => f.host, 'host', 'root.example')
              .having((f) => f.port, 'port', 6464));
    });

    test('no options go direct through the production atDirectory', () {
      final s = _wire(null);

      expect((s.gateway.root.rootDomain, s.gateway.root.rootPort),
          ('root.atsign.org', 64));
      expect(s.gateway.finder, isA<HttpsSecondaryAddressFinder>());
      expect(s.gateway.app, 'wavi');
      expect(s.gateway.device, 'browser');
    });

    test('the client the gateway opens takes the options\' root', () async {
      final wire = Wire();
      final s = _wire(
          SessionTransportOptions(proxyHost: 'proxy.example', proxyPort: 443));
      final lookUp = wire.lookUps(
          atSign: '@alice',
          rootDomain: s.transport.root,
          authenticator: null,
          secondaryAddressFinder: s.transport.finder);
      addTearDown(() async {
        for (final c
            in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
          await c.stop();
        }
        AtClientImpl.atClientInstanceMap.clear();
        AtClientManager.getInstance().reset();
      });

      final client = await s.gateway.clientOpener(
          lookUp: lookUp,
          atSign: '@alice',
          enrollmentId: 'eid1',
          keysIo:
              SessionKeysIo('@alice', classicalAtKeys(enrollmentId: 'eid1')));

      final prefs = client.getPreferences()!;
      expect((prefs.rootDomain, prefs.rootPort), ('proxy:proxy.example', 443));
      expect(prefs.namespace, 'wavi');
    });

    test(
        'the passkey wiring forwards appName and appVersion to the client '
        'opener', () async {
      final wire = Wire();
      final s = passkeyServerSide(
          options: null,
          app: 'wavi',
          device: 'browser',
          appName: 'Tally',
          appVersion: '1.2.3');
      final lookUp = wire.lookUps(
          atSign: '@alice',
          rootDomain: s.transport.root,
          authenticator: null,
          secondaryAddressFinder: s.transport.finder);
      addTearDown(() async {
        for (final c
            in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
          await c.stop();
        }
        AtClientImpl.atClientInstanceMap.clear();
        AtClientManager.getInstance().reset();
      });

      final client = await s.gateway.clientOpener(
          lookUp: lookUp,
          atSign: '@alice',
          enrollmentId: 'eid1',
          keysIo:
              SessionKeysIo('@alice', classicalAtKeys(enrollmentId: 'eid1')));

      final particulars = client.getPreferences()!.atClientParticulars;
      expect((particulars.appName, particulars.appVersion), ('Tally', '1.2.3'));
    });
  });
}
