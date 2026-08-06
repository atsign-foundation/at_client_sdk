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

import 'dart:convert'
    show base64Decode, base64Encode, jsonDecode, jsonEncode, utf8;

import 'package:at_chops/at_chops.dart'
    show
        HashingAlgoType,
        MlDsa65PureDartAlgo,
        RsaKeyPair,
        RsaSigningAlgo,
        SigningAlgoType;
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
  // Refuse to sign under a hash the verifier will not accept, so nobody can
  // produce an envelope that is well-formed and permanently uncheckable.
  _verifiableHashingAlgo(hashingAlgo.name);

  final String signableText = signableTextOf(payload, toEncodable: toEncodable);

  final String signature;
  switch (signingAlgo) {
    case SigningAlgoType.rsa2048:
      final algo = RsaSigningAlgo(
          RsaKeyPair.create(keys.publicKey, keys.privateKey), hashingAlgo);
      signature = base64Encode(algo.sign(utf8.encode(signableText)));
    case SigningAlgoType.mldsa65:
      // [keys] carries base64 of the raw ML-DSA-65 keys; ML-DSA signs the
      // message directly, so [hashingAlgo] plays no part (the envelope still
      // records it for shape stability).
      signature = base64Encode(MlDsa65PureDartAlgo.signBytesSync(
          utf8.encode(signableText),
          secretKey: base64Decode(keys.privateKey)));
    default:
      throw ArgumentError.value(
          signingAlgo, 'signingAlgo', 'no envelope signing support');
  }

  return {
    'payload': payload,
    'signature': signature,
    'hashingAlgo': hashingAlgo.name,
    'signingAlgo': signingAlgo.name,
    if (enrollmentId != null) 'enrollmentId': enrollmentId,
  };
}

/// A parsed `_apsk` value: which algorithm the key is for, and the key itself.
///
/// The published record comes in two forms, and the migration between them is
/// the same two-release ladder as everything else
/// (`docs/projects/pq/decisions.md` 39):
///
/// - **Bare (today, and everything the final 3.x publishes):** the RSA public
///   key string exactly as `_apsk` has always carried it. Parsed as
///   [SigningAlgoType.rsa2048].
/// - **Tagged (what 4.x's new enrollments publish):** a JSON object
///   `{"v": 1, "signingAlgo": "mldsa65", "publicKey": "<base64>"}`. The shape
///   is deliberately unmistakable to an old bare-RSA parser — a consumer that
///   base64-decodes it as an RSA key fails loudly, never mis-reads it.
class ParsedApsk {
  final SigningAlgoType signingAlgo;

  /// The key material: the bare RSA string for [SigningAlgoType.rsa2048], or
  /// base64 of the raw ML-DSA-65 public key for [SigningAlgoType.mldsa65].
  final String publicKey;

  const ParsedApsk({required this.signingAlgo, required this.publicKey});
}

/// Parses a fetched `_apsk` value, bare or tagged.
///
/// Throws [AtSigningVerificationException] on a tagged value that names an
/// algorithm this build has no code for — the reader must fail loudly rather
/// than guess, because a guessed algorithm turns a key mismatch into silent
/// acceptance of whatever the server sent.
ParsedApsk parseApskValue(String value) {
  final trimmed = value.trim();
  if (!trimmed.startsWith('{')) {
    // The bare legacy form: an RSA public key string, as published today.
    return ParsedApsk(signingAlgo: SigningAlgoType.rsa2048, publicKey: trimmed);
  }

  final Map<String, dynamic> tagged;
  try {
    tagged = jsonDecode(trimmed) as Map<String, dynamic>;
  } on FormatException catch (e) {
    throw AtSigningVerificationException(
        'the _apsk value looks tagged but is not valid JSON: ${e.message}');
  }
  final algoName = tagged['signingAlgo'];
  final publicKey = tagged['publicKey'];
  if (algoName is! String || publicKey is! String) {
    throw AtSigningVerificationException(
        'a tagged _apsk must carry signingAlgo and publicKey');
  }
  final algo =
      SigningAlgoType.values.where((a) => a.name == algoName).firstOrNull;
  if (algo == null) {
    throw AtSigningVerificationException(
        'the _apsk names signing algorithm "$algoName", which this build has '
        'no code for — refusing to verify rather than guessing');
  }
  return ParsedApsk(signingAlgo: algo, publicKey: publicKey);
}

/// Encodes the tagged, self-describing `_apsk` form.
///
/// Nothing in 3.x publishes this — the final 3.x keeps the bare form exactly
/// as it is, because apps sign and verify against `_apsk` today and their
/// parsers expect it. This exists so the read side can be tested against the
/// format 4.x's new enrollments will publish, and so the format has exactly
/// one definition.
String encodeTaggedApsk(
        {required SigningAlgoType signingAlgo, required String publicKey}) =>
    jsonEncode(
        {'v': 1, 'signingAlgo': signingAlgo.name, 'publicKey': publicKey});

