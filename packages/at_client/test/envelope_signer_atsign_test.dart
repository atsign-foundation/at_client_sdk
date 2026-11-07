import 'dart:convert';

import 'package:at_client/src/crypto/nskey/pq_signing_chain.dart'
    show LinkVoucher;
import 'package:at_client/src/signing/envelope_signature.dart';
import 'package:test/test.dart';

import 'test_utils/envelope_signers.dart';
import 'test_utils/envelope_tamper.dart';

/// Catalogue: features/at_client/envelope_signer_atsign.feature
void main() {
  const alice = '@alice';
  const e = 'enroll-e';
  late Map<String, String> remoteData;
  late SigningClient ofE;

  setUp(() async {
    remoteData = {};
    ofE = await signingClient(alice, e, remoteData);
  });

  Map<String, Object?> headerOf(EnvelopeSignature entry) =>
      (jsonDecode(unb64u(entry.protected)) as Map).cast<String, Object?>();

  test(
      "Every envelope at_client signs names its signer's Atsign: an "
      'application payload through EnvelopeSigning.wrapAndSign', () async {
    final envelope = await ofE.signer.wrapAndSign({'result': 1});

    for (final entry in envelope.signatures) {
      expect(headerOf(entry)['iss'], alice);
    }
    expect(envelope.signerAtSign, alice);
  });

  test(
      "Every envelope at_client signs names its signer's Atsign: a chain "
      'link through PqSigningChain.signChainLink', () async {
    final link = SignedEnvelope.fromJson(await LinkVoucher.chain(
        key: ofE.key,
        atSign: alice,
        enrollmentId: e,
        keysWalked: const []).sign({'v': 2}));

    expect(link.signatures.map((s) => s.iss).toSet(), {alice});
    expect(link.signerAtSign, alice);
  });

  test(
      "An application envelope's header names the Atsign after the key and "
      'before the enrollment', () async {
    final envelope = await ofE.signer.wrapAndSign({'result': 1});

    for (final entry in envelope.signatures) {
      final header = headerOf(entry);
      expect(header.keys.toList(), ['alg', 'typ', 'kid', 'iss', 'enid', 'v']);
      expect(header['v'], 1);
    }
  });

  group('Given a client whose current Atsign is spelt "@Alice"', () {
    test('when it signs, then iss is "@alice"', () async {
      final spelt = await signingClient('@Alice', e, remoteData);

      final envelope = await spelt.signer.wrapAndSign({'result': 1});

      expect(headerOf(envelope.signature)['iss'], alice);
    });
  });
}
