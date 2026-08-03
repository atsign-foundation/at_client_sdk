/// Signing and verification of the JSON envelopes clients exchange, given the
/// key material as an argument.
///
/// These are functions rather than methods on a key-holding object, and that
/// is the point. Key state belongs in `AtKeys` (held by an `AtKeysIo`), not in
/// a long-lived crypto object a caller reaches into; `AtChops` is a collection
/// of stateless operations over material handed in per call.
///
/// It is also what makes the enrollment path possible at all. A key package
/// riding `enroll:request` must be signed by an APKAM keypair that exists only
/// for the moment between being generated and being sent — before there is any
/// approved enrollment, and before an `AtClient` exists to reach through.
///
/// The algorithm classes here are the non-deprecated surface: `PkamSigningAlgo`
/// and `AtPkamKeyPair` both carry deprecations pointing at `RsaSigningAlgo` and
/// `RsaKeyPair`, which take their key material directly.
library;

import 'dart:convert' show base64Decode, base64Encode, jsonEncode, utf8;

import 'package:at_chops/at_chops.dart'
    show HashingAlgoType, RsaKeyPair, RsaSigningAlgo, SigningAlgoType;
import 'package:at_commons/at_commons.dart' show AtSigningVerificationException;

/// The APKAM key material an envelope signature needs. The public half is
/// what a verifier fetches from the signer's `_apsk`; the private half signs.
class ApkamSigningKeys {
  final String publicKey;
  final String privateKey;

  const ApkamSigningKeys({required this.publicKey, required this.privateKey});
}

/// The exact text that is signed and verified. Strings are signed as-is;
/// everything else is signed as its JSON encoding. Verification re-derives
/// this from the decoded envelope, which is stable because Dart maps preserve
/// insertion order through a `jsonEncode`/`jsonDecode` round trip.
String signableTextOf(
  Object? payload, {
  Object? Function(Object? nonEncodable)? toEncodable,
}) {
  if (payload is String) {
    return payload;
  }
  return jsonEncode(payload, toEncodable: toEncodable);
}

/// Wraps [payload] in an envelope signed by [keys], verifiable by
/// [verifyEnvelope].
///
/// [enrollmentId] is stamped only when supplied. It is deliberately omitted
/// rather than defaulted when the signer has no enrollment yet: at
/// `enroll:request` time the atServer has not assigned one, and a guessed or
/// sentinel value would be frozen inside the signature where nobody could
/// correct it — the signer signed too early, the server stores the blob
/// verbatim, and a verifier can only check what it is given. Authority for an
/// absent claim is the signature verifying against that enrollment record's
/// own `_apsk`, plus the record binding the package to the request that
/// created it.
Map<String, Object?> signEnvelope(
  Object? payload, {
  required ApkamSigningKeys keys,
  String? enrollmentId,
  HashingAlgoType hashingAlgo = HashingAlgoType.sha256,
  SigningAlgoType signingAlgo = SigningAlgoType.rsa2048,
  Object? Function(Object? nonEncodable)? toEncodable,
}) {
  final String signableText = signableTextOf(payload, toEncodable: toEncodable);

  final algo = RsaSigningAlgo(
      RsaKeyPair.create(keys.publicKey, keys.privateKey), hashingAlgo);
  final signature = base64Encode(algo.sign(utf8.encode(signableText)));

  return {
    'payload': payload,
    'signature': signature,
    'hashingAlgo': hashingAlgo.name,
    'signingAlgo': signingAlgo.name,
    if (enrollmentId != null) 'enrollmentId': enrollmentId,
  };
}

/// Verifies an envelope produced by [signEnvelope] against
/// [signerPublicKey] — the APKAM public key the signer's enrollment published
/// at its `_apsk`.
///
/// Throws [AtSigningVerificationException] if the signature does not check
/// out. Verification needs no keypair of its own: the public key is the whole
/// input, which is why this works on a client holding no keys at all.
void verifyEnvelope(
  Map envelope, {
  required String signerPublicKey,
  Object? Function(Object? nonEncodable)? toEncodable,
}) {
  final hashingAlgo = HashingAlgoType.values.byName(envelope['hashingAlgo']);
  final String signableText =
      signableTextOf(envelope['payload'], toEncodable: toEncodable);

  final ok = RsaSigningAlgo(null, hashingAlgo).verify(
    utf8.encode(signableText),
    base64Decode(envelope['signature']),
    publicKey: signerPublicKey,
  );
  if (!ok) {
    throw AtSigningVerificationException(
        'Signature verification failed using public key $signerPublicKey');
  }
}
