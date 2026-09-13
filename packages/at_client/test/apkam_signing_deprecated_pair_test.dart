// The pair is deprecated on purpose and this file is what holds its contract,
// so reading it here is the point.
// ignore_for_file: deprecated_member_use_from_same_package

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/signing/resolved_signing_algo.dart'
    show recordResolvedSigningAlgo;
import 'package:at_commons/at_commons.dart' show AtClientException;
import 'package:at_utils/at_utils.dart' show AtSignLogger;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/recorded_logs.dart';

class MockAtClient extends Mock implements AtClient {}

class TestSigner with ApkamSigning {
  @override
  final AtClient atClient;

  @override
  final AtSignLogger logger = AtSignLogger('TestSigner');

  TestSigner(this.atClient);
}

/// `ApkamSigning.publicSigningKey` and `.privateSigningKey`, which at_client
/// 3.14.0 published and a consumer still compiles against.
///
/// They answer the APKAM **authentication** keypair, as that version did, and
/// they are deprecated because `_apsk` stops advertising that key once the
/// enrollment holds signing keys of its own — so what they return can verify
/// against nothing. The replacement is `signingKeys`.
void main() {
  const atSign = '@alice';
  const enrollmentId = 'enroll-a';
  final logs = RecordedLogs();

  late MockAtClient atClient;
  late AtPkamKeyPair pkamPair;
  late TestSigner signer;

  setUpAll(() => logs.installOn());

  setUp(() {
    logs.records.clear();
    pkamPair = AtChopsUtil.generateAtPkamKeyPair();

    atClient = MockAtClient();
    when(() => atClient.atChops)
        .thenReturn(AtChopsImpl(AtChopsKeys.create(null, pkamPair)));
    when(() => atClient.getCurrentAtSign()).thenReturn(atSign);
    when(() => atClient.enrollmentId).thenReturn(enrollmentId);
    when(() => atClient.getPreferences()).thenReturn(null);
    recordResolvedSigningAlgo(atClient, SigningAlgoType.rsa2048);

    signer = TestSigner(atClient);
  });

  test('answer the APKAM keypair, the halves 3.14.0 answered with', () {
    expect(signer.publicSigningKey, pkamPair.atPublicKey.publicKey);
    expect(signer.privateSigningKey, pkamPair.atPrivateKey.privateKey);
    expect(logs.at('SHOUT'), isEmpty,
        reason: 'a legacy posture is the case these exist for, so reading '
            'them there is not worth shouting about');
  });

  test('refuse when the enrollment does not authenticate with RSA', () {
    recordResolvedSigningAlgo(atClient, SigningAlgoType.mldsa65);

    for (final read in [
      () => signer.publicSigningKey,
      () => signer.privateSigningKey,
    ]) {
      expect(
          read,
          throwsA(isA<AtClientException>()
              .having((e) => e.message, 'message', contains('mldsa65'))),
          reason: 'the pkam slot then holds base64 ML-DSA bytes, and handing '
              'those back where an RSA key is expected is a corrupted value '
              'rather than a policy mismatch - so this refuses instead of '
              'warning');
    }
  });

  test('refuse when the client holds no APKAM keypair', () {
    when(() => atClient.atChops)
        .thenReturn(AtChopsImpl(AtChopsKeys.create(null, null)));

    expect(
        () => signer.publicSigningKey,
        throwsA(isA<AtClientException>()
            .having((e) => e.message, 'message', contains('no APKAM keypair'))),
        reason: '3.14.0 met this with a bare null-check failure; a named '
            'refusal says which client and what to read instead');
  });

  test('shout under a posture that configures post-quantum providers', () {
    when(() => atClient.getPreferences())
        .thenReturn(AtClientPreference(posture: PqPosture.pqReady));

    expect(signer.publicSigningKey, pkamPair.atPublicKey.publicKey,
        reason: 'still answers - a consumer on a published version must keep '
            'working, which is the whole reason these are back');
    expect(logs.at('SHOUT').join(' '), contains('may no longer advertise'),
        reason: 'and says so where it may now be wrong: this is the posture '
            'under which the enrollment mints signing keys, and `_apsk` then '
            'stops naming the authentication key');
  });
}
