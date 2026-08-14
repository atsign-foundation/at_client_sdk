import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/src/at_auth_impl.dart';
import 'package:at_auth/src/auth/pkam_authenticator.dart';
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
    keysIo =
        FileAtKeysIo(filePath: (a) => '${tempDir.path}/${a}_key.atKeys');

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
    when(() => mockAtLookUp.executeVerb(any())).thenAnswer((_) async => 'data:2');
    when(() => mockAtLookUp.close()).thenAnswer((_) async => {});
    when(() => mockPkam.authenticate(any(), any(),
        enrollmentId: any(named: 'enrollmentId'))).thenAnswer((_) async => true);
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
          {SigningAlgoType? signingAlgo, bool? mintLegacyMaterial}) =>
      AtOnboardingRequest(atSign)
        ..atKeysIo = keysIo
        ..appName = 'wavi'
        ..deviceName = 'iphone'
        ..mintLegacyMaterial = mintLegacyMaterial
        ..signingAlgoType = signingAlgo ?? SigningAlgoType.rsa2048;

  /// The request the onboard actually submitted.
  FirstEnrollmentRequest submittedRequest() =>
      verify(() => mockAtEnrollment.submit(captureAny(), any()))
          .captured
          .single as FirstEnrollmentRequest;

  group('PQ-native activation', () {
    test('the APKAM is ML-DSA-65, typed under the enrollment id, and the flat '
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
          CryptographicKeyType.privateAuthentication);
      final verification = keys.getKey(enrollmentId, 'auth:mldsa65:1',
          CryptographicKeyType.publicAuthentication);
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
                  CryptographicKeyType.publicAuthentication)!
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
    test('rsa2048 is the default and fills the flat fields, with no typed '
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
