import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/src/at_auth_impl.dart';
import 'package:at_auth/src/auth/pkam_authenticator.dart';
import 'package:at_auth/at_auth_io.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_server_status/at_server_status.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtLookUp extends Mock implements AtLookupImpl {}

class MockAtEnrollment extends Mock implements AtEnrollment {}

class MockPkamAuthenticator extends Mock implements PkamAuthenticator {}

class MockAtServerStatus extends Mock implements AtServerStatus {}

class FakeVerbBuilder extends Fake implements VerbBuilder {}

class FakeAtLookUp extends Fake implements AtLookupImpl {}

class FakeEnrollmentRequest extends Fake implements EnrollmentRequest {}

class FakeSecondaryAddressFinder extends Fake
    implements CacheableSecondaryAddressFinder {
  @override
  Future<SecondaryAddress> findSecondary(String atSign,
          {Duration? timeout}) async =>
      SecondaryAddress('abcd', 123);
}

/// ON-1: a CRAM activation can be PQ-native.
///
/// The APKAM is an ML-DSA-65 keypair filed as typed material under the
/// enrollment id the atServer assigns — the flat fields stay empty, so
/// `AtAuthImpl.authenticate` resolves it through the typed path and signs
/// ML-DSA with no caller-supplied algorithm anywhere. Legacy material is still
/// cut and published by default, because whether this atSign will ever need to
/// talk to a legacy peer is decided by the apps that adopt it.
void main() {
  const atSign = '@bob🛠';
  const enrollmentId = 'pq-first-1';
  const cramSecret = 'cram123';

  late AtAuthImpl atAuth;
  late MockAtLookUp mockAtLookUp;
  late MockAtEnrollment mockAtEnrollment;
  late Directory tempDir;
  late FileAtKeysIo keysIo;

  setUp(() {
    registerFallbackValue(FakeVerbBuilder());
    registerFallbackValue(FakeEnrollmentRequest());
    registerFallbackValue(FakeAtLookUp());
    registerFallbackValue(SigningAlgoType.rsa2048);

    tempDir = Directory.systemTemp.createTempSync('pq_onboard_test');
    keysIo = FileAtKeysIo(filePath: (a) => '${tempDir.path}/${a}_key.atKeys');

    mockAtLookUp = MockAtLookUp();
    mockAtEnrollment = MockAtEnrollment();
    final mockPkam = MockPkamAuthenticator();
    final mockStatus = MockAtServerStatus();

    when(() => mockStatus.get(any())).thenAnswer((_) async => AtStatus(
        serverStatus: ServerStatus.teapot,
        rootStatus: RootStatus.found,
        atSignStatus: AtSignStatus.teapot));
    when(() => mockAtLookUp.cramAuthenticate(cramSecret))
        .thenAnswer((_) async => true);
    when(() => mockAtLookUp.executeVerb(any()))
        .thenAnswer((_) async => 'data:2');
    when(() => mockAtLookUp.close()).thenAnswer((_) async => {});
    when(() => mockPkam.authenticate(any(), any(),
            enrollmentId: any(named: 'enrollmentId')))
        .thenAnswer((_) async => true);
    when(() => mockAtEnrollment.submit(any(), any())).thenAnswer((_) async =>
        AtEnrollmentResponse(enrollmentId, EnrollmentStatus.approved));

    atAuth = AtAuthImpl(
        atLookUp: mockAtLookUp,
        pkamAuthenticator: mockPkam,
        atEnrollment: mockAtEnrollment,
        atServerStatus: mockStatus)
      ..secondaryAddressFinder = FakeSecondaryAddressFinder()
      ..probeSocket = ((host, port) async {});
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  AtOnboardingRequest requestFor(
          {SigningAlgoType? signingAlgo,
          bool? mintLegacyMaterial,
          ({
            SigningAlgoType algorithm,
            String publicKey,
            String privateKey
          })? advertisedSigningKey}) =>
      AtOnboardingRequest(atSign)
        ..atKeysIo = keysIo
        ..appName = 'wavi'
        ..deviceName = 'iphone'
        ..mintLegacyMaterial = mintLegacyMaterial
        ..advertisedSigningKey = advertisedSigningKey
        ..signingAlgoType = signingAlgo ?? SigningAlgoType.rsa2048;

  /// The request the onboard actually submitted.
  FirstEnrollmentRequest submittedRequest() =>
      verify(() => mockAtEnrollment.submit(captureAny(), any())).captured.single
          as FirstEnrollmentRequest;

  group('PQ-native activation', () {
    test(
        'the APKAM is ML-DSA-65, typed under the enrollment id, and the flat '
        'fields stay empty', () async {
      final response = await atAuth.onboard(
          requestFor(signingAlgo: SigningAlgoType.mldsa65), cramSecret);
      expect(response.isSuccessful, true);

      final keys = await keysIo.read(atSign);
      expect(keys.apkamPublicKey, isNull,
          reason: 'a reader calling toAtChops() must fail loudly rather than '
              'sign an ML-DSA key with the RSA routine');
      expect(keys.apkamPrivateKey, isNull);

      expect(keys.signingAlgorithmForEnrollment(enrollmentId),
          SigningAlgoType.mldsa65,
          reason: 'this is what AtAuthImpl.authenticate reads to pick the '
              'signing routine on every later connection');
      final signing = keys.getKey(enrollmentId, 'auth:mldsa65:1',
          CryptographicMaterialRole.privateAuthentication);
      final verification = keys.getKey(enrollmentId, 'auth:mldsa65:1',
          CryptographicMaterialRole.publicAuthentication);
      expect(signing, isNotNull);
      expect(verification, isNotNull);
      // A genuine raw ML-DSA-65 keypair, not a placeholder.
      expect(base64Decode(verification!.bytes.toString()).length, 1952);
      expect(base64Decode(signing!.bytes.toString()).length, 4032);
    });

    test('the enrollment request declares mldsa65 and advertises that key',
        () async {
      await atAuth.onboard(
          requestFor(signingAlgo: SigningAlgoType.mldsa65), cramSecret);

      final request = submittedRequest();
      expect(request.signingAlgo, SigningAlgoType.mldsa65,
          reason: 'the atServer verifies this enrollment\'s PKAM signatures '
              'with the algorithm the record names');
      expect(base64Decode(request.apkamPublicKey!).length, 1952);

      final keys = await keysIo.read(atSign);
      expect(
          request.apkamPublicKey,
          keys
              .getKey(enrollmentId, 'auth:mldsa65:1',
                  CryptographicMaterialRole.publicAuthentication)!
              .bytes
              .toString(),
          reason: 'the key advertised to the atServer and the key kept in the '
              'keyfile must be the same one, or the atSign can never '
              'authenticate');
    });

    test('legacy material is minted and publickey published, by DEFAULT',
        () async {
      await atAuth.onboard(
          requestFor(signingAlgo: SigningAlgoType.mldsa65), cramSecret);

      final keys = await keysIo.read(atSign);
      expect(keys.defaultEncryptionPublicKey, isNotNull);
      expect(keys.defaultEncryptionPrivateKey, isNotNull);
      expect(keys.defaultSelfEncryptionKey, isNotNull);
      expect(keys.apkamSymmetricKey, isNotNull);

      final published = verify(() => mockAtLookUp.executeVerb(captureAny()))
          .captured
          .whereType<UpdateVerbBuilder>()
          .where((b) => b.atKey.key == 'publickey');
      expect(published, isNotEmpty,
          reason: 'a legacy peer must be able to send to a brand-new atSign '
              'out of the box — decisions 37');
      expect(published.single.value.toString(),
          keys.defaultEncryptionPublicKey!.toString());
    });
  });

  /// UC-G3.1's third door.
  ///
  /// Three paths create an enrollment holding a data signing keypair, and
  /// at_auth files the private half at three separate points. Two were pinned
  /// — `enrollment_test.dart` and `at_self_enrollment_test.dart` each carry
  /// "the signing key is FILED, not merely advertised". This one, the
  /// activation, was driven by no test in any pack until 2026-08-31.
  ///
  /// ⚠️ **`packages/at_client/test/pq_native_onboard_test.dart` looks like
  /// coverage and is not**: it asserts the activation REQUEST carries the key,
  /// which is a claim about the request object. What reaches the keyfile is
  /// whatever at_auth copies out of it after the atServer answers, and that is
  /// a different statement — an enrollment whose `_apsk` names a key its
  /// keyfile does not hold signs with something else entirely, and the next
  /// start finds the in-use algorithm missing, mints a SECOND keypair and
  /// republishes, orphaning the key the record already named.
  group('the activation files the signing key it advertises', () {
    ({SigningAlgoType algorithm, String publicKey, String privateKey})
        advertised(SigningAlgoType algorithm) => (
              algorithm: algorithm,
              publicKey: base64Encode(utf8.encode('advertised-public')),
              privateKey: base64Encode(utf8.encode('advertised-private')),
            );

    test('the PRIVATE half reaches the keyfile, under the enrollment id',
        () async {
      final key = advertised(SigningAlgoType.rsa2048);
      await atAuth.onboard(
          requestFor(
              signingAlgo: SigningAlgoType.mldsa65, advertisedSigningKey: key),
          cramSecret);

      final held = (await keysIo.read(atSign)).signingKeysFor(enrollmentId);
      expect(held, hasLength(1),
          reason: 'filed, and filed where the reader looks. `enrollmentId` is '
              'the id the mocked atServer RETURNED and appears nowhere in the '
              'request, so a non-empty answer here is also what proves the '
              'filing used the assigned id rather than anything the caller '
              'supplied — and that it went into the enrollment\'s container '
              'rather than the atSign\'s, which `signingKeysFor` never reads');
      expect(held.single.privateKey, key.privateKey,
          reason: 'the PRIVATE half is the whole point — a public half alone '
              'is an advertisement of a key this atSign cannot sign with');
      expect(held.single.publicKey, key.publicKey);
      expect(held.single.algorithm, SigningAlgoType.rsa2048,
          reason: 'the algorithm travels with the key rather than following '
              'the APKAM\'s, which is mldsa65 here — an activation at pqReady '
              'authenticates post-quantum and signs data with rsa2048, and '
              'the two are read back separately');
    });

    test('without one, nothing is filed', () async {
      await atAuth.onboard(requestFor(), cramSecret);

      expect((await keysIo.read(atSign)).signingKeysFor(enrollmentId), isEmpty,
          reason: 'the control. Without it the two rows above are satisfied '
              'by a path that files something unconditionally, and nothing '
              'would attribute the filing to the advertised key');
    });
  });

  group('the mintLegacyMaterial opt-out', () {
    test('false mints no legacy material and publishes no publickey', () async {
      await atAuth.onboard(
          requestFor(
              signingAlgo: SigningAlgoType.mldsa65, mintLegacyMaterial: false),
          cramSecret);

      final keys = await keysIo.read(atSign);
      expect(keys.defaultEncryptionPublicKey, isNull);
      expect(keys.defaultEncryptionPrivateKey, isNull);
      expect(keys.defaultSelfEncryptionKey, isNull,
          reason: 'with no legacy flat fields to protect there is nothing for '
              'it to encrypt');
      expect(keys.apkamSymmetricKey, isNull);

      final verbs =
          verify(() => mockAtLookUp.executeVerb(captureAny())).captured;
      expect(
          verbs
              .whereType<UpdateVerbBuilder>()
              .where((b) => b.atKey.key == 'publickey'),
          isEmpty,
          reason: 'publishing a null publickey would be worse than publishing '
              'none: a legacy peer would encrypt to it and produce ciphertext '
              'nobody can ever read');
      expect(verbs.whereType<DeleteVerbBuilder>(), isNotEmpty,
          reason: 'the CRAM secret is a live path back into the atSign and is '
              'deleted whichever material was minted');
    });

    test('null resolves to true, not to false', () async {
      await atAuth.onboard(
          requestFor(signingAlgo: SigningAlgoType.mldsa65), cramSecret);
      final keys = await keysIo.read(atSign);
      expect(keys.defaultEncryptionPublicKey, isNotNull,
          reason: 'legacy material is retained until the ECOSYSTEM is PQ, not '
              'until this atSign is; the default inverts in a later major');
    });
  });

  group('the legacy activation is unchanged', () {
    test(
        'rsa2048 is the default and fills the flat fields, with no typed '
        'signing material', () async {
      await atAuth.onboard(requestFor(), cramSecret);

      final keys = await keysIo.read(atSign);
      expect(keys.apkamPublicKey, isNotNull);
      expect(keys.apkamPrivateKey, isNotNull);
      expect(keys.apkamPublicKey.toString(), contains('MI'),
          reason: 'an RSA key, base64 of DER — not raw ML-DSA bytes');
      expect(keys.signingAlgorithmForEnrollment(enrollmentId), isNull,
          reason: 'a legacy enrollment reports null and authenticate() falls '
              'through to the flat-field path, exactly as before');
      expect(submittedRequest().signingAlgo, SigningAlgoType.rsa2048);
    });
  });
}
