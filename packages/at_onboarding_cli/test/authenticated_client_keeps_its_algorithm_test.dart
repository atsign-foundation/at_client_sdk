import 'dart:io';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockAtAuth extends Mock implements AtAuth {}

class _FakeAtAuthRequest extends Fake implements AtAuthRequest {}

/// **Key material outranks the preference for an authenticated client.**
///
/// `_initAtClient` serves two flows through one method. Enrolment hands it a
/// lookup this service built for an APKAM keypair minted moments earlier, with
/// no keyfile yet to resolve from — there the preference is the only source
/// there is. Authentication hands it nothing, so it adopts the client's own
/// lookup, and that client has already read the keyfile.
///
/// Writing the preference over the second case is what
/// [#2161](https://github.com/atsign-foundation/at_client_sdk/issues/2161)
/// reported: `at_activate otp` and `at_activate list` build their client
/// through `createAtClient`, which constructs a bare `AtOnboardingPreference`
/// and so runs at `PqPosture.legacy`. On a PQ-native atSign the overwrite
/// claimed `rsa2048` for an ML-DSA enrollment, and the first reconnect signed
/// the challenge with the RSA routine.
///
/// The two tests are a pair. Asserting only that the adopted lookup keeps
/// `mldsa65` would pass just as well if the stamp had been deleted outright,
/// which would break enrolment — so the second arm holds the stamp in place
/// for the flow that needs it.
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
        keyPartType: CryptographicMaterialRole.privateAuthentication,
        keyAlgorithmType: CryptographicMaterialAlgorithm.mlDsa65,
        bytes: AtBytes(Uint8List.fromList(List<int>.filled(32, 3))),
        createdAt: now,
      ))
      ..addKey(CryptographicMaterial(
        keyId: 'apkam:$enrollmentId:1',
        enrollmentId: enrollmentId,
        keyPartType: CryptographicMaterialRole.publicAuthentication,
        keyAlgorithmType: CryptographicMaterialAlgorithm.mlDsa65,
        bytes: AtBytes(Uint8List.fromList(List<int>.filled(32, 4))),
        createdAt: now,
      ));
    await FileAtKeysIo(filePath: (_) => path).write(atSign, keys);
    addTearDown(() => File(path).parent.deleteSync(recursive: true));
    return path;
  }

  /// A service whose `authenticate()` will succeed without a server, reading
  /// [keysFilePath], under a **bare** preference — the `PqPosture.legacy`
  /// default that `createAtClient` gives every `otp`/`list` invocation.
  AtOnboardingServiceImpl legacyPostureService(
      String atSign, String keysFilePath, String enrollmentId, AtAuth atAuth) {
    final preference = AtOnboardingPreference()
      ..atKeysFilePath = keysFilePath
      ..namespace = 'unit_test'
      ..hiveStoragePath = 'test/storage/hive/$atSign'
      ..commitLogPath = 'test/storage/hive/$atSign/commit';
    expect(preference.authenticationKeyAlgorithm, SigningAlgoType.rsa2048,
        reason: 'the rig must supply the legacy default, or these tests '
            'compare mldsa65 with mldsa65 and discriminate nothing');

    when(() => atAuth.progressStream).thenAnswer((_) => Stream.empty());
    when(() => atAuth.atChops).thenReturn(AtChopsImpl(AtChopsKeys()));
    when(() => atAuth.authenticate(any())).thenAnswer(
        (_) async => AtAuthResponse(atSign)
          ..isSuccessful = true
          ..atAuthKeys = (AtKeys()..enrollmentId = enrollmentId));

    return AtOnboardingServiceImpl(atSign, preference)..atAuth = atAuth;
  }

  test('an authenticated client keeps the algorithm it resolved from its keys',
      () async {
    const atSign = '@pq_adopted';
    const enrollmentId = 'pq-adopted-1';
    final service = legacyPostureService(
        atSign, await pqKeyfile(atSign, enrollmentId), enrollmentId,
        _MockAtAuth());

    expect(await service.authenticate(), isTrue);

    // The lookup under test is the client's own, adopted because this service
    // built none of its own for the authenticate flow.
    final adopted = service.atLookUp!;
    expect(identical(adopted, AtClientManager.getInstance().atClient
        .getRemoteSecondary()!.atLookUp), isTrue,
        reason: 'the flow under test is the one that adopts the client\'s '
            'lookup; if this service built its own, the assertion below is '
            'about the wrong object');

    expect(adopted.signingAlgoType, SigningAlgoType.mldsa65,
        reason: 'the keyfile holds ML-DSA authentication material for this '
            'enrollment, and the preference says rsa2048 — the key material '
            'is what the connection has to sign with');
    expect(adopted.enrollmentId, enrollmentId);
  });

  test('a lookup this service built is still stamped from the preference',
      () async {
    const atSign = '@pq_own_lookup';
    const enrollmentId = 'pq-own-1';
    // A real lookup rather than a mock, so what is read back is the value the
    // connection would authenticate with. It is stamped twice on this path —
    // once by the RemoteSecondary that wraps it, once here — and only the
    // last one decides, which a call count cannot tell you.
    final own = AtLookupImpl(atSign, 'vip.ve.atsign.zone', 64);
    final service = legacyPostureService(
        atSign, await pqKeyfile(atSign, enrollmentId), enrollmentId,
        _MockAtAuth())
      ..atLookUp = own;

    expect(await service.authenticate(), isTrue);

    // Enrolment's case: no keyfile has been written for the new enrollment
    // yet, so the posture's axis is the only thing that can say which routine
    // this connection authenticates with — even though the keyfile this
    // service happens to be pointed at says otherwise, which is what makes
    // this the opposite arm of the test above rather than a restatement of it.
    expect(own.signingAlgoType, SigningAlgoType.rsa2048);
    expect(own.enrollmentId, enrollmentId);
  });
}
