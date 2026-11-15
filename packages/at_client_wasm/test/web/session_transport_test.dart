@TestOn('browser')
library;

import 'package:at_client/at_client.dart';
import 'package:at_client_wasm/at_client_wasm_web.dart';
import 'package:at_lookup/at_lookup_web.dart';
import 'package:test/test.dart';

void main() {
  test('no proxy resolves atSigns through the root over HTTPS', () {
    final t = sessionTransport(
        SessionTransportOptions(root: AtRootDomain('root.example', 64)));

    final finder = t.finder as HttpsSecondaryAddressFinder;
    expect((finder.host, finder.port), ('root.example', 64));
  });

  test('a proxy sends every atSign to it', () async {
    final t = sessionTransport(
        SessionTransportOptions(proxyHost: 'proxy.example', proxyPort: 443));

    expect(t.finder, isA<FixedSecondaryAddressFinder>());
    final address = await t.finder.findSecondary('@bob');
    expect((address.host, address.port), ('proxy.example', 443));
  });

  test('the default root is the atsign domain', () {
    final t = sessionTransport(SessionTransportOptions());

    final finder = t.finder as HttpsSecondaryAddressFinder;
    expect(finder.host, AtRootDomain.atsignDomain.rootDomain);
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
