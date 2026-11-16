import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_client_cli/at_client_cli.dart';
import 'package:at_client_cli/src/commands/auth_cli.dart' show deleteStorage;
import 'package:test/test.dart';

import 'from_recorder.dart';
import 'keyfile_helpers.dart';

/// The app a command's client names on its authenticating `from:`: the
/// calling program's own for the public [createAtClient], and the program
/// at_activate runs as for its own commands, onboard among them. Observed at a
/// TLS proxy on the loopback interface, which answers the proxy's
/// `from:@alice`, keeps the authenticating `from:` that follows it, and
/// answers anything else with `data:null`.
void main() {
  AtSignLogger.root_level = 'SHOUT';
  late Directory certs;
  late Directory dir;
  late SecureServerSocket proxy;
  late StreamController<String> configs;

  setUpAll(() async {
    certs = Directory.systemTemp.createTempSync('create_at_client_names_');
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
    proxy = await SecureServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
        SecurityContext()
          ..useCertificateChain('${certs.path}/cert.pem')
          ..usePrivateKey('${certs.path}/key.pem'));
    configs = StreamController.broadcast();
    // NOTE: a client that hangs up mid-handshake surfaces here, not on a
    // socket; it is noise, and unhandled it fails setUpAll after the tests.
    proxy.listen((socket) {
      var received = '';
      socket.cast<List<int>>().transform(utf8.decoder).listen((text) {
        received += text;
        for (var end = received.indexOf('\n');
            end >= 0;
            end = received.indexOf('\n')) {
          final line = received.substring(0, end);
          received = received.substring(end + 1);
          if (line == 'from:@alice') {
            socket.write('data:ok\n@');
          } else if (line.startsWith('from:@alice:clientConfig:')) {
            configs.add(line.substring('from:@alice:clientConfig:'.length));
            socket.destroy();
          } else if (line.startsWith('enroll:request:')) {
            socket.write('data:{"enrollmentId":"e-1","status":"pending"}\n@');
          } else {
            socket.write('data:null\n@');
          }
        }
      }, onError: (_) {});
    }, onError: (_) {});
  });

  tearDownAll(() async {
    await proxy.close();
    certs.deleteSync(recursive: true);
  });

  setUp(() => dir = Directory.systemTemp.createTempSync('create_at_client_'));

  tearDown(() async {
    for (final client
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await client.stop();
    }
    AtClientImpl.atClientInstanceMap.clear();
    AtClientManager.getInstance().reset();
    deleteStorage();
    dir.deleteSync(recursive: true);
  });

  /// A keyfile for `@alice`, at a path under the test's directory.
  Future<String> keyfile() async {
    final path = '${dir.path}/keys/key.atKeys';
    await FileAtKeysIo(filePath: (_) => path)
        .write('@alice', randomLegacyKeys());
    return path;
  }

  /// The clientConfig of the first authenticating `from:` the proxy receives
  /// while [run] runs; [run]'s own failure, once the proxy hangs up, is
  /// expected and ignored.
  Future<Map<String, dynamic>> firstConfigWhile(Future<Object?> run) async {
    final first = configs.stream.first;
    final finished = run.then((_) {}, onError: (_) {});
    final config = jsonDecode(await first.timeout(const Duration(seconds: 20)))
        as Map<String, dynamic>;
    await finished;
    return config;
  }

  /// The clientConfig of the first authenticating `from:` the proxy receives
  /// from at_activate run in a process of its own with [arguments], as
  /// [program] (`AtActivate` for its own entry point), and a home directory
  /// of its own. The process is ended once that `from:` arrives.
  Future<Map<String, dynamic>> firstConfigFromProcess(
      String program, List<String> Function(String home) arguments) async {
    final home = Directory.systemTemp.createTempSync('from_names_home_');
    final first = configs.stream.first;
    final process = await Process.start(Platform.resolvedExecutable, [
      'test/fixtures/at_activate_through_proxy.dart',
      '${certs.path}/cert.pem',
      program,
      ...arguments(home.path),
    ], environment: {
      'HOME': home.path
    });
    final errors = process.stderr.transform(utf8.decoder).join();
    unawaited(process.stdout.drain<void>());
    try {
      final config = await Future.any([
        first,
        process.exitCode.then((code) async => throw StateError(
            'at_activate exited $code before it authenticated: '
            '${await errors}')),
      ]).timeout(const Duration(seconds: 90));
      return jsonDecode(config) as Map<String, dynamic>;
    } finally {
      process.kill();
      await process.exitCode;
      home.deleteSync(recursive: true);
    }
  }

  /// An onboard command line for `@alice` through the proxy, over in one
  /// provisioning check.
  List<String> onboard(String home) => [
        'onboard', '-a', '@alice', '-c', 'the-one-time-secret', //
        '-r', 'proxy:127.0.0.1:${proxy.port}',
        '--posture', 'legacy', '--max-retries', '1',
      ];

  test(
      'Given at_activate\'s onboard command line, when AtActivate.main runs '
      'it, then its CRAM from: names at_activate at at_client_cli\'s version',
      () async {
    final config = await firstConfigFromProcess('AtActivate', onboard);

    expect(config['appName'], 'at_activate');
    expect(config['appVersion'], pubspecVersion());
    expect(config['sdkName'], 'atsign.dart.at_client');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test(
      'Given at_register\'s onboard command line, when at_activate runs it as '
      'at_register, then its CRAM from: names at_register', () async {
    final config = await firstConfigFromProcess('at_register', onboard);

    expect(config['appName'], 'at_register');
    expect(config['appVersion'], pubspecVersion());
  }, timeout: const Timeout(Duration(minutes: 3)));

  test(
      'Given at_activate run as another program, when its enroll command\'s '
      'approval handshake authenticates, then its from: names that program',
      () async {
    final config = await firstConfigFromProcess(
        'acme_admin',
        (home) => [
              'enroll', '-a', '@alice', '-k', '$home/keys/@alice_key.atKeys', //
              '-r', 'proxy:127.0.0.1:${proxy.port}',
              '-s', 'ABC123', '-p', 'wavi', '-d', 'phone', '-n', 'wavi:rw',
              '--posture', 'pqReady',
            ]);

    expect(config['appName'], 'acme_admin');
    expect(config['sdkName'], 'atsign.dart.at_client');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test(
      'Given a program outside at_client_cli, when the client createAtClient '
      'opens authenticates, then its from: names the program file', () async {
    final keysPath = await keyfile();

    final config = await firstConfigWhile(createAtClient(
        atSign: '@alice',
        atKeysFilePath: keysPath,
        rootDomain: 'proxy:127.0.0.1:${proxy.port}',
        posture: PqPosture.legacy,
        waitForPqStartup: false,
        maxConnectAttempts: 1));

    expect(
        config['appName'], Platform.script.pathSegments.last.split('.').first,
        reason: 'the calling program names no app through createAtClient, so '
            'it is named after its program file, not at_activate');
    expect(config['appVersion'], 'unknown',
        reason: 'the calling program names no version through createAtClient');
    expect(config['sdkName'], 'atsign.dart.at_client',
        reason: 'the control: this is at_client\'s config');
  });

  test(
      'Given a program outside at_client_cli that passes appName and '
      'appVersion, when the client createAtClient opens authenticates, then '
      'its from: names them', () async {
    final keysPath = await keyfile();

    final config = await firstConfigWhile(createAtClient(
        atSign: '@alice',
        atKeysFilePath: keysPath,
        rootDomain: 'proxy:127.0.0.1:${proxy.port}',
        posture: PqPosture.legacy,
        waitForPqStartup: false,
        maxConnectAttempts: 1,
        appName: 'acme_admin',
        appVersion: '3.2.1'));

    expect(config['appName'], 'acme_admin');
    expect(config['appVersion'], '3.2.1');
    expect(config['sdkName'], 'atsign.dart.at_client');
  });

  test(
      'Given at_activate\'s list command, when its client authenticates, '
      'then its from: names at_activate at at_client_cli\'s version', () async {
    final keysPath = await keyfile();

    final config = await firstConfigWhile(AtActivate.main([
      'list', '-a', '@alice', '-k', keysPath, //
      '-r', 'proxy:127.0.0.1:${proxy.port}',
      '--posture', 'legacy', '--mca', '1',
    ]));

    expect(config['appName'], 'at_activate');
    expect(config['appVersion'], pubspecVersion());
    expect(config['sdkName'], 'atsign.dart.at_client');
  });
}
