@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:at_client_web/at_client_web_web.dart'
    show
        AtRootDomain,
        Atsign,
        SessionTransport,
        SessionTransportOptions,
        sessionTransport;
import 'package:at_client_web/src/js/bridge.dart'
    show BridgeEntry, openJsSession;
import 'package:at_lookup/at_lookup_web.dart'
    show AtAuthenticator, SecondaryAddressFinder;
import 'package:test/test.dart';

import '../js/bridge_test_helpers.dart' show jsObject, invoke, resolved;
import '../test_utils.dart' show classicalAtKeys;

/// Opens a real session through `create` against a proxy whose first
/// WebSocket upgrade is dropped. To run it, map vip.ve.atsign.zone to
/// 127.0.0.1 in /etc/hosts, as the virtual environment needs, and set
/// `AT_VE_CERTS_DIR` to an at_server checkout's certs folder. Without it the
/// fake throws and the test fails, naming the variable.
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
    // The fake answers frames but runs no PKAM challenge, so the session's
    // connect is the real browser WebSocket while authentication reports
    // success without a handshake.
    final SessionTransport transport = (
      lookUps: ({
        required String atSign,
        required AtRootDomain rootDomain,
        required AtAuthenticator? authenticator,
        SecondaryAddressFinder? secondaryAddressFinder,
      }) =>
          direct.lookUps(
              atSign: atSign,
              rootDomain: rootDomain,
              authenticator: (_) async => true,
              secondaryAddressFinder: secondaryAddressFinder),
      finder: direct.finder,
      root: direct.root,
    );

    final bridge = createJSInteropWrapper(BridgeEntry(
        open: (options) => openJsSession(options, keysTransport: transport),
        isSecureContext: () => true));
    final session = await resolved(invoke(bridge, 'create', [
      jsObject({
        'atSign': '@alice',
        'namespace': 'wavi',
        'keys': classicalAtKeys(atsign: Atsign('@alice')).toJson(),
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
