import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'dart:typed_data';

import 'package:at_auth/at_auth.dart'
    show
        AtKeysPassphraseEnvelopeCodec,
        CryptographicMaterial,
        CryptographicMaterialAlgorithm,
        CryptographicMaterialRole,
        CryptographicMaterialStatus;
import 'package:at_chops/at_chops.dart'
    show AESEncryptionAlgo, AESKey, InitialisationVector, RsaKeyPair;
import 'package:at_client_cli/at_client_cli.dart';
import 'package:at_client_cli/src/commands/auth_cli.dart' show absentKeysHint;
import 'package:at_lookup/at_lookup.dart' show AtAuthenticator;
import 'package:test/test.dart';

import 'keyfile_helpers.dart';
import 'lifecycle_rig.dart';

/// How a fake atDirectory answers for `@alice`: the atServer's address, or
/// no entry.
enum _AtDirectory { atServer, noEntry }

/// How a fake atServer answers a lookup of `@alice`'s public key: with it,
/// with the error for a key it does not hold, or with a line that is
/// neither.
enum _PublicKey { held, absent, garbled }

/// at_activate, run as a program with a home directory of the test's, and a
/// program built on CLIBase, report a keys problem once.
///
/// Catalogue: features/at_client_cli/keys_problems_said_once.feature
///
/// The atDirectory and the atServer are TLS servers on the loopback
/// interface, under a certificate the at_activate process alone trusts, so
/// nothing reaches root.atsign.org.
void main() {
  const atSign = '@alice';
  const footer = 'Need help? support@atsign.com. Never send anyone your '
      '.atKeys file, support included.';
  late Directory certs;
  late String program;
  late SecureServerSocket atDirectory;
  late SecureServerSocket atServer;
  var directoryAnswer = _AtDirectory.atServer;
  late int atServerPort;
  var publicKeyAnswer = _PublicKey.absent;
  late int unreachablePort;
  late Directory home;
  late SecureServerSocket silentAtDirectory;
  final silentSockets = <SecureSocket>[];
  var directoryConnections = 0;
  final atServerHangUps = StreamController<void>.broadcast();

  setUpAll(() async {
    certs = Directory.systemTemp.createTempSync('keys_problems_said_once_');
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
    final context = SecurityContext()
      ..useCertificateChain('${certs.path}/cert.pem')
      ..usePrivateKey('${certs.path}/key.pem');

    atServer =
        await SecureServerSocket.bind(InternetAddress.loopbackIPv4, 0, context);
    atServer.listen((socket) {
      utf8.decoder.bind(socket).transform(const LineSplitter()).listen(
          (command) {
        final answer = !command.startsWith('lookup:publickey')
            ? 'error:{"errorCode":"AT0003","errorDescription":"unexpected"}'
            : switch (publicKeyAnswer) {
                _PublicKey.held => 'data:${base64Encode(List.filled(32, 7))}',
                _PublicKey.absent =>
                  'error:{"errorCode":"AT0015","errorDescription":'
                      '"public:publickey$atSign does not exist in keystore"}',
                _PublicKey.garbled => '@unexpected@',
              };
        socket.write('$answer\n@');
      }, onError: (_) {}, onDone: () => atServerHangUps.add(null));
    }, onError: (_) {});

    atDirectory =
        await SecureServerSocket.bind(InternetAddress.loopbackIPv4, 0, context);
    atDirectory.listen((socket) {
      directoryConnections++;
      socket.write('@');
      utf8.decoder.bind(socket).transform(const LineSplitter()).listen((line) {
        if (line.startsWith('@exit')) return;
        socket.write(directoryAnswer == _AtDirectory.atServer
            ? '@127.0.0.1:$atServerPort\n@'
            : '@null\n@');
      }, onError: (_) {});
    }, onError: (_) {});

    silentAtDirectory =
        await SecureServerSocket.bind(InternetAddress.loopbackIPv4, 0, context);
    silentAtDirectory.listen(silentSockets.add, onError: (_) {});

    // NOTE: for the hint lookups this process makes itself; at_activate runs
    // trust it through the fixture.
    SecurityContext.defaultContext
        .setTrustedCertificates('${certs.path}/cert.pem');

    unreachablePort = await refusedPort();
    program = '${certs.path}/at_activate_trusting.dill';
    final compiled = await Process.run(Platform.resolvedExecutable, [
      'compile', 'kernel', 'test/fixtures/at_activate_trusting.dart', //
      '-o', program,
    ]);
    expect(compiled.exitCode, 0,
        reason: 'the at_activate fixture did not compile: ${compiled.stderr}');
  });

  tearDownAll(() async {
    for (final socket in silentSockets) {
      socket.destroy();
    }
    await silentAtDirectory.close();
    await atDirectory.close();
    await atServer.close();
    certs.deleteSync(recursive: true);
  });

  setUp(() {
    home = Directory.systemTemp.createTempSync('keys_problems_home_');
    directoryAnswer = _AtDirectory.atServer;
    atServerPort = atServer.port;
    publicKeyAnswer = _PublicKey.absent;
    directoryConnections = 0;
  });

  tearDown(() => home.deleteSync(recursive: true));

  String defaultKeyfile() => '${home.path}/.atsign/keys/${atSign}_key.atKeys';
  String atDirectoryRoot() => '127.0.0.1:${atDirectory.port}';

  /// at_activate run with [args], [home] as its home directory: its exit code
  /// and the lines it wrote to stderr, without colour.
  Future<({int exitCode, List<String> stderr})> atActivate(
      List<String> args) async {
    final environment = Map.of(Platform.environment)
      ..remove('AT_REGISTRAR_API_KEY')
      ..['HOME'] = home.path
      ..['AT_ACTIVATE_TEST_CERT'] = '${certs.path}/cert.pem';
    final process = await Process.start(
        Platform.resolvedExecutable, [program, ...args],
        environment: environment, includeParentEnvironment: false);
    final stderr = process.stderr.transform(utf8.decoder).join();
    unawaited(process.stdout.drain<void>());
    await process.stdin.close();
    final exitCode = await process.exitCode.timeout(const Duration(seconds: 90),
        onTimeout: () {
      process.kill();
      return -1;
    });
    final text = (await stderr)
        .replaceAll(RegExp(r'\x1b\[[0-9;]*[A-Za-z]'), '')
        .replaceAll('\r', '\n');
    return (exitCode: exitCode, stderr: text.split('\n'));
  }

  /// Matches stderr lines holding each of [lines] once, in order.
  Matcher holdsOnceInOrder(List<String> lines) => predicate<List<String>>((
        written,
      ) {
        var from = 0;
        for (final line in lines) {
          if (written.where((w) => w == line).length != 1) return false;
          final at = written.indexOf(line);
          if (at < from) return false;
          from = at;
        }
        return true;
      }, 'holding each of $lines once, in that order');

  group('No keys and the atSign not yet activated', () {
    for (final command in ['otp', 'list', 'approve']) {
      test(command, () async {
        final run =
            await atActivate([command, '-a', atSign, '-r', atDirectoryRoot()]);

        expect(
            run.stderr,
            holdsOnceInOrder([
              'No keys for $atSign at ${defaultKeyfile()}.',
              '$atSign has not been activated yet. To activate it: '
                  'at_activate onboard -a $atSign',
              footer,
            ]));
        expect(run.exitCode, 1);
      }, timeout: const Timeout(Duration(minutes: 2)));
    }
  });

  test('No keys and the atSign activated elsewhere', () async {
    publicKeyAnswer = _PublicKey.held;

    final run =
        await atActivate(['otp', '-a', atSign, '-r', atDirectoryRoot()]);

    expect(
        run.stderr,
        holdsOnceInOrder([
          'No keys for $atSign at ${defaultKeyfile()}.',
          '$atSign is activated, but not on this machine. Run this command on '
              'the machine that activated it, or enroll this machine first.',
          footer,
        ]));
    expect(run.exitCode, 1);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('No keys and the atSign not in the atDirectory', () async {
    directoryAnswer = _AtDirectory.noEntry;

    final run =
        await atActivate(['otp', '-a', atSign, '-r', atDirectoryRoot()]);

    expect(
        run.stderr,
        holdsOnceInOrder([
          'No keys for $atSign at ${defaultKeyfile()}.',
          '$atSign is not in the atDirectory at ${atDirectoryRoot()}. Check '
              'the spelling, or -r.',
          footer,
        ]));
    expect(run.exitCode, 1);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('No keys and the atDirectory unreachable', () async {
    final run = await atActivate(
        ['otp', '-a', atSign, '-r', '127.0.0.1:$unreachablePort']);

    expect(
        run.stderr,
        holdsOnceInOrder([
          'No keys for $atSign at ${defaultKeyfile()}.',
          '  Not activated yet?             at_activate onboard -a $atSign',
          '  Activated on another machine?  Run this command there, or enroll '
              'this machine first.',
          footer,
        ]));
    expect(run.exitCode, 1);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('A passphrase-protected keyfile without its passphrase', () async {
    await FileAtKeysIo(
            filePath: (_) => defaultKeyfile(), passPhrase: 'passphrase-4e1b9a')
        .write(atSign, randomLegacyKeys());

    final run =
        await atActivate(['otp', '-a', atSign, '-r', atDirectoryRoot()]);

    expect(
        run.stderr,
        holdsOnceInOrder([
          'Could not read the keys for $atSign at ${defaultKeyfile()}: the '
              'passphrase is wrong or missing.',
          '  If the keyfile has a passphrase, pass it with -P.',
          footer,
        ]));
    expect(run.exitCode, 1);
    expect(directoryConnections, 0, reason: 'only absent keys are looked up');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('A keyfile for another atSign', () async {
    final path = '${home.path}/bob_key.atKeys';
    final apkam = RsaKeyPair.generate();
    // NOTE: typed material, as a keyfile records its atSign only beside it.
    await FileAtKeysIo(filePath: (_) => path).write(
        '@bob',
        randomLegacyKeys()
          ..fileApkamMaterial(
              enrollmentId: 'e-bob',
              algorithm: CryptographicMaterialAlgorithm.rsa2048,
              publicKey: apkam.atPublicKey.publicKey,
              privateKey: apkam.atPrivateKey.privateKey));
    expect(
        (await FileAtKeysIo(filePath: (_) => path).read(atSign)).atsign, '@bob',
        reason: 'the precondition: the keyfile records @bob');

    final run = await atActivate(
        ['otp', '-a', atSign, '-k', path, '-r', atDirectoryRoot()]);

    expect(
        run.stderr,
        holdsOnceInOrder([
          'The keys at $path are for @bob, not $atSign. Check -a and -k.',
          footer,
        ]));
    expect(run.exitCode, 1);
    expect(directoryConnections, 0, reason: 'only absent keys are looked up');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test(
      'A keys problem is said once, with no prefix, retry advice or stack '
      'trace', () async {
    final run =
        await atActivate(['otp', '-a', atSign, '-r', atDirectoryRoot()]);
    final written = run.stderr.where((l) => l.trim().isNotEmpty).toList();

    expect(written, contains('No keys for $atSign at ${defaultKeyfile()}.'),
        reason: 'the control: the keys problem was reported');
    expect(written.toSet().length, written.length,
        reason: 'no line appears twice: $written');
    expect(written.join('\n'), isNot(contains('ERROR: otp : Exception:')));
    expect(written.join('\n'), isNot(contains('Please try again')));
    expect(written.where((l) => RegExp(r'^#\d+\s|\(package:').hasMatch(l)),
        isEmpty,
        reason: 'no stack trace');
  }, timeout: const Timeout(Duration(minutes: 2)));

  group(
      'the passphrase line is for a passphrase-protected keyfile that '
      'cannot be decrypted, and nothing else', () {
    test(
        'a keyfile that is not passphrase-protected, with a field that '
        'cannot be decrypted', () async {
      final key = AESKey.generate(32).key;
      // NOTE: one block whose plaintext ends in a zero byte, which is no
      // valid padding.
      final block = (await AESEncryptionAlgo(AESKey(key)).encrypt(
              Uint8List.fromList([...List.filled(15, 65), 0]),
              iv: InitialisationVector.legacy()))
          .sublist(0, 16);
      File(defaultKeyfile())
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({
          'selfEncryptionKey': key,
          'aesPkamPrivateKey': base64Encode(block),
        }));

      final run =
          await atActivate(['otp', '-a', atSign, '-r', atDirectoryRoot()]);
      final first = 'The keys for $atSign at ${defaultKeyfile()} could not be '
          'read: ';

      expect(run.stderr.where((l) => l.startsWith(first)), hasLength(1),
          reason: 'the library message: ${run.stderr}');
      expect(run.stderr.join('\n'), isNot(contains('passphrase')));
      expect(run.exitCode, 1);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test(
        'a passphrase-protected keyfile, decrypted, with a field of the '
        'wrong type', () async {
      const passPhrase = 'passphrase-90c2d7';
      File(defaultKeyfile())
        ..createSync(recursive: true)
        ..writeAsStringSync(await const AtKeysPassphraseEnvelopeCodec().encode(
            jsonEncode({
              'selfEncryptionKey': AESKey.generate(32).key,
              'aesPkamPublicKey': 5,
            }),
            passPhrase));

      final run = await atActivate(
          ['otp', '-a', atSign, '-P', passPhrase, '-r', atDirectoryRoot()]);

      expect(
          run.stderr,
          holdsOnceInOrder([
            "The keys for $atSign at ${defaultKeyfile()} could not be read: "
                "type 'int' is not a subtype of type 'String' in type cast.",
            footer,
          ]));
      expect(run.stderr.join('\n'), isNot(contains('pass it with -P')));
      expect(run.exitCode, 1);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  test(
      'a keyfile holding only a pending enrollment request says to wait for '
      'its approval', () async {
    await FileAtKeysIo(filePath: (_) => defaultKeyfile()).write(
        atSign,
        AtKeys()
          ..addKey(CryptographicMaterial(
              keyId: 'apkam:e-1:1',
              enrollmentId: 'e-1',
              role: CryptographicMaterialRole.privateAuthentication,
              algorithm: CryptographicMaterialAlgorithm.rsa2048,
              bytes: AtBytes.fromString(base64Encode(List.filled(32, 3))),
              createdAt: DateTime.now().toUtc(),
              status: CryptographicMaterialStatus.pending)));

    final run =
        await atActivate(['otp', '-a', atSign, '-r', atDirectoryRoot()]);

    expect(
        run.stderr,
        holdsOnceInOrder([
          'This keyfile holds only a pending enrollment request for $atSign '
              '(id e-1). Wait for it to be approved, then run this command '
              'again.',
          footer,
        ]));
    expect(run.exitCode, 1);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test(
      'the absent keys\' lookup gives both hints when the atDirectory does '
      'not answer within 5 seconds', () async {
    final elapsed = Stopwatch()..start();
    final run = await atActivate(
        ['otp', '-a', atSign, '-r', '127.0.0.1:${silentAtDirectory.port}']);
    elapsed.stop();

    expect(
        run.stderr,
        holdsOnceInOrder([
          'No keys for $atSign at ${defaultKeyfile()}.',
          '  Not activated yet?             at_activate onboard -a $atSign',
          '  Activated on another machine?  Run this command there, or enroll '
              'this machine first.',
          footer,
        ]));
    expect(silentSockets, isNotEmpty,
        reason: 'the control: the lookup reached the silent atDirectory');
    expect(elapsed.elapsed, lessThan(const Duration(seconds: 20)),
        reason: 'the lookup is given 5 seconds, not the network timeout');
    expect(run.exitCode, 1);
  }, timeout: const Timeout(Duration(minutes: 2)));

  group('the hint lookup, made from this process', () {
    test('closes its connection to the atServer', () async {
      final hungUp = atServerHangUps.stream.first;

      expect(await absentKeysHint(atSign, atDirectoryRoot()), [
        '$atSign has not been activated yet. To activate it: at_activate '
            'onboard -a $atSign'
      ]);
      await hungUp.timeout(const Duration(seconds: 5));
    });

    test('reads an answer that is not data as no public key', () async {
      publicKeyAnswer = _PublicKey.garbled;

      expect(await absentKeysHint(atSign, atDirectoryRoot()), [
        '$atSign has not been activated yet. To activate it: at_activate '
            'onboard -a $atSign'
      ]);
    });
  });

  test('A program built on CLIBase says the same', () async {
    final dir = Directory.systemTemp.createTempSync('keys_problems_cli_base_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final keysPath = '${dir.path}/keys/key.atKeys';
    final err = _Captured();
    var built = 0;

    await expectLater(
        IOOverrides.runZoned(
            () => CLIBase.fromCommandLineArgs([
                  '-a', atSign, //
                  '-k', keysPath,
                  '-s', '${dir.path}/storage',
                  '-r', '127.0.0.1:$unreachablePort',
                  '--max-connect-attempts', '1',
                  '--never-sync',
                ], parser: CLIBase.createArgsParser(namespace: 'keys_test'),
                    lookUps: (
                        {required String atSign,
                        required AtRootDomain rootDomain,
                        required AtAuthenticator? authenticator,
                        SecondaryAddressFinder? secondaryAddressFinder}) {
                  built++;
                  throw StateError('no connection was expected');
                }),
            stderr: () => err),
        throwsA(isA<AtKeysUnusableException>()
            .having((e) => e.cause, 'cause', AtKeysUnusableCause.absent)
            .having((e) => e.source, 'source', keysPath)));
    final lines = err.text
        .replaceAll(RegExp(r'\x1b\[[0-9;]*[A-Za-z]'), '')
        .replaceAll('\r', '\n')
        .split('\n');
    expect(lines.where((l) => l == 'No keys for $atSign at $keysPath.'),
        hasLength(1));
    expect(built, 0, reason: 'no connection is built');
  });

  test('A network failure still says to try again', () async {
    await FileAtKeysIo(filePath: (_) => defaultKeyfile())
        .write(atSign, randomLegacyKeys());
    atServerPort = unreachablePort;

    final run = await atActivate(
        ['otp', '-a', atSign, '-r', atDirectoryRoot(), '--mca', '1']);
    final text = run.stderr.join('\n');

    expect(text, contains('Failed to connect within 1 attempts'));
    expect(text, contains('Please try again'));
    expect(text, isNot(contains(footer)));
    expect(run.exitCode, 1);
  }, timeout: const Timeout(Duration(minutes: 2)));
}

/// Collects what is written to it, for a test to read.
class _Captured implements Stdout {
  final List<String> written = [];

  String get text => written.join();

  @override
  void write(Object? object) => written.add('$object');

  @override
  void writeln([Object? object = '']) => written.add('$object\n');

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
