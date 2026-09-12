// The PQ enrolment surface is @experimental while it matures; this test drives
// it deliberately.
// ignore_for_file: experimental_member_use, deprecated_member_use

import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/at_auth_io.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_utils/at_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockAtAuth extends Mock implements AtAuth {}

class _FakeAtAuthRequest extends Fake implements AtAuthRequest {}

/// Answers a challenge-response without an atServer.
///
/// The `from:` reply has to be well formed — at_auth refuses to sign a
/// challenge that does not carry a uuid and this atSign — or every arm fails
/// for that reason instead of the one under test.
class _OfflineExchange implements AtCommandExecutor {
  _OfflineExchange(this.atSign);

  final String atSign;
  final List<String> sent = [];

  @override
  Future<String> sendSync(String command,
      {int? maxWaitMilliSeconds, int? transientWaitTimeMillis}) async {
    sent.add(command.trim());
    if (command.startsWith('from:')) {
      return 'data:_6c9f8b1e-6f7a-4d3b-9a1a-2f5e7c8d9012$atSign'
          ':b2d4a6c8-1e3f-4a5b-8c7d-9e0f1a2b3c4d';
    }
    return 'data:success';
  }
}

/// The signer stamped on the adopted lookup has to belong to the enrolment
/// that lookup declares, whatever enrolment the caller authenticated as.
void main() {
  AtSignLogger.root_level = 'SHOUT';

  setUpAll(() => registerFallbackValue(_FakeAtAuthRequest()));

  const atSign = '@retrofitted_cli';
  const namespace = 'unit_test';
  const flatEnrollmentId = 'legacy-flat-enrollment';
  const retrofittedId = 'retrofitted-enrollment';

  late String keysFilePath;
  late AtClient retrofittedClient;

  setUp(() async {
    AtClientImpl.atClientInstanceMap.clear();

    keysFilePath =
        '${Directory.systemTemp.createTempSync('retrofit_keys').path}'
        '/${atSign}_key.atKeys';
    addTearDown(() => File(keysFilePath).parent.deleteSync(recursive: true));

    // The keyfile a retrofit leaves behind: the legacy enrolment's RSA keypair
    // in the flat fields, the live enrolment's ML-DSA-65 material in the typed
    // section. Both halves are real keys, since the assertion below is a
    // signature that either gets produced or does not.
    final rsaPair = AtChopsUtil.generateAtPkamKeyPair();
    final encryptionPair = AtChopsUtil.generateAtEncryptionKeyPair();
    final mlDsaPair = await MlDsa65KeyPair.generate();
    final now = DateTime.now().toUtc();
    final keys = AtKeys()
      ..enrollmentId = flatEnrollmentId
      ..apkamPublicKey = AtBytes.fromString(rsaPair.atPublicKey.publicKey)
      ..apkamPrivateKey = AtBytes.fromString(rsaPair.atPrivateKey.privateKey)
      // NOTE: `FileAtKeysIo` self-encrypts the legacy fields on write and
      // refuses without the self-encryption key.
      ..defaultEncryptionPublicKey =
          AtBytes.fromString(encryptionPair.atPublicKey.publicKey)
      ..defaultEncryptionPrivateKey =
          AtBytes.fromString(encryptionPair.atPrivateKey.privateKey)
      ..defaultSelfEncryptionKey = AtBytes.fromString(AESKey.generate(32).key)
      ..addKey(CryptographicMaterial(
        keyId: 'auth:mldsa65:1',
        enrollmentId: retrofittedId,
        role: CryptographicMaterialRole.privateAuthentication,
        algorithm: CryptographicMaterialAlgorithm.mlDsa65,
        bytes: AtBytes.fromString(mlDsaPair.atPrivateKey.privateKey),
        createdAt: now,
      ))
      ..addKey(CryptographicMaterial(
        keyId: 'auth:mldsa65:1',
        enrollmentId: retrofittedId,
        role: CryptographicMaterialRole.publicAuthentication,
        algorithm: CryptographicMaterialAlgorithm.mlDsa65,
        bytes: AtBytes.fromString(mlDsaPair.atPublicKey.publicKey),
        createdAt: now,
      ));
    final io = FileAtKeysIo(filePath: (_) => keysFilePath);
    await io.write(atSign, keys);

    // The client as a retrofit leaves it: running as the retrofitted
    // enrolment, with the signer that enrolment owns.
    final retrofittedChops =
        (await io.read(atSign)).authenticationFor(retrofittedId).chops;
    retrofittedClient = await AtClientImpl.create(
      atSign,
      namespace,
      AtClientPreference(posture: PqPosture.legacy)
        ..hiveStoragePath = 'test/storage/hive/retrofitted'
        ..commitLogPath = 'test/storage/hive/retrofitted/commit',
      atChops: retrofittedChops,
      atKeysIo: FileAtKeysIo(filePath: (_) => keysFilePath),
      enrollmentId: retrofittedId,
    );
  });

  tearDown(() async {
    await retrofittedClient.getRemoteSecondary()?.atLookUp.close();
    AtClientImpl.atClientInstanceMap.clear();
  });

  /// A service whose `authenticate()` succeeds without a server, reporting the
  /// flat enrolment in the response as at_auth would.
  AtOnboardingServiceImpl serviceAuthenticatingAsFlatEnrollment() {
    final atAuth = _MockAtAuth();
    when(() => atAuth.progressStream).thenAnswer((_) => const Stream.empty());
    when(() => atAuth.authenticate(any()))
        .thenAnswer((_) async => AtAuthResponse(atSign)
          ..isSuccessful = true
          // NOTE: at_auth reports the FLAT id on the session; the rig names
          // the retrofitted id because that is the client-cache key, which is
          // what lets it reach the post-retrofit state without an atServer.
          // `_initAtClient` sees only the client and the caller's chops either
          // way. The session's source is the keyfile on disk, which is what
          // the service reads the keys back through.
          ..session = AtAuthSession(
            atSign: atSign,
            rootDomain: AtRootDomain.atsignDomain,
            enrollmentId: retrofittedId,
            atKeysIo: FileAtKeysIo(filePath: (_) => keysFilePath),
          ));

    return AtOnboardingServiceImpl(
        atSign,
        AtOnboardingPreference(posture: PqPosture.legacy)
          ..atKeysFilePath = keysFilePath
          ..namespace = namespace
          ..hiveStoragePath = 'test/storage/hive/retrofitted'
          ..commitLogPath = 'test/storage/hive/retrofitted/commit')
      ..atAuth = atAuth;
  }

  test('the adopted lookup authenticates as the enrolment it declares',
      () async {
    final service = serviceAuthenticatingAsFlatEnrollment();
    expect(await service.authenticate(), isTrue);

    final adopted = service.atLookUp!;
    expect(
        identical(
            adopted,
            AtClientManager.getInstance()
                .atClient
                .getRemoteSecondary()!
                .atLookUp),
        isTrue,
        reason: 'the flow under test is the one that adopts the client\'s own '
            'lookup; if this service built its own, everything below is about '
            'the wrong object');

    // NOTE: these two go red if a fix weakens the DECLARATION to rsa2048
    // instead of correcting the signer, which would otherwise turn the
    // assertion below green for the wrong reason.
    expect(adopted.enrollmentId, retrofittedId);
    expect(adopted.signingAlgoType, SigningAlgoType.mldsa65);

    final exchange = _OfflineExchange(atSign);
    // NOTE: `AtLookUp` does not declare the authenticator — that interface is
    // frozen for the mocks implementing it — so the seam `_initAtClient`
    // installs on is reached through `AtLookupMuxable`.
    final authenticator = (adopted as AtLookupMuxable).authenticator!;
    await expectLater(authenticator(exchange), completion(isTrue),
        reason: 'the lookup declares mldsa65 for the retrofitted enrolment, so '
            'the signer installed beside it has to be that enrolment\'s '
            'ML-DSA keypair. Handing it the flat enrolment\'s RSA keypair — '
            'which is what at_auth resolved before the client moved — reaches '
            'at_chops as "this PKAM key is ~1218 bytes, and an ML-DSA-65 '
            'secret key is 4032", and no verb this client runs can '
            'authenticate');

    expect(exchange.sent.where((c) => c.startsWith('pkam:')), isNotEmpty,
        reason: 'a green that never reached the pkam: verb would mean the '
            'authenticator short-circuited rather than signed');
  });
}
