@TestOn('browser')
library;

import 'dart:async';

import 'package:at_client_web/at_client_web_web.dart';
import 'package:at_lookup/at_lookup_web.dart';
import 'package:test/test.dart';

import 've_tls_proxy_fake.dart' show aliceAddress;

/// A transport and an atDirectory finder named by the bracketed IPv6 literal
/// `[::1]`, over TLS to a fake bound to `::1`. Set `AT_IPV6_CERTS_DIR` to a
/// folder holding a `fullchain.pem` and `privkey.pem` for `IP:::1` that
/// Chrome trusts, such as one issued by a CA added to its trust store.
/// Without it each test is skipped, and the skip reason names the variable.
void main() {
  /// The fake's port, or null once the test is marked skipped, and the
  /// replies that follow it.
  Future<(int?, StreamIterator<dynamic>, StreamSink<dynamic>)>
      ipv6Fake() async {
    final fake = spawnHybridUri('ve_tls_proxy_fake.dart', message: 'ipv6');
    addTearDown(fake.sink.close);
    final replies = StreamIterator(fake.stream);
    await replies.moveNext();
    if (replies.current is String) {
      markTestSkipped(replies.current as String);
      return (null, replies, fake.sink);
    }
    return ((replies.current as num).toInt(), replies, fake.sink);
  }

  Future<List<String>> receivedBy(
      StreamIterator<dynamic> replies, StreamSink<dynamic> sink) async {
    sink.add('received?');
    await replies.moveNext();
    return (replies.current as List).cast<String>();
  }

  for (final (given, options) in [
    (
      'a proxyHost',
      (int port) => SessionTransportOptions(proxyHost: '[::1]', proxyPort: port)
    ),
    (
      'a proxy: root',
      (int port) =>
          SessionTransportOptions(root: AtRootDomain('proxy:[::1]', port))
    ),
  ]) {
    test(
        'Given $given naming [::1], a connection from its own lookups opens '
        'wss://[::1]:<port>/ws and sends from:@alice once, before the first '
        'command', () async {
      final (port, replies, sink) = await ipv6Fake();
      if (port == null) return;
      final transport = sessionTransport(options(port));
      final lookUp = transport.lookUps(
          atSign: '@alice', rootDomain: transport.root, authenticator: null);
      addTearDown(lookUp.stop);

      await lookUp.executeCommand('scan\n');
      final received = await receivedBy(replies, sink);

      expect(received.where((frame) => frame.startsWith('from:')),
          ['from:@alice\n'],
          reason: 'from:@alice is sent exactly once on the connection');
      expect(received, ['from:@alice\n', 'scan\n'],
          reason: 'from:@alice is sent before the command, over the '
              'WebSocket at [::1]');
    });
  }

  test(
      'An atDirectory named by a bracketed IPv6 literal is asked at that '
      'address', () async {
    final (port, replies, sink) = await ipv6Fake();
    if (port == null) return;
    final finder = HttpsSecondaryAddressFinder('[::1]', port: port);

    final address = await finder.findSecondary('@alice');

    expect(address.toString(), aliceAddress,
        reason: 'the answer of the atDirectory at [::1]');
    expect(await receivedBy(replies, sink), ['GET /@alice'],
        reason: 'one request, for @alice, reached the fake at ::1');
  });
}
