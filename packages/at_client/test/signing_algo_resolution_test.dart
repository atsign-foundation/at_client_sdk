import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:test/test.dart';

import 'test_utils/ml_dsa_keyfile.dart';
import 'test_utils/mocks.dart';

/// The signing algorithm is a fact about the enrollment's key material — you
/// cannot sign ML-DSA with an RSA key — so the client resolves it from the
/// keyfile as an explicit init step.
void main() {
  test(
      'a keyfile client resolves its enrollment algorithm from the key '
      'material', () async {
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
    // NOTE: the legacy posture above is deliberate — a pqReady client holding
    // a legacy enrollment retrofits rather than falling back, which is a
    // different behaviour.
    final io = InMemoryAtKeysIo.holding(
        atSign,
        AtKeys.legacy(
            apkamPublicKey: _flatApkamPublicKey,
            apkamPrivateKey: _flatApkamPrivateKey,
            encryptionPublicKey: 'ZmxhdC1lbmMtcHVibGlj',
            encryptionPrivateKey: 'ZmxhdC1lbmMtcHJpdmF0ZQ==',
            selfEncryptionKey: 'REqkIcl9HPekt0T7+rZhkrBvpysaPOeC2QL1PVuWlus='));

    final ac = await AtClientImpl.create(
      atSign,
      'unit',
      preferences,
      remoteSecondary: MockRemoteSecondary(),
      atKeysIo: io,
      enrollmentId: enrollmentId,
    ) as AtClientImpl;

    expect(ac.signingAlgoType, SigningAlgoType.rsa2048,
        reason: 'no typed material means a legacy RSA enrollment — the '
            'fallback, not a resolution failure');
  });

  test(
      'the PKAM signs with the enrollment\'s own keypair even when the '
      'algorithm resolution failed', () async {
    const atSign = '@algo_resolution_3';
    const enrollmentId = 'pq-enrollment-3';
    AtClientImpl.atClientInstanceMap
        .remove(AtClientImpl.instanceKey(atSign, enrollmentId));

    final pqPair = await MlDsa65KeyPair.generate();
    final flatPair = RsaKeyPair.generate();
    // NOTE: the flat fields make this the retrofitted shape — a legacy
    // enrollment's RSA credentials beside the live enrollment's typed
    // material — and they are real, so the two arms differ by which key
    // signed rather than by an exception.
    final keys = AtKeys(atsign: atSign.toAtsign())
      ..fileApkamMaterial(
          enrollmentId: enrollmentId,
          algorithm: CryptographicMaterialAlgorithm.mlDsa65,
          publicKey: pqPair.atPublicKey.publicKey,
          privateKey: pqPair.atPrivateKey.privateKey)
      ..fileLegacyMaterial(
          apkamPublicKey: flatPair.atPublicKey.publicKey,
          apkamPrivateKey: flatPair.atPrivateKey.privateKey);

    final preferences = AtClientPreference()
      ..hiveStoragePath = 'test/hive'
      ..commitLogPath = 'test/hive/path';

    final ac = await AtClientImpl.create(
      atSign,
      'unit',
      preferences,
      remoteSecondary: MockRemoteSecondary(),
      atKeysIo: _FailsFirstReadAtKeysIo(InMemoryAtKeysIo.holding(atSign, keys)),
      enrollmentId: enrollmentId,
    ) as AtClientImpl;

    // The resolution read threw, so the preference's rsa2048 stands — the
    // survivable fallback.
    expect(ac.signingAlgoType, SigningAlgoType.rsa2048);

    const challenge = '_9e8169dc-5618-44ec-ab43-1a5b2144c581$atSign'
        ':c3d345fc-5691-4f90-bc34-17cba31f060f';
    final executor = _RecordingExecutor(['data:$challenge', 'data:success']);
    final authenticate = ac.buildRemoteSecondary().atLookUp.authenticator!;

    expect(await authenticate(executor), isTrue);

    final pkam = executor.sent.last;
    expect(pkam, startsWith('pkam:signingAlgo:mldsa65:'),
        reason: 'the flat fields belong to a different enrollment');
    expect(
        MlDsa65PureDartAlgo.verifyBytesSync(
            Uint8List.fromList(utf8.encode(challenge)),
            signature:
                base64Decode(pkam.substring(pkam.lastIndexOf(':') + 1).trim()),
            publicKey: base64Decode(pqPair.atPublicKey.publicKey)),
        isTrue);
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

/// Answers each command with the next of [replies] and records what was sent.
class _RecordingExecutor implements AtCommandExecutor {
  final List<String> sent = [];
  final List<String> replies;

  _RecordingExecutor(this.replies);

  @override
  Future<String> sendSync(String command,
      {int? maxWaitMilliSeconds, int? transientWaitTimeMillis}) async {
    sent.add(command);
    return replies.removeAt(0);
  }
}
