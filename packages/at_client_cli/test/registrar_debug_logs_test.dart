import 'dart:convert';
import 'dart:io';

import 'package:at_client_cli/src/register/onboarding_util.dart';
import 'package:at_utils/at_utils.dart' show AtSignLogger, LoggingHandler;
import 'package:test/test.dart';

class _RecordedLogs implements LoggingHandler {
  final List<String> messages = [];

  @override
  void call(dynamic record) => messages.add('${record.message}');
}

/// What logging at its finest keeps of a registrar request, observed against
/// a registrar on the loopback interface.
///
/// Catalogue: features/at_client_cli/registrar_debug_logs.feature
void main() {
  const otp = 'OTP7Q2X';
  const cramSecret = 'cram5f1e9a0b';
  late Directory certs;
  late HttpServer registrar;

  setUpAll(() async {
    certs = Directory.systemTemp.createTempSync('registrar_debug_logs_test_');
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
    SecurityContext.defaultContext
        .setTrustedCertificates('${certs.path}/cert.pem');
    registrar = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        SecurityContext()
          ..useCertificateChain('${certs.path}/cert.pem')
          ..usePrivateKey('${certs.path}/key.pem'));
    registrar.listen((request) async {
      await utf8.decoder.bind(request).join();
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(
            {'message': 'Verified', 'cramkey': '@alice:$cramSecret'}));
      await request.response.close();
    });
  });

  tearDownAll(() async {
    await registrar.close(force: true);
    certs.deleteSync(recursive: true);
  });

  test('A registrar request is logged without its body', () async {
    final recorded = _RecordedLogs();
    final level = AtSignLogger.root_level;
    final handler = AtSignLogger.defaultLoggingHandler;
    AtSignLogger.root_level = 'finest';
    AtSignLogger.defaultLoggingHandler = recorded;
    addTearDown(() {
      AtSignLogger.root_level = level;
      AtSignLogger.defaultLoggingHandler = handler;
    });

    final cram = await OnboardingUtil()
        .getCramKey('@alice', otp, authority: '127.0.0.1:${registrar.port}');

    expect(cram, cramSecret,
        reason: 'the premise: the registrar answered and its answer was read');
    expect(recorded.messages, contains(contains('Sending request to url')),
        reason: 'the control: the logger recorded the request at finest');
    expect(
        recorded.messages
            .where((m) => m.contains(otp) || m.contains(cramSecret)),
        isEmpty,
        reason: 'no log line holds the one-time code or the CRAM secret');
    expect(recorded.messages, contains(contains('Got response 200')));
  });
}
