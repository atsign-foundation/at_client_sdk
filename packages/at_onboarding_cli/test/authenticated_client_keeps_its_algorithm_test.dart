import 'dart:io';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/at_auth_io.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockAtAuth extends Mock implements AtAuth {}

class _FakeAtAuthRequest extends Fake implements AtAuthRequest {}

/// Key material outranks the preference for an authenticated client.
///
/// `_initAtClient` serves two flows, and both hand it the keyfile: enrolment
/// writes the keyfile for the new enrollment first and builds the client from
/// it, while authentication hands over the source at_auth just read. The two
/// tests are a pair — one adopts the client's own lookup, the other hands the
/// service's own lookup in — and both must come out stamped from the keyfile,
/// because the client's connection wraps whichever lookup it is given and
/// resolves the algorithm from the key material.
void main() {
  AtSignLogger.root_level = 'SHOUT';

  setUpAll(() => registerFallbackValue(_FakeAtAuthRequest()));

  /// A real `.atKeys` file whose [enrollmentId] holds typed ML-DSA
  /// **authentication** material, written through the same store
  /// `authenticate()` reads back through.
  Future<String> pqKeyfile(String atSign, String enrollmentId) async {
    final path = '${Directory.systemTemp.createTempSync('pq_keys').path}'
        '/${atSign}_key.atKeys';
    final now = DateTime.now().toUtc();
    final keys = AtKeys()
      ..enrollmentId = enrollmentId
      ..addKey(CryptographicMaterial(
        keyId: 'apkam:$enrollmentId:1',
        enrollmentId: enrollmentId,
        role: CryptographicMaterialRole.privateAuthentication,
        algorithm: CryptographicMaterialAlgorithm.mlDsa65,
        bytes: AtBytes(Uint8List.fromList(List<int>.filled(32, 3))),
        createdAt: now,
      ))
      ..addKey(CryptographicMaterial(
        keyId: 'apkam:$enrollmentId:1',
        enrollmentId: enrollmentId,
        role: CryptographicMaterialRole.publicAuthentication,
        algorithm: CryptographicMaterialAlgorithm.mlDsa65,
        bytes: AtBytes(Uint8List.fromList(List<int>.filled(32, 4))),
        createdAt: now,
      ));
    await FileAtKeysIo(filePath: (_) => path).write(atSign, keys);
    addTearDown(() => File(path).parent.deleteSync(recursive: true));
    return path;
  }

  /// A service whose `authenticate()` will succeed without a server, reading
  /// [keysFilePath], under `PqPosture.legacy`.
  ///
  /// The posture is named, not inherited: an inherited default supplies
  /// `mldsa65`, and these tests then compare `mldsa65` with `mldsa65`.
  AtOnboardingServiceImpl legacyPostureService(
      String atSign, String keysFilePath, String enrollmentId, AtAuth atAuth) {
    final preference = AtOnboardingPreference(posture: PqPosture.legacy)
      ..atKeysFilePath = keysFilePath
      ..namespace = 'unit_test'
      ..hiveStoragePath = 'test/storage/hive/$atSign'
      ..commitLogPath = 'test/storage/hive/$atSign/commit';
    expect(preference.authenticationKeyAlgorithm, SigningAlgoType.rsa2048,
        reason: 'the rig must supply the legacy algorithm, or these tests '
            'compare mldsa65 with mldsa65 and discriminate nothing');

    when(() => atAuth.progressStream).thenAnswer((_) => Stream.empty());
    when(() => atAuth.authenticate(any()))
        .thenAnswer((_) async => AtAuthResponse(atSign)
          ..isSuccessful = true
          ..atAuthKeys = (AtKeys()..enrollmentId = enrollmentId));

    return AtOnboardingServiceImpl(atSign, preference)..atAuth = atAuth;
  }

  test('an authenticated client keeps the algorithm it resolved from its keys',
      () async {
    const atSign = '@pq_adopted';
    const enrollmentId = 'pq-adopted-1';
    final service = legacyPostureService(atSign,
        await pqKeyfile(atSign, enrollmentId), enrollmentId, _MockAtAuth());

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
        reason: 'the flow under test is the one that adopts the client\'s '
            'lookup; if this service built its own, the assertion below is '
            'about the wrong object');

    expect(adopted.signingAlgoType, SigningAlgoType.mldsa65,
        reason: 'the keyfile holds ML-DSA authentication material for this '
            'enrollment, and the preference says rsa2048 — the key material '
            'is what the connection has to sign with');
    expect(adopted.enrollmentId, enrollmentId);
  });

  test('a lookup this service built is stamped from the keyfile too',
      () async {
    const atSign = '@pq_own_lookup';
    const enrollmentId = 'pq-own-1';
    // NOTE: a real lookup rather than a mock — the client's connection wraps
    // it and stamps it, and a mock would keep nothing to read back.
    final own = AtLookupImpl(atSign, 'vip.ve.atsign.zone', 64);
    final service = legacyPostureService(atSign,
        await pqKeyfile(atSign, enrollmentId), enrollmentId, _MockAtAuth())
      ..atLookUp = own;

    expect(await service.authenticate(), isTrue);

    // The service stamps nothing itself any more; what the lookup carries is
    // what the client's connection resolved from the keyfile, and the
    // preference's rsa2048 is what it would carry if the service still wrote
    // the credential ladder over the top.
    expect(own.signingAlgoType, SigningAlgoType.mldsa65,
        reason: 'the keyfile holds ML-DSA material for this enrollment; a '
            'stamp from the preference would sign it with the RSA routine');
    expect(own.enrollmentId, enrollmentId);
    expect(own.authenticator, isNotNull,
        reason: 'the connection authenticates from the keyfile through the '
            'seam, not from credentials parked on the lookup');
  });
}
