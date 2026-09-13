import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/at_auth_io.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_utils/at_logger.dart';
import 'package:test/test.dart';

import 'lifecycle_rig.dart';

/// Key material outranks the preference for the client `authenticate()`
/// opens: the connection signs with what the keyfile holds, whatever
/// algorithm the preference names.
void main() {
  AtSignLogger.root_level = 'SHOUT';

  /// A real `.atKeys` file whose [enrollmentId] holds typed ML-DSA
  /// **authentication** material, written through the same store
  /// `authenticate()` reads back through.
  Future<String> pqKeyfile(String atSign, String enrollmentId) async {
    final path = '${Directory.systemTemp.createTempSync('pq_keys').path}'
        '/${atSign}_key.atKeys';
    final pair = await MlDsa65KeyPair.generate();
    final now = DateTime.now().toUtc();
    final keys = AtKeys()
      // ignore: deprecated_member_use
      ..enrollmentId = enrollmentId
      ..addKey(CryptographicMaterial(
        keyId: 'auth:mldsa65:1',
        enrollmentId: enrollmentId,
        role: CryptographicMaterialRole.privateAuthentication,
        algorithm: CryptographicMaterialAlgorithm.mlDsa65,
        bytes: AtBytes.fromString(pair.atPrivateKey.privateKey),
        createdAt: now,
      ))
      ..addKey(CryptographicMaterial(
        keyId: 'auth:mldsa65:1',
        enrollmentId: enrollmentId,
        role: CryptographicMaterialRole.publicAuthentication,
        algorithm: CryptographicMaterialAlgorithm.mlDsa65,
        bytes: AtBytes.fromString(pair.atPublicKey.publicKey),
        createdAt: now,
      ));
    await FileAtKeysIo(filePath: (_) => path).write(atSign, keys);
    addTearDown(() => File(path).parent.deleteSync(recursive: true));
    return path;
  }

  tearDown(() async {
    for (final client
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await client.stop();
    }
    AtClientImpl.atClientInstanceMap.clear();
    AtClientManager.getInstance().reset();
  });

  test(
      'the client\'s connection is stamped from the keyfile, not the '
      'preference', () async {
    const atSign = '@pq_own_lookup';
    const enrollmentId = 'pq-own-1';
    final storage = Directory.systemTemp.createTempSync('pq_storage');
    addTearDown(() => storage.deleteSync(recursive: true));
    // The posture is named, not inherited: an inherited default supplies
    // mldsa65, and the test would then compare mldsa65 with mldsa65.
    final preference = AtOnboardingPreference(posture: PqPosture.legacy)
      ..atKeysFilePath = await pqKeyfile(atSign, enrollmentId)
      ..namespace = 'unit_test'
      ..rootDomain = InternetAddress.loopbackIPv4.address
      ..rootPort = await refusedPort()
      ..storagePath = storage.path;
    expect(preference.authenticationKeyAlgorithm, SigningAlgoType.rsa2048,
        reason: 'the rig must supply the legacy algorithm, or this test '
            'discriminates nothing');
    // NOTE: a real lookup rather than a mock — the client's connection stamps
    // it, and a mock would keep nothing to read back. It points at a port
    // nothing listens on, so the open comes back offline without a network.
    final own = AtLookupImpl(
        atSign, InternetAddress.loopbackIPv4.address, preference.rootPort);
    final service = AtOnboardingServiceImpl(atSign, preference, atLookUp: own);

    expect(await service.authenticate(), isFalse,
        reason: 'nothing listens, so the client is offline; the stamping '
            'under test happened when the client was built');

    expect(identical(own, service.atClient!.getRemoteSecondary()!.atLookUp),
        isTrue,
        reason: 'the client\'s connection wraps the lookup it was handed; if '
            'it built its own, the assertions below are about the wrong '
            'object');
    expect(own.signingAlgoType, SigningAlgoType.mldsa65,
        reason: 'the keyfile holds ML-DSA material for this enrollment and '
            'the preference says rsa2048; the key material is what the '
            'connection has to sign with');
    expect(own.enrollmentId, enrollmentId);
    expect(own.authenticator, isNotNull,
        reason: 'the connection authenticates from the keyfile through the '
            'seam, not from credentials parked on the lookup');
  });
}
