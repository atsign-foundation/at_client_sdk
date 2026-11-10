// ignore_for_file: experimental_member_use

/// A test that verifies envelopes needs at_client_cli's barrel and its
/// test-support library, and nothing else from the SDK.
///
/// Catalogue: features/at_client/envelope_verification.feature
library;

import 'package:at_client_cli/at_client_cli.dart';
import 'package:at_client_cli/testing.dart';
import 'package:test/test.dart';

void main() {
  const e = 'enroll-e';

  for (final algorithm in [SigningAlgoType.mldsa65, SigningAlgoType.rsa2048]) {
    test(
        'TestEnvelopeSigner signs offline an envelope its PublishedApsk '
        'verifies: ${algorithm.name}', () async {
      final signer = await TestEnvelopeSigner.create(
          atSign: '@alice', enrollmentId: e, algorithm: algorithm);

      final result = await verifySignedEnvelope(signer.sign({'result': 1}),
          signer: signer.publishedApsk);

      expect(
          result,
          isA<EnvelopeVerified>()
              .having((r) => r.signer.atSign, 'atSign', '@alice')
              .having((r) => r.signer.enrollmentId, 'enrollmentId', e)
              .having((r) => r.algorithm, 'algorithm', algorithm)
              .having((r) => r.keyStatus, 'keyStatus', KeyEntryStatus.active)
              .having((r) => r.issuerConfirmed, 'issuerConfirmed', isTrue));
    });
  }

  test(
      'TestEnvelopeSigner lists its key under a status a test chooses: as '
      'retired', () async {
    final signer = await TestEnvelopeSigner.create(
        atSign: '@alice', enrollmentId: e, listedAs: KeyEntryStatus.retired);

    final result = await verifySignedEnvelope(signer.sign({'result': 1}),
        signer: signer.publishedApsk);

    expect(
        result,
        isA<EnvelopeVerified>()
            .having((r) => r.keyStatus, 'keyStatus', KeyEntryStatus.retired));
  });

  test(
      'TestEnvelopeSigner lists its key under a status a test chooses: under '
      'the unknown status "paused"', () async {
    final signer = await TestEnvelopeSigner.create(
        atSign: '@alice',
        enrollmentId: e,
        listedAs: const KeyEntryStatus.of('paused'));

    final result = await verifySignedEnvelope(signer.sign({'result': 1}),
        signer: signer.publishedApsk);

    expect(
        result,
        isA<EnvelopeRefused>()
            .having(
                (r) => r.refusal, 'refusal', EnvelopeRefusal.keyNotVouchedFor)
            .having((r) => r.reason, 'reason', contains('"paused"')));
  });
}
