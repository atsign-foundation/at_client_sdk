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
import 'package:stream_channel/stream_channel.dart' show StreamChannel;
import 'package:test/test.dart';

import '../js/bridge_test_helpers.dart'
    show jsObject, invoke, resolved, rejected;
import '../test_utils.dart' show classicalAtKeys;

/// Opens a real session, PKAM included, through `create` against a proxy whose
/// first WebSocket upgrade is dropped; the fake then answers the `from:`
/// challenge and accepts the `pkam:` that follows. To run it, map
/// vip.ve.atsign.zone to 127.0.0.1 in /etc/hosts, as the virtual environment
/// needs, and set `AT_VE_CERTS_DIR` to an at_server checkout's certs folder.
/// Without it the fake throws and the test fails, naming the variable.
void main() {
  // dart2js generates the RSA keys below in pure Dart, which can take tens of seconds.
  const slow = Timeout(Duration(minutes: 2));

  /// Spawns the fake, which verifies each `pkam:` against [verifyWith]'s
  /// public key, and returns the bridge's `create` options for a client that
  /// signs with [signWith]'s private key.
  Future<
          ({
            StreamChannel<Object?> proxy,
            StreamIterator<Object?> replies,
            JSObject bridge,
            JSObject options
          })>
      start(RsaKeyPair signWith, RsaKeyPair verifyWith,
          void Function(void Function()) addTearDown) async {
    final proxy = spawnHybridUri('ve_tls_proxy_fake.dart', message: {
      'mode': 'drop-first-upgrade',
      'pkamPublicKey': verifyWith.atPublicKey.publicKey,
    });
    addTearDown(proxy.sink.close);
    final replies = StreamIterator(proxy.stream);
    await replies.moveNext();
    final port = (replies.current as num).toInt();
    final direct = sessionTransport(SessionTransportOptions(
        proxyHost: 'vip.ve.atsign.zone', proxyPort: port));
    final bridge = createJSInteropWrapper(BridgeEntry(
        open: (options) => openJsSession(options, keysTransport: direct),
        isSecureContext: () => true));
    final options = jsObject({
      'atSign': '@alice',
      'namespace': 'wavi',
      'keys': (classicalAtKeys(atsign: Atsign('@alice'))
            // ignore: deprecated_member_use
            ..apkamPrivateKey =
                AtBytes.fromString(signWith.atPrivateKey.privateKey))
          .toJson(),
    });
    return (proxy: proxy, replies: replies, bridge: bridge, options: options);
  }

  test('create() tolerates one refused connection', () async {
    final pair = RsaKeyPair.generate();
    final run = await start(pair, pair, addTearDown);
    final session =
        await resolved(invoke(run.bridge, 'create', [run.options])) as JSObject;

    run.proxy.sink.add('received?');
    await run.replies.moveNext();
    final received = (run.replies.current as List).cast<String>();
    expect(received, contains('DROP /ws'),
        reason: 'the fake dropped the first WebSocket upgrade');
    expect(received, contains('from:@alice\n'),
        reason: 'a fresh socket then served the open');
    expect(received.where((frame) => frame.startsWith('pkam:')), isNotEmpty,
        reason: 'the open signed, and the fake verified that signature');

    await resolved(invoke(session, 'close'));
  }, timeout: slow);

  test(
      'create() rejects pkam_refused when the signature is not the key the atServer holds',
      () async {
    final run =
        await start(RsaKeyPair.generate(), RsaKeyPair.generate(), addTearDown);
    final failure = await rejected(invoke(run.bridge, 'create', [run.options]));
    expect(failure.code, 'pkam_refused');
  }, timeout: slow);
}