/// Verifies an envelope produced by [signEnvelope] against
/// [signerPublicKey] — the `_apsk` value the signer's enrollment published,
/// in either its bare or its tagged form.
///
/// **The key's own declaration is authoritative** over the envelope's
/// `signingAlgo` claim, matching PKAM's record-authoritative rule
/// (`docs/projects/pq/decisions.md` 34): a tagged key names its algorithm and
/// the envelope must agree; a bare key is RSA by definition, so an envelope
/// claiming otherwise fails against it. Either way, a lie about `signingAlgo`
/// fails the verify — it can never select a weaker routine than the published
/// key calls for.
///
/// The same rule applies to `hashingAlgo`, which the envelope also names and
/// the signature also does not cover. It is checked against an allowlist rather
/// than resolved straight to a routine — `HashingAlgoType` carries `md5`, and
/// an unsigned field must not be able to select a broken hash.
///
/// Throws [AtSigningVerificationException] if the signature does not check
/// out. Verification needs no keypair of its own: the public key is the whole
/// input, which is why this works on a client holding no keys at all.
/// The hashes an envelope is allowed to name.
///
/// `HashingAlgoType` also carries `md5` and `argon2id`. MD5's collision
/// resistance is broken and Argon2id is a password KDF rather than a signature
/// hash, so neither belongs under a signature — and this field is not covered
/// by the signature, which makes it an unauthenticated input selecting a
/// cryptographic routine.
///
/// Nothing produces anything but `sha256` today: `wrapAndSign` never passes
/// `hashingAlgo`, and neither does the key-package signer, so both take
/// [signEnvelope]'s default. `sha512` is allowed because it is a legitimate
/// signature hash a future producer might reasonably choose.
const Set<HashingAlgoType> _verifiableHashingAlgos = {
  HashingAlgoType.sha256,
  HashingAlgoType.sha512,
};

/// Resolves the envelope's `hashingAlgo` claim, refusing anything outside
/// [_verifiableHashingAlgos].
///
/// Also the reason this is a function rather than a `byName` call: `byName`
/// throws `ArgumentError` for an unknown name and a type error for a null one,
/// so a malformed envelope escaped as an uncaught error instead of the
/// documented [AtSigningVerificationException].
HashingAlgoType _verifiableHashingAlgo(Object? claimed) {
  if (claimed is! String) {
    throw AtSigningVerificationException(
        'the envelope names no hashingAlgo, so there is no way to know which '
        'hash its signature covers');
  }
  final algo =
      HashingAlgoType.values.where((a) => a.name == claimed).firstOrNull;
  if (algo == null || !_verifiableHashingAlgos.contains(algo)) {
    throw AtSigningVerificationException(
        'the envelope claims hashingAlgo "$claimed", which is not one this '
        'build will verify a signature under — refusing rather than letting '
        'an unsigned field choose the routine');
  }
  return algo;
}

Future<void> verifyEnvelope(
  Map envelope, {
  required String signerPublicKey,
  Object? Function(Object? nonEncodable)? toEncodable,
}) async {
  final parsed = parseApskValue(signerPublicKey);
  final claimed = envelope['signingAlgo'];
  if (claimed is String && claimed != parsed.signingAlgo.name) {
    throw AtSigningVerificationException(
        'the envelope claims signingAlgo "$claimed" but the published _apsk '
        'is a ${parsed.signingAlgo.name} key — refusing the mismatch rather '
        'than letting the claim choose the routine');
  }
  final String signableText =
      signableTextOf(envelope['payload'], toEncodable: toEncodable);

  final bool ok;
  switch (parsed.signingAlgo) {
    case SigningAlgoType.mldsa65:
      ok = await MlDsa65PureDartAlgo().verifyBytes(
        utf8.encode(signableText),
        signature: base64Decode(envelope['signature']),
        publicKey: base64Decode(parsed.publicKey),
      );
    case SigningAlgoType.rsa2048:
      final hashingAlgo = _verifiableHashingAlgo(envelope['hashingAlgo']);
      ok = RsaSigningAlgo(null, hashingAlgo).verify(
        utf8.encode(signableText),
        base64Decode(envelope['signature']),
        publicKey: parsed.publicKey,
      );
    default:
      throw AtSigningVerificationException(
          'no verify routine for ${parsed.signingAlgo.name}');
  }
  if (!ok) {
    throw AtSigningVerificationException(
        'Signature verification failed using public key $signerPublicKey');
  }
}
