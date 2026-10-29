import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_client_cli/at_client_cli.dart';
import 'package:test/test.dart';

/// [lookUpsFor] decides what a connection sends first from the root domain
/// alone, observed at a TLS server on the loopback interface.
///
/// Catalogue: features/at_client_cli/lookups_for.feature
void main() {
  late Directory certs;
  late SecureServerSocket server;
  late StreamController<String> firstLines;

  setUpAll(() async {
    certs = Directory.systemTemp.createTempSync('lookups_for_test_');
    final made = await Process.run('openssl', [
      'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1', //
      '-subj', '/CN=127.0.0.1',
      '-addext', 'subjectAltName=IP:127.0.0.1',
      // NOTE: macOS verifies through the system, which refuses a self-signed
      // certificate that names no server use.
      '-addext', 'extendedKeyUsage=serverAuth',
      '-addext', 'keyUsage=digitalSignature,keyEncipherment,keyCertSign',
      '-keyout', '${certs.path}/key.pem',
      '-out', '${certs.path}/cert.pem',
    ]);
    expect(made.exitCode, 0,
        reason: 'openssl made no test certificate: ${made.stderr}');
    // NOTE: the default lookUps connect through
    // SecurityContext.defaultContext, which is this test file's isolate's own.
    SecurityContext.defaultContext
        .setTrustedCertificates('${certs.path}/cert.pem');
    server = await SecureServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
        SecurityContext()
          ..useCertificateChain('${certs.path}/cert.pem')
          ..usePrivateKey('${certs.path}/key.pem'));
    firstLines = StreamController.broadcast();
    server.listen((socket) {
      var received = '';
      socket.cast<List<int>>().transform(utf8.decoder).listen((text) {
        received += text;
        final end = received.indexOf('\n');
        if (end >= 0) {
          firstLines.add(received.substring(0, end));
          socket.destroy();
        }
      }, onError: (_) {});
    });
  });

  tearDownAll(() async {
    await server.close();
    certs.deleteSync(recursive: true);
  });

  /// The first line the server receives when a lookup [lookUps] builds for
  /// `@alice` runs `scan`.
  Future<String> firstLineFrom(AtLookUpFactory lookUps) async {
    final lookUp = lookUps(
        atSign: '@alice',
        rootDomain: AtRootDomain.atsignDomain,
        authenticator: null,
        secondaryAddressFinder:
            FixedSecondaryAddressFinder('127.0.0.1', server.port));
    final line = firstLines.stream.first;
    unawaited(lookUp.executeCommand('scan\n').then((_) {}, onError: (_) {}));
    try {
      return await line.timeout(const Duration(seconds: 10));
    } finally {
      await lookUp.close();
    }
  }

  test('Through a proxy, each connection names its atSign first', () async {
    expect(await firstLineFrom(lookUpsFor('proxy:127.0.0.1')), 'from:@alice',
        reason: 'a proxy routes a connection by the atSign it names first');
  });

  test('Straight to an atServer, the command goes first', () async {
    expect(await firstLineFrom(lookUpsFor('root.atsign.org')), 'scan',
        reason: 'an atServer reached directly is sent no from: unasked');
  });
}
