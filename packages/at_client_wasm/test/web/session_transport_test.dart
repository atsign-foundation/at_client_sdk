@TestOn('browser')
library;

import 'package:at_client/at_client.dart';
import 'package:at_client_wasm/at_client_wasm_web.dart';
import 'package:at_lookup/at_lookup_web.dart';
import 'package:test/test.dart';

void main() {
  Matcher httpsFinderAt(String host, int port) =>
      isA<HttpsSecondaryAddressFinder>()
          .having((f) => f.host, 'host', host)
          .having((f) => f.port, 'port', port)
          .having((f) => f.scheme, 'scheme', 'https');

  test(
      'Transport options with nothing set go direct through the production '
      'atDirectory', () {
    final t = sessionTransport(SessionTransportOptions());

    expect((t.root.rootDomain, t.root.rootPort), ('root.atsign.org', 64),
        reason: 'the default root is the production atDirectory');
    expect(t.finder, httpsFinderAt('root.atsign.org', 64),
        reason: 'Atsigns are looked up at that root over HTTPS');
  });

  test('A root given to the transport options is where Atsigns are looked up',
      () {
    final t = sessionTransport(
        SessionTransportOptions(root: AtRootDomain('root.example', 6464)));

    expect((t.root.rootDomain, t.root.rootPort), ('root.example', 6464),
        reason: "the transport carries the options' root");
    expect(t.finder, httpsFinderAt('root.example', 6464),
        reason: 'Atsigns are looked up at that root over HTTPS');
  });

  test('A proxy given to the transport options becomes a proxy: root',
      () async {
    final t = sessionTransport(
        SessionTransportOptions(proxyHost: 'proxy.example', proxyPort: 443));

    expect((t.root.rootDomain, t.root.rootPort), ('proxy:proxy.example', 443),
        reason: 'a proxy session is built for a proxy: root at its port');
    expect(t.finder, isA<FixedSecondaryAddressFinder>(),
        reason: 'a proxy answers for every Atsign');
    final address = await t.finder.findSecondary('@bob');
    expect((address.host, address.port), ('proxy.example', 443),
        reason: 'every Atsign resolves to the proxy');
  });

  test('A proxy: root given as the root selects that proxy', () async {
    final t = sessionTransport(SessionTransportOptions(
        root: AtRootDomain('proxy:proxy.example', 443)));

    expect(t.finder, isA<FixedSecondaryAddressFinder>(),
        reason: 'a proxy: root is a proxy, not an atDirectory to ask');
    final address = await t.finder.findSecondary('@bob');
    expect((address.host, address.port), ('proxy.example', 443),
        reason: 'a proxy: root sends every Atsign to its host and port');
  });
}
