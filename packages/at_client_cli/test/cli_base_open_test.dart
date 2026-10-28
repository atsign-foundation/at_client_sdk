import 'dart:io';

import 'package:at_auth/at_auth.dart'
    show
        AtKeys,
        CryptographicMaterial,
        CryptographicMaterialAlgorithm,
        CryptographicMaterialRole,
        CryptographicMaterialStatus;
import 'package:at_client_cli/at_client_cli.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'keyfile_helpers.dart';
import 'lifecycle_rig.dart';

/// `CLIBase.fromCommandLineArgs` tells a refusal from an outage.
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
  late int lookUpsBuilt;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('cli_base_open_');
    keysPath = '${dir.path}/keys/key.atKeys';
    storageDir = '${dir.path}/storage';
    port = await refusedPort();
    lookUpsBuilt = 0;
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
        Map<String, dynamic> clientConfig = const {},
      }) {
        lookUpsBuilt++;
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

  test('A keyfile still holding only its enrollment request says so', () async {
    const atSign = '@clirequestonly';
    final keyPair = randomLegacyKeys().authenticationKeyPairFor(null)!;
    final request = AtKeys(atsign: Atsign(atSign));
    for (final (role, key) in [
      (CryptographicMaterialRole.privateAuthentication, keyPair.privateKey),
      (CryptographicMaterialRole.publicAuthentication, keyPair.publicKey),
    ]) {
      request.addKey(CryptographicMaterial(
          keyId: 'auth:rsa2048:1',
          enrollmentId: 'e-pending',
          role: role,
          algorithm: CryptographicMaterialAlgorithm.rsa2048,
          bytes: AtBytes.fromString(key),
          createdAt: DateTime.now().toUtc(),
          status: CryptographicMaterialStatus.pending));
    }
    expect(request.pendingEnrollmentIds, ['e-pending'],
        reason: 'the precondition: the keyfile holds only the request');
    await FileAtKeysIo(filePath: (_) => keysPath).write(atSign, request);

    await expectLater(
        open(atSign, answering(() async => true)),
        throwsA(isA<AtEnrollmentPendingException>()
            .having((e) => e.pendingEnrollmentIds, 'pending', ['e-pending'])));
    expect(AtClientImpl.holdsLiveClient(atSign), isFalse,
        reason: 'no client is opened');
    expect(lookUpsBuilt, 0, reason: 'no atServer is asked');
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
