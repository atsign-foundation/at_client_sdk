@TestOn('browser')
library;

import 'dart:async';

import 'package:at_client_wasm/at_client_wasm_web.dart';
import 'package:test/test.dart';

/// Opens a real connection over TLS to `vip.ve.atsign.zone`. To run it
/// locally, map vip.ve.atsign.zone to 127.0.0.1 in /etc/hosts, as the virtual
/// environment needs, and set `AT_VE_CERTS_DIR` to an at_server checkout's
/// `tools/build_virtual_environment/ve_base/contents/atsign/secondary/base/certs`.
/// Without it the test is skipped, and the skip reason names the variable.
void main() {
  test(
      "a connection from a proxy transport's own lookups sends from:@alice "
      'once, before the first command', () async {
    final proxy = spawnHybridUri('ve_tls_proxy_fake.dart');
    addTearDown(proxy.sink.close);
    final replies = StreamIterator(proxy.stream);
    await replies.moveNext();
    if (replies.current is String) {
      markTestSkipped(replies.current as String);
      return;
    }
    final transport = sessionTransport(SessionTransportOptions(
        proxyHost: 'vip.ve.atsign.zone',
        proxyPort: (replies.current as num).toInt()));
    final lookUp = transport.lookUps(
        atSign: '@alice', rootDomain: transport.root, authenticator: null);
    addTearDown(lookUp.stop);

    await lookUp.executeCommand('scan\n');
    proxy.sink.add('received?');
    await replies.moveNext();
    final received = (replies.current as List).cast<String>();

    expect(
        received.where((frame) => frame.startsWith('from:')), ['from:@alice\n'],
        reason: 'from:@alice is sent exactly once on the connection');
    expect(received, ['from:@alice\n', 'scan\n'],
        reason: 'from:@alice is sent before the command');
  });
}
