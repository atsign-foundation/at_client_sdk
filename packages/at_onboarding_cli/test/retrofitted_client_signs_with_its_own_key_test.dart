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

/// **The signer and the enrolment id must come from the same place.**
///
/// A client whose posture asks for a stronger authentication key than its
/// enrolment holds retrofits itself during `AtClientImpl._init`: it comes up on
/// a NEW enrolment id, with ML-DSA-65 authentication material written into the
/// keyfile beside the original enrolment's untouched flat RSA fields, and its
/// own `AtChops` rebuilt to sign with the new keypair.
///
/// `_initAtClient` then adopts that client's lookup and stamps three things on
/// it. Two came from the client — the enrolment id and the signing algorithm —
/// and the third, the signer, came from the caller: `authenticate()` passes
/// `atAuth.atChops`, built moments earlier for the enrolment the keyfile's flat
/// fields name. Nothing reconciles them, so the lookup declares `mldsa65` while
/// holding an RSA-2048 keypair.
///
/// ⛔ **`authenticatorFor` will not save it, because it takes only the
/// ALGORITHM from the keyfile when a signer is injected** (at_auth's
/// `_pkam`, the `injectedChops != null` branch). Measured with three arms over
/// one keyfile, varying only the enrolment id:
///
/// | injected RSA signer, the enrolment it belongs to | authenticates |
/// | injected RSA signer, the retrofitted enrolment | **`this PKAM key is 1217 bytes, and an ML-DSA-65 secret key is 4032`** |
/// | no injected signer, the retrofitted enrolment | authenticates |
///
/// (The byte count is the encoded RSA-2048 private key's and moves by a byte or
/// two between keypairs — 1217 to 1219 here, 1218 in the field report. It is the
/// order of magnitude that identifies the key, which is why at_chops says so in
/// the message rather than leaving a reader to recognise the number.)
///
/// The third arm is the one that says where the fault is: the keyfile resolves
/// this correctly on its own, so it is the injection of a signer from the other
/// enrolment that breaks it, not the retrofit and not the key material.
///
/// **What that costs in the field.** `at_activate list` on a retrofitted
/// keyfile prints "Connected" — at_auth authenticated on its own connection,
/// with a signer and an algorithm that agree — and then fails the verb, because
/// the verb runs over the client's rebuilt lookup, which authenticates lazily
/// through the mismatched pair. A legacy atSign upgrades by running a client at
/// a newer posture, so this is the migration path itself.
///
/// ⚠️ **The rig reaches the post-retrofit state through the client cache
/// rather than by retrofitting.** A real retrofit needs an atServer to create
/// the new enrolment on. What `_initAtClient` can observe is only
/// `atClientManager.atClient`, and the state this test hands it — a client
/// running as `retrofittedId` with the ML-DSA signer for it, while the caller's
/// `atChops` is the flat enrolment's RSA one — is byte-for-byte the state a
/// retrofit leaves behind. The route by which the client came to be that way is
/// not an input to the code under test.
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

void main() {
  AtSignLogger.root_level = 'SHOUT';

  setUpAll(() => registerFallbackValue(_FakeAtAuthRequest()));

  const atSign = '@retrofitted_cli';
  const namespace = 'unit_test';
  const flatEnrollmentId = 'legacy-flat-enrollment';
  const retrofittedId = 'retrofitted-enrollment';

  late String keysFilePath;
  late AtChops flatRsaChops;
  late AtClient retrofittedClient;

  setUp(() async {
    AtClientImpl.atClientInstanceMap.clear();

    keysFilePath =
        '${Directory.systemTemp.createTempSync('retrofit_keys').path}'
        '/${atSign}_key.atKeys';
    addTearDown(() => File(keysFilePath).parent.deleteSync(recursive: true));

    // The keyfile a retrofit leaves behind: the capped legacy enrolment's RSA
    // keypair still in the flat fields, byte-identical and statusless, and the
    // live enrolment's ML-DSA-65 material in the typed section. Both halves
    // are real keys, because the assertion below is a signature that either
    // gets produced or does not.
    final rsaPair = AtChopsUtil.generateAtPkamKeyPair();
    final encryptionPair = AtChopsUtil.generateAtEncryptionKeyPair();
    final mlDsaPair = await MlDsa65KeyPair.generate();
    final now = DateTime.now().toUtc();
    final keys = AtKeys()
      ..enrollmentId = flatEnrollmentId
      ..apkamPublicKey = AtBytes.fromString(rsaPair.atPublicKey.publicKey)
      ..apkamPrivateKey = AtBytes.fromString(rsaPair.atPrivateKey.privateKey)
      // The flat encryption pair and the self-encryption key are what makes
      // this a whole keyfile: `FileAtKeysIo` self-encrypts the legacy fields on
      // write and refuses without the key, and the RSA signer below is built
      // through `toAtChops()`, which reads all of them.
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

    // What at_auth hands `_initAtClient`: the signer for the FLAT enrolment,
    // which is the one it authenticated as. Built through the same resolver
    // at_auth uses, so this is not a hand-assembled approximation of it.
    flatRsaChops = (await io.read(atSign)).authenticationFor(null).chops;

    // The client, already running as the retrofitted enrolment with the signer
    // that enrolment owns — `_createAtChops`'s own expression, so the rig
    // cannot drift from what the retrofit actually installs.
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

  /// A service whose `authenticate()` succeeds without a server, handing over
  /// [flatRsaChops] as at_auth would.
  AtOnboardingServiceImpl serviceAuthenticatingAsFlatEnrollment() {
    final atAuth = _MockAtAuth();
    when(() => atAuth.progressStream).thenAnswer((_) => const Stream.empty());
    when(() => atAuth.atChops).thenReturn(flatRsaChops);
    when(() => atAuth.authenticate(any()))
        .thenAnswer((_) async => AtAuthResponse(atSign)
          ..isSuccessful = true
          // ⚠️ In the field at_auth reports the FLAT id here — a retrofit
          // deliberately leaves the keyfile's own `enrollmentId` at the capped
          // legacy enrolment — and the client moves past it inside `create`.
          // The rig names the retrofitted id instead because that is the
          // client-cache key, and reaching the same state through the cache is
          // what lets this run without an atServer. Neither route changes what
          // `_initAtClient` sees, which is the client and the caller's chops.
          ..atAuthKeys = (AtKeys()..enrollmentId = retrofittedId));

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

    // The two halves that already came from the client, asserted so that a
    // regression which fixed the mismatch by weakening the DECLARATION —
    // stamping rsa2048 over an ML-DSA enrolment — would go red here rather
    // than turn the assertion below green for the wrong reason.
    expect(adopted.enrollmentId, retrofittedId);
    expect(adopted.signingAlgoType, SigningAlgoType.mldsa65);

    final exchange = _OfflineExchange(atSign);
    // The authenticator is the seam `_initAtClient` installs on; `AtLookUp`
    // itself does not declare it, because that interface is frozen for the
    // mocks that implement it.
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
