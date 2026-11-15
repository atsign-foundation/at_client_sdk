@TestOn('browser')
library;

import 'package:at_client/at_client.dart';
import 'package:at_client_wasm/at_client_wasm_web.dart';
import 'package:at_lookup/at_lookup_web.dart';
import 'package:test/test.dart';

void main() {
  test('no proxy resolves atSigns through the root over HTTPS', () {
    final t = sessionTransport(DevSessionOptions(
        atSign: '@alice', app: 'wavi', root: AtRootDomain('root.example', 64)));

    final finder = t.finder as HttpsSecondaryAddressFinder;
    expect((finder.host, finder.port), ('root.example', 64));
  });

  test('a proxy sends every atSign to it', () async {
    final t = sessionTransport(DevSessionOptions(
        atSign: '@alice',
        app: 'wavi',
        proxyHost: 'proxy.example',
        proxyPort: 443));

    expect(t.finder, isA<FixedSecondaryAddressFinder>());
    final address = await t.finder.findSecondary('@bob');
    expect((address.host, address.port), ('proxy.example', 443));
  });

  test('the default root is the atsign domain', () {
    final t =
        sessionTransport(DevSessionOptions(atSign: '@alice', app: 'wavi'));

    final finder = t.finder as HttpsSecondaryAddressFinder;
    expect(finder.host, AtRootDomain.atsignDomain.rootDomain);
  });
}
