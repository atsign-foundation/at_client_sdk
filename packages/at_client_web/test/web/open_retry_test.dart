@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:at_chops/at_chops.dart' show RsaKeyPair;
import 'package:at_client_web/at_client_web_web.dart'
    show Atsign, SessionTransportOptions, sessionTransport;
import 'package:at_client_web/src/js/bridge.dart'
    show BridgeEntry, openJsSession;
import 'package:at_commons/at_commons.dart' show AtBytes;
import 'package:test/test.dart';

import '../js/bridge_test_helpers.dart' show jsObject, invoke, resolved;
import '../test_utils.dart' show classicalAtKeys;

/// Opens a real session, PKAM included, through `create` against a proxy whose
/// first WebSocket upgrade is dropped; the fake then answers the `from:`
/// challenge and accepts the `pkam:` that follows. To run it, map
/// vip.ve.atsign.zone to 127.0.0.1 in /etc/hosts, as the virtual environment
/// needs, and set `AT_VE_CERTS_DIR` to an at_server checkout's certs folder.
/// Without it the fake throws and the test fails, naming the variable.
void main() {
  test('create() tolerates one refused connection', () async {
    final proxy =
        spawnHybridUri('ve_tls_proxy_fake.dart', message: 'drop-first-upgrade');
    addTearDown(proxy.sink.close);
    final replies = StreamIterator(proxy.stream);
    await replies.moveNext();
    final port = (replies.current as num).toInt();

    final direct = sessionTransport(SessionTransportOptions(
        proxyHost: 'vip.ve.atsign.zone', proxyPort: port));

    final bridge = createJSInteropWrapper(BridgeEntry(
        open: (options) => openJsSession(options, keysTransport: direct),
        isSecureContext: () => true));
    final session = await resolved(invoke(bridge, 'create', [
      jsObject({
        'atSign': '@alice',
        'namespace': 'wavi',
        'keys': (classicalAtKeys(atsign: Atsign('@alice'))
              // ignore: deprecated_member_use
              ..apkamPrivateKey = AtBytes.fromString(
                  RsaKeyPair.generate().atPrivateKey.privateKey))
            .toJson(),
      })
    ])) as JSObject;

    proxy.sink.add('received?');
    await replies.moveNext();
    final received = (replies.current as List).cast<String>();
    expect(received, contains('DROP /ws'),
        reason: 'the fake dropped the first WebSocket upgrade');
    expect(received, contains('from:@alice\n'),
        reason: 'a fresh socket then served the open');

    await resolved(invoke(session, 'close'));
  });
}
