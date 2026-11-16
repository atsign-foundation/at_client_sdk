import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup_io.dart';
import 'package:test/test.dart';

/// features/at_lookup/proxy_root_preamble.feature through the default
/// `secureSocketLookUps()` factory, over real TLS on the loopback interface:
/// the other suites reach the preamble only through `AtLookUp.withTransport`.
///
/// The server answers every line with an `ok` and the `@alice@` prompt, so
/// each `sendSync` completes; `lines` is everything it received, in order.
void main() {
  late Directory certs;
  late SecureServerSocket server;
  late SecureServerSocket ipv6Server;
  late List<String> lines;
  late SecureSocketConfig trusting;

  setUpAll(() async {
    certs = Directory.systemTemp.createTempSync('secure_socket_lookups_');
    final made = await Process.run('openssl', [
      'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1', //
      '-subj', '/CN=127.0.0.1',
      '-addext', 'subjectAltName=IP:127.0.0.1,IP:::1',
      // NOTE: macOS verifies through the system, which refuses a self-signed
      // certificate that names no server use.
      '-addext', 'extendedKeyUsage=serverAuth',
      '-addext', 'keyUsage=digitalSignature,keyEncipherment,keyCertSign',
      '-keyout', '${certs.path}/key.pem',
      '-out', '${certs.path}/cert.pem',
    ]);
    expect(made.exitCode, 0,
        reason: 'openssl made no test certificate: ${made.stderr}');
    // NOTE: the transport trusts pathToCerts through
    // SecurityContext.defaultContext, which is this file's isolate's own.
    trusting = SecureSocketConfig()..pathToCerts = '${certs.path}/cert.pem';
    final serverContext = SecurityContext()
      ..useCertificateChain('${certs.path}/cert.pem')
      ..usePrivateKey('${certs.path}/key.pem');
    server = await SecureServerSocket.bind(
        InternetAddress.loopbackIPv4, 0, serverContext);
    ipv6Server = await SecureServerSocket.bind(
        InternetAddress.loopbackIPv6, 0, serverContext);
    for (final listening in [server, ipv6Server]) {
      // NOTE: a client that hangs up mid-handshake surfaces here, not on a
      // socket; it is noise, and unhandled it fails setUpAll after the tests.
      listening.listen((socket) {
        socket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
          lines.add(line);
          socket.write('data:ok\n@alice@');
        }, onError: (_) {});
      }, onError: (_) {});
    }
  });

  setUp(() => lines = []);

  tearDownAll(() async {
    await server.close();
    await ipv6Server.close();
    certs.deleteSync(recursive: true);
  });

  /// A lookup built by `secureSocketLookUps()` for `@alice` at [rootDomain],
  /// connecting to the test server, that has run `noop:0`. With a
  /// [rootPort] the lookup finds the server through its own default finder,
  /// from the root alone.
  Future<void> runCommandAt(String rootDomain,
      {int? rootPort,
      Future<void> Function(AtCommandExecutor connection)? onConnect}) async {
    final lookUp = secureSocketLookUps(config: trusting, onConnect: onConnect)(
        atSign: '@alice',
        rootDomain: AtRootDomain(rootDomain, rootPort ?? 443),
        authenticator: null,
        secondaryAddressFinder: rootPort == null
            ? FixedSecondaryAddressFinder('127.0.0.1', server.port)
            : null);
    try {
      await lookUp
          .executeCommand('noop:0\n')
          .timeout(const Duration(seconds: 10));
    } finally {
      await lookUp.close();
    }
  }

  group('Given a lookup built by secureSocketLookUps() for a proxy root', () {
    test(
        'when it connects and runs a command, then from:<atSign> is the first '
        'thing the server receives', () async {
      await runCommandAt('proxy:127.0.0.1');

      expect(lines, ['from:@alice', 'noop:0']);
    });

    test(
        "when the caller passed an onConnect, then from:<atSign> comes before "
        "the caller's own command on the same connection", () async {
      await runCommandAt('proxy:127.0.0.1',
          onConnect: (c) => c.sendSync('noop:own\n'));

      expect(lines, ['from:@alice', 'noop:own', 'noop:0']);
    });
  });

  test(
      'Given a proxy root naming a bracketed IPv6 literal, when a lookup built '
      'by secureSocketLookUps() runs a command, then it reaches the proxy at '
      'that address and from:<atSign> comes first', () async {
    await runCommandAt('proxy:[::1]', rootPort: ipv6Server.port);

    expect(lines, ['from:@alice', 'noop:0']);
  });

  group('Given a lookup built by secureSocketLookUps() for a plain root', () {
    test(
        'when it connects and runs a command, then the command is the first '
        'thing the server receives', () async {
      await runCommandAt('root.atsign.org');

      expect(lines, ['noop:0']);
    });

    test(
        'when the caller passed an onConnect, then only the caller writes '
        'before the command', () async {
      await runCommandAt('root.atsign.org',
          onConnect: (c) => c.sendSync('noop:own\n'));

      expect(lines, ['noop:own', 'noop:0']);
    });
  });
}
