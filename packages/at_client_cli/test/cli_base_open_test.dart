import 'dart:io';

import 'package:at_client_cli/at_client_cli.dart';
import 'package:at_commons/at_builders.dart' show VerbBuilder;
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'keyfile_helpers.dart';
import 'lifecycle_rig.dart';

/// `CLIBase.fromCommandLineArgs` tells a refusal from an outage, and resumes
/// a keyfile that holds only an enrollment request.
///
/// Catalogue: features/at_client_cli/cli_base_open.feature
///
/// The atServer is a mocked lookup that every connection CLIBase builds is
/// handed, so what it answers to the PKAM attempt is the test's to choose;
/// the atDirectory is a loopback port nothing listens on.
void main() {
  const namespace = 'cli_test';
  late Directory dir;
  late String keysPath;
  late String storageDir;
  late int port;

  setUpAll(() => registerFallbackValue(_FakeVerbBuilder()));

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('cli_base_open_');
    keysPath = '${dir.path}/keys/key.atKeys';
    storageDir = '${dir.path}/storage';
    port = await refusedPort();
  });

  tearDown(() async {
    for (final client
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await client.stop();
    }
    AtClientImpl.atClientInstanceMap.clear();
    dir.deleteSync(recursive: true);
  });

  Future<void> writeKeys(String atSign) =>
      FileAtKeysIo(filePath: (_) => keysPath).write(atSign, randomLegacyKeys());

  /// Every connection answers its PKAM attempt with [onPkam].
  AtLookUpFactory answering(Future<bool> Function() onPkam) => ({
        required String atSign,
        required AtRootDomain rootDomain,
        required AtAuthenticator? authenticator,
        SecondaryAddressFinder? secondaryAddressFinder,
      }) {
        final lookUp = lookUpAnswering(onPkam);
        when(() => lookUp.stopNotifications()).thenAnswer((_) async {});
        return lookUp;
      };

  Future<CLIBase> open(String atSign, AtLookUpFactory lookUps) =>
      CLIBase.fromCommandLineArgs([
        '-a', atSign, //
        '-k', keysPath,
        '-s', storageDir,
        '-r', '127.0.0.1:$port',
        '--max-connect-attempts', '1',
        '--never-sync',
      ],
          parser: CLIBase.createArgsParser(namespace: namespace),
          lookUps: lookUps);

  test('A refused open throws, naming the cause', () async {
    const atSign = '@clirefused';
    await writeKeys(atSign);

    await expectLater(
        open(
            atSign,
            answering(() async =>
                throw UnAuthenticatedException('Failed connecting to $atSign. '
                    'error:AT0027:Apkam Access Revoked'))),
        throwsA(isA<AtCredentialRefusedException>()
            .having((e) => e.atSign, 'atSign', atSign)
            .having((e) => e.state.cause, 'cause', AtConnectionCause.revoked)
            .having((e) => e.message, 'message', contains(atSign))));
    expect(AtClientImpl.holdsLiveClient(atSign), isFalse,
        reason: 'no client is left open');
  });

  test(
      'A refusal throws the same way after the atSign has been online on the '
      'device', () async {
    const atSign = '@clirefusedlater';
    await writeKeys(atSign);
    final preference = AtClientPreference()
      ..namespace = namespace
      ..rootDomain = '127.0.0.1'
      ..rootPort = port;
    final first = await Atsign(atSign).open(
        keys: CliKeys.fileFor(atSign, path: keysPath),
        preference: preference,
        storage:
            CliKeys.storageFor(atSign, program: namespace, path: storageDir),
        atLookUp: lookUpAnswering(() async => true),
        lookUps: secureSocketLookUps(),
        secondaryAddressFinder:
            CacheableSecondaryAddressFinder(preference.rootDomain, port));
    expect(first.connection.current.isOnline, isTrue,
        reason: 'the precondition: this device has held the atSign online');
    await first.stop();

    await expectLater(
        open(
            atSign,
            answering(() async =>
                throw UnAuthenticatedException('Failed connecting to $atSign. '
                    'error:AT0027:Apkam Access Revoked'))),
        throwsA(isA<AtCredentialRefusedException>()
            .having((e) => e.state.cause, 'cause', AtConnectionCause.revoked)));
    expect(AtClientImpl.holdsLiveClient(atSign), isFalse,
        reason: 'the client it opened is stopped');
  });

  test('An enrollment awaiting approval says so', () async {
    const atSign = '@clipending';
    await writeKeys(atSign);

    await expectLater(
        open(
            atSign,
            answering(() async =>
                throw UnAuthenticatedException('Failed connecting to $atSign. '
                    'error:AT0026:enrollment_id: e-1 is pending'))),
        throwsA(isA<AtCredentialRefusedException>()
            .having((e) => e.state.cause, 'cause',
                AtConnectionCause.enrollmentNotApproved)
            .having((e) => e.message, 'message',
                endsWith('; the enrollment awaits approval'))));
  });

  test('An atServer not reached is an outage, not a refusal', () async {
    const atSign = '@clioutage';
    await writeKeys(atSign);

    await expectLater(
        open(
            atSign,
            answering(() async => throw SecondaryConnectException(
                'could not connect to the atServer'))),
        throwsA(isA<SecondaryServerConnectivityException>()));
    expect(AtClientImpl.holdsLiveClient(atSign), isFalse,
        reason: 'no client is left open');
  });

  group('Given a keyfile holding only its enrollment request', () {
    const atSign = approvingAtSign;
    late List<String> wrapped;

    Future<List<String>> pending() => pendingIn(keysPath, atSign);

    Future<void> submitRequest() async {
      if (File(keysPath).existsSync()) File(keysPath).deleteSync();
      wrapped = await fileRequest(
          keysPath: keysPath, rootPort: port, namespace: namespace);
      expect(await pending(), [approvedEnrollmentId],
          reason: 'the precondition: the keyfile holds only the request');
    }

    /// CLIBase over [server], polling for approval every 10ms, with what it
    /// writes to stderr in [stderrText].
    Future<CLIBase> openOver(MockAtLookupImpl server, List<String> stderrText) {
      when(() => server.stopNotifications()).thenAnswer((_) async {});
      return IOOverrides.runZoned(
          () => CLIBase.fromCommandLineArgs([
                '-a', atSign, //
                '-k', keysPath,
                '-s', storageDir,
                '-r', '127.0.0.1:$port',
                '--max-connect-attempts', '1',
                '--never-sync',
              ],
                  parser: CLIBase.createArgsParser(namespace: namespace),
                  lookUps: (
                          {required String atSign,
                          required AtRootDomain rootDomain,
                          required AtAuthenticator? authenticator,
                          SecondaryAddressFinder? secondaryAddressFinder}) =>
                      server,
                  approvalRetryInterval: const Duration(milliseconds: 10)),
          stderr: () => _Captured(stderrText));
    }

    test('A keyfile still holding only its enrollment request is resumed',
        () async {
      await submitRequest();
      final server = approvingAtServer(
          decide: (_) async => true, wrapped: wrapped);
      final stderrText = <String>[];

      final cli = await openOver(server.lookUp, stderrText);

      expect(stderrText.join(),
          contains('Waiting for approval of enrollment $approvedEnrollmentId'));
      expect(cli.atClient.enrollmentId, approvedEnrollmentId);
      expect(cli.atClient.connection.current.isOnline, isTrue);
      expect(server.sent.where((c) => c.startsWith('enroll:')), isEmpty,
          reason: 'the wait resumed from the keyfile; no second request');
      expect(
          (await FileAtKeysIo(filePath: (_) => keysPath).read(atSign))
              .enrollmentToAuthenticateAs(),
          approvedEnrollmentId);
    });

    test(
        'A denied or expired request ends the program with that reason, and '
        'its keys go', () async {
      for (final (code, reason) in [
        ('AT0025', 'Apkam Auth Denied'),
        ('AT0028', 'enrollment expired'),
      ]) {
        await submitRequest();
        final server = approvingAtServer(
            decide: (_) async => throw UnAuthenticatedException(
                'Failed connecting to $atSign. error:$code:$reason'),
            wrapped: wrapped);

        await expectLater(openOver(server.lookUp, []),
            throwsA(isA<AtEnrollmentException>()),
            reason: code);
        expect(await pending(), isEmpty, reason: code);
        expect(AtClientImpl.holdsLiveClient(atSign), isFalse, reason: code);
      }
    });

    test(
        'An atServer not reached for the retry budget ends the program, '
        'keeping the request', () async {
      await submitRequest();
      final server = approvingAtServer(
          decide: (_) async =>
              throw SecondaryConnectException('could not connect'),
          wrapped: wrapped);

      await expectLater(openOver(server.lookUp, []),
          throwsA(isA<SecondaryConnectException>()));
      expect(await pending(), [approvedEnrollmentId]);
      expect(AtClientImpl.holdsLiveClient(atSign), isFalse);
    });
  });

  test('An atSign the atDirectory has no atServer for is named as such',
      () async {
    const atSign = '@clinoserver';
    await writeKeys(atSign);

    await expectLater(
        open(
            atSign,
            answering(() async => throw SecondaryNotFoundException(
                'No entry in atDirectory for clinoserver'))),
        throwsA(isA<SecondaryNotFoundException>().having((e) => e.message,
            'message', contains('$atSign is not in the atDirectory'))));
    expect(AtClientImpl.holdsLiveClient(atSign), isFalse,
        reason: 'no client is left open');
  });
}

/// Collects what is written to it, for a test to read.
class _Captured implements Stdout {
  _Captured(this.text);

  final List<String> text;

  @override
  void write(Object? object) => text.add('$object');

  @override
  void writeln([Object? object = '']) => text.add('$object\n');

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeVerbBuilder extends Fake implements VerbBuilder {}
