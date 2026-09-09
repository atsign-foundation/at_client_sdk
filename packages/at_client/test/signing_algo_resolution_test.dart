import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/ml_dsa_keyfile.dart';
import 'test_utils/mocks.dart';

/// The signing algorithm is a fact about the enrollment's key material — you
/// cannot sign ML-DSA with an RSA key — so the client must resolve it from
/// the keyfile as an explicit init step, not as a side effect of building its
/// own AtChops.
///
/// A client whose AtChops is injected — the auth path — never builds one, so
/// resolving there would leave it signing the preference's rsa2048 default
/// under an ML-DSA enrollment and failing every reconnect against the
/// record-authoritative atServer.
void main() {
  final mockAtChopsKeys = MockAtChopsKeys();

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
      // Injected, so _createAtChops never runs.
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

    final preferences = AtClientPreference(posture: PqPosture.legacy)
      ..hiveStoragePath = 'test/hive'
      ..commitLogPath = 'test/hive/path';

    // A keyfile with no typed entries at all — the flat-fields legacy shape.
    final io = InMemoryAtKeysIo();
    // NOTE: the legacy posture above is deliberate — a pqReady client holding
    // a legacy enrollment retrofits rather than falling back, which is a
    // different behaviour.
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

  test(
      'the keypair comes from the keyfile even when the algorithm resolution '
      'failed', () async {
    const atSign = '@algo_resolution_3';
    const enrollmentId = 'pq-enrollment-3';
    AtClientImpl.atClientInstanceMap
        .remove(AtClientImpl.instanceKey(atSign, enrollmentId));

    final io = await mlDsaKeyfile(atSign, enrollmentId);
    // NOTE: the flat fields make this the retrofitted shape — a legacy
    // enrollment's RSA credentials beside the live enrollment's typed
    // material. Without them toAtChops() throws and the arms differ by an
    // exception rather than by which key was chosen.
    final stored = await io.read(atSign);
    stored
      ..apkamPublicKey = AtBytes.fromString(_flatApkamPublicKey)
      ..apkamPrivateKey = AtBytes.fromString(_flatApkamPrivateKey)
      ..defaultEncryptionPublicKey = AtBytes.fromString('ZmxhdC1lbmMtcHVibGlj')
      ..defaultEncryptionPrivateKey =
          AtBytes.fromString('ZmxhdC1lbmMtcHJpdmF0ZQ==')
      ..defaultSelfEncryptionKey =
          AtBytes.fromString('REqkIcl9HPekt0T7+rZhkrBvpysaPOeC2QL1PVuWlus=');

    final preferences = AtClientPreference()
      ..hiveStoragePath = 'test/hive'
      ..commitLogPath = 'test/hive/path';

    final ac = await AtClientImpl.create(
      atSign,
      'unit',
      preferences,
      remoteSecondary: MockRemoteSecondary(),
      // No injected AtChops, so the client builds its own — which is the
      // path under test.
      atKeysIo: _FailsFirstReadAtKeysIo(io),
      enrollmentId: enrollmentId,
    ) as AtClientImpl;

    // The resolution read threw, so the preference's rsa2048 stands — the
    // survivable fallback.
    expect(ac.signingAlgoType, SigningAlgoType.rsa2048);

    // The keypair is not survivable: serving the flat fields signs PKAM as the
    // enrollment that owns them.
    final pkam =
        (ac.atChops as AtChopsImpl).atChopsKeys.atPkamKeyPair!.atPublicKey;
    expect(pkam.publicKey, isNot(_flatApkamPublicKey),
        reason: 'the flat fields belong to a different enrollment');
  });
}

const _flatApkamPublicKey = 'ZmxhdC1hcGthbS1wdWJsaWM=';
const _flatApkamPrivateKey = 'ZmxhdC1hcGthbS1wcml2YXRl';

/// Fails the algorithm-resolution read and delegates every other.
///
/// The read before it decides the enrollment at construction and has to
/// succeed, so it is the second read that throws.
class _FailsFirstReadAtKeysIo extends WrittenAtKeysIo {
  _FailsFirstReadAtKeysIo(this._delegate);

  final InMemoryAtKeysIo _delegate;
  int _reads = 0;

  @override
  Future<AtKeys> read(String atsign) async {
    if (++_reads == 2) {
      throw AtKeysNotInMemoryException('transient read failure');
    }
    return await _delegate.read(atsign);
  }

  @override
  Future<void> write(String atsign, AtKeys atKeys) =>
      _delegate.write(atsign, atKeys);

  @override
  Future<void> flush(Atsign atsign, AtKeys atKeys) async =>
      _delegate.flush(atsign, atKeys);
}
