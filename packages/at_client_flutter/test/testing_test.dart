// ignore_for_file: experimental_member_use

/// A Flutter app's test that verifies envelopes needs at_client_flutter's
/// barrel and its test-support library, and nothing else from the SDK.
///
/// Catalogue: features/at_client/envelope_verification.feature
library;

import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:at_client_flutter/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TestEnvelopeSigner, from package:at_client_flutter/testing.dart, signs '
      'offline an envelope its PublishedApsk verifies', () async {
    final signer = await TestEnvelopeSigner.create(
      atSign: '@alice',
      enrollmentId: 'enroll-e',
    );

    final result = await verifySignedEnvelope(
      signer.sign({'result': 1}),
      signer: signer.publishedApsk,
    );

    expect(
      result,
      isA<EnvelopeVerified>()
          .having((r) => r.signer.atSign, 'atSign', '@alice')
          .having((r) => r.issuerConfirmed, 'issuerConfirmed', isTrue),
    );
  });
}
