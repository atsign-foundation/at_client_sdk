import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

/// The signing algorithm is a fact about the enrollment's key material — you
/// cannot sign ML-DSA with an RSA key — so the client must resolve it from
/// the keyfile as an explicit init step, not as a side effect of building its
/// own AtChops. The side-effect version had a hole: a client whose AtChops
/// was injected (the auth path) never built one, so it signed the
/// preference's rsa2048 default under an ML-DSA enrollment and every
/// reconnect failed against the record-authoritative atServer.
void main() {
  final mockAtChopsKeys = MockAtChopsKeys();

  /// A keyfile whose [enrollmentId] has active typed ML-DSA signing material.
  Future<InMemoryAtKeysIo> mlDsaKeyfile(
      String atSign, String enrollmentId) async {
    final now = DateTime.now().toUtc();
    final keys = AtKeys()
      ..addKey(AtKeysMaterial(
        keyId: 'apkam-$enrollmentId',
        enrollmentId: enrollmentId,
        keyPartType: CryptographicKeyType.privateSigning,
        keyAlgorithmType: KeyAlgorithmType.mlDsa65,
        bytes: AtBytes(Uint8List.fromList(List<int>.filled(32, 3))),
        createdAt: now,
      ))
      ..addKey(AtKeysMaterial(
        keyId: 'apkam-$enrollmentId',
        enrollmentId: enrollmentId,
        keyPartType: CryptographicKeyType.publicVerification,
        keyAlgorithmType: KeyAlgorithmType.mlDsa65,
        bytes: AtBytes(Uint8List.fromList(List<int>.filled(32, 4))),
        createdAt: now,
      ));
    final io = InMemoryAtKeysIo();
    await io.write(atSign, keys);
    return io;
  }

  setUp(() {
    var key = 'REqkIcl9HPekt0T7+rZhkrBvpysaPOeC2QL1PVuWlus=';
    when(() => mockAtChopsKeys.selfEncryptionKey).thenReturn(AESKey(key));
  });

  test(
      'an injected-AtChops client still resolves its enrollment algorithm '
      'from the key material', () async {
    const atSign = '@algo_resolution_1';
    const enrollmentId = 'pq-enrollment-1';
    AtClientImpl.atClientInstanceMap
        .remove(AtClientImpl.instanceKey(atSign, enrollmentId));

    final preferences = AtClientPreference()
      ..hiveStoragePath = 'test/hive'
      ..commitLogPath = 'test/hive/path';

    final ac = await AtClientImpl.create(
      atSign,
      'unit',
      preferences,
      remoteSecondary: MockRemoteSecondary(),
      // Injected — so _createAtChops, whose keyfile read used to be the only
      // place the algorithm was resolved, never runs.
      // ignore: deprecated_member_use_from_same_package
      atChops: AtChopsImpl(mockAtChopsKeys),
      atKeysIo: await mlDsaKeyfile(atSign, enrollmentId),
      enrollmentId: enrollmentId,
    ) as AtClientImpl;

    expect(ac.signingAlgoType, SigningAlgoType.mldsa65,
        reason: 'the keyfile holds ML-DSA material for this enrollment; '
            'answering the preference default instead means every connection '
            'this client opens PKAMs with the wrong routine');
  });

  test('a legacy enrollment with no typed material falls back to rsa2048',
      () async {
    const atSign = '@algo_resolution_2';
    const enrollmentId = 'legacy-enrollment-1';
    AtClientImpl.atClientInstanceMap
        .remove(AtClientImpl.instanceKey(atSign, enrollmentId));

    final preferences = AtClientPreference()
      ..hiveStoragePath = 'test/hive'
      ..commitLogPath = 'test/hive/path';

    // A keyfile with no typed entries at all — the flat-fields legacy shape.
    final io = InMemoryAtKeysIo();
    await io.write(atSign, AtKeys());

    final ac = await AtClientImpl.create(
      atSign,
      'unit',
      preferences,
      remoteSecondary: MockRemoteSecondary(),
      // ignore: deprecated_member_use_from_same_package
      atChops: AtChopsImpl(mockAtChopsKeys),
      atKeysIo: io,
      enrollmentId: enrollmentId,
    ) as AtClientImpl;

    expect(ac.signingAlgoType, SigningAlgoType.rsa2048,
        reason: 'no typed material means a legacy RSA enrollment — the '
            'fallback, not a resolution failure');
  });
}
