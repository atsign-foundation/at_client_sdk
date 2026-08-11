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
    show
        base64,
        base64Decode,
        base64Encode,
        base64Url,
        jsonDecode,
        jsonEncode,
        utf8;
import 'dart:typed_data' show Uint8List;

import 'package:at_chops/at_chops.dart'
    show
        HashingAlgoType,
        MlDsa65PureDartAlgo,
        RsaKeyPair,
        RsaSigningAlgo,
        SigningAlgoType;
import 'package:at_commons/at_commons.dart'
    show AtSigningVerificationException, EnrollmentConstants;

/// `public:_apsk.<enrollmentId>.a.__e@<atSign>` — where an enrollment's
/// APKAM public signing key lives, and the one record its own connection may
/// write.
///
/// The single builder of that address: publishers, verifiers and the
/// enrollment-key collector all resolve an `_apsk` through it. The atServer
/// mints the record at approval, so the spelling is a cross-implementation
/// contract; it is pinned in `test/wire_literal_pins_test.dart`.
String apskUri(String atSign, String enrollmentId) =>
    'public:_apsk.$enrollmentId.${EnrollmentConstants.perEnrollmentApproved}'
    '$atSign';

/// The original signed-envelope wrapper shape, and the one producers emit by
/// default: the payload embedded as-is, with `signingAlgo`, `hashingAlgo` and
/// `enrollmentId` sitting beside the signature rather than under it.
///
/// The wrapper carried no version until 2026-08-06, so an envelope without a
/// `v` field is this shape by definition.
///
/// The field is **not** covered by the signature, because only `payload` is.
/// Treat it as a parsing hint rather than an authenticated claim; the JWS
/// shape puts the equivalent in the protected header, where it is signed.
const int signedEnvelopeVersion = 1;

/// The JWS wrapper shape: RFC 7515 Flattened JSON Serialization, `b64` true.
///
/// ```json
/// {"v": 2, "payload": "<b64url>", "protected": "<b64url>",
///  "signature": "<b64url>"}
/// ```
///
/// The protected header is `{"alg": ..., "kid": "<enrollmentId>", "v": 2}`,
/// so the algorithm and the signer claim sit **inside** the signature —
/// the improvement over version 1, where both are unauthenticated wrapper
/// fields. `alg` is `RS256` for RSA-2048 (every RSA envelope is SHA-256) and
/// `ML-DSA-65` (RFC 9964) for the PQ arm; `hashingAlgo` has no equivalent
/// because the `alg` name carries the hash. The top-level `v` is the same
/// parsing hint version 1 carries — RFC 7515 requires unrecognised additional
/// members to be ignored, so off-the-shelf verifiers are undisturbed by it.
///
/// All three members are **unpadded** base64url, as RFC 7515 requires, and
/// Dart's `base64Decode` throws on unpadded input at some lengths — an
/// RSA-2048 signature is 342 chars (throws) while an ML-DSA-65 one is 4412
/// (decodes), so a naive decode fails on exactly the arm a PQ-focused test
/// never exercises. Every decode here goes through `base64.normalize` first.
///
/// Readers accept this shape always; producers emit it only when asked
/// (`signEnvelope`'s `version` parameter), because an envelope written into
/// the enrollment record's `metadata.keyPackage` in a shape the fleet cannot
/// read yet stays unreadable until that enrollment republishes it — and
/// `enroll:update` is self-only, so nothing else can repair it.
const int jwsEnvelopeVersion = 2;

/// The JOSE `alg` names the JWS shape signs under, keyed by the signing
/// algorithm. RSA is `RS256` exactly: nothing anywhere produces an RSA
/// envelope under any hash but SHA-256, so no other RSA mapping exists until
/// a producer does.
const String _jwsAlgRs256 = 'RS256';
const String _jwsAlgMlDsa65 = 'ML-DSA-65';

String _base64UrlUnpadded(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

/// Decodes JWS base64url, which is unpadded; `base64.normalize` restores the
/// padding Dart's decoder insists on. [what] names the member for the refusal.
Uint8List _base64UrlDecode(String s, String what) {
  try {
    return base64Decode(base64.normalize(s));
  } on FormatException catch (e) {
    throw AtSigningVerificationException(
        "the envelope's $what is not base64url: ${e.message}");
  }
}

/// Which wrapper shape [envelope] carries: [signedEnvelopeVersion] or
/// [jwsEnvelopeVersion]. An absent `v` is version 1 — the wrapper carried no
/// version field before 2026-08-06.
///
/// Throws [AtSigningVerificationException] for a version this build has no
/// code for: the fields a newer shape carries might mean something else
/// entirely, so it is refused rather than read as a shape it is not.
int envelopeVersionOf(Map envelope) {
  final v = envelope['v'];
  if (v == null || v == signedEnvelopeVersion) return signedEnvelopeVersion;
  if (v == jwsEnvelopeVersion) return jwsEnvelopeVersion;
  throw AtSigningVerificationException(
      'the envelope declares wrapper version "$v", which this build has no '
      'code for — refusing rather than guessing at its shape');
}

/// The decoded JWS protected header, refusing anything malformed.
Map _decodeProtectedHeader(Map envelope) {
  final protected = envelope['protected'];
  if (protected is! String) {
    throw AtSigningVerificationException(
        'a JWS envelope must carry its protected header as a string');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(
        utf8.decode(_base64UrlDecode(protected, 'protected header')));
  } on FormatException catch (e) {
    throw AtSigningVerificationException(
        "the envelope's protected header does not decode to JSON: "
        '${e.message}');
  }
  if (decoded is! Map) {
    throw AtSigningVerificationException(
        "the envelope's protected header is not a JSON object");
  }
  return decoded;
}

/// The payload [envelope] carries, whichever wrapper shape it is in: version
/// 1 embeds it as-is, the JWS shape as base64url of its JSON encoding.
///
/// This is the one way to read a payload out of a signed envelope — a direct
/// `envelope['payload']` read gets the undecoded base64url string on a JWS
/// envelope. Throws [AtSigningVerificationException] for an unknown wrapper
/// version or a JWS payload that does not decode.
Object? envelopePayloadOf(Map envelope) {
  if (envelopeVersionOf(envelope) == signedEnvelopeVersion) {
    return envelope['payload'];
  }
  final payload = envelope['payload'];
  if (payload is! String) {
    throw AtSigningVerificationException(
        'a JWS envelope must carry its payload as a string');
  }
  try {
    return jsonDecode(utf8.decode(_base64UrlDecode(payload, 'payload')));
  } on FormatException catch (e) {
    throw AtSigningVerificationException(
        "the envelope's payload does not decode to JSON: ${e.message}");
  }
}

/// The signer's enrollment-id claim, wherever the wrapper shape carries it:
/// the version-1 wrapper's `enrollmentId` field, or the JWS protected
/// header's `kid`. Null when the envelope makes no claim — a key package
/// signed at `enroll:request` time has no id to stamp, and its authority is
/// the record binding it to the request that created it.
///
/// In version 1 the claim is unauthenticated; in the JWS shape it is under
/// the signature. Either way it is a *claim* — what makes it true is the
/// signature verifying against the named enrollment's own `_apsk`.
String? envelopeSignerOf(Map envelope) {
  if (envelopeVersionOf(envelope) == signedEnvelopeVersion) {
    final claimed = envelope['enrollmentId'];
    return claimed is String ? claimed : null;
  }
  final kid = _decodeProtectedHeader(envelope)['kid'];
  return kid is String ? kid : null;
}

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
///
/// [version] selects the wrapper shape: [signedEnvelopeVersion] (the default)
/// or [jwsEnvelopeVersion]. The default stays at version 1 for all of 3.x —
/// see [jwsEnvelopeVersion] for why flipping it is a deployment decision, not
/// a code one.
Map<String, Object?> signEnvelope(
  Object? payload, {
  required ApkamSigningKeys keys,
  String? enrollmentId,
  HashingAlgoType hashingAlgo = HashingAlgoType.sha256,
  SigningAlgoType signingAlgo = SigningAlgoType.rsa2048,
  int version = signedEnvelopeVersion,
  Object? Function(Object? nonEncodable)? toEncodable,
}) {
  // Refuse to sign under a hash the verifier will not accept, so nobody can
  // produce an envelope that is well-formed and permanently uncheckable.
  _verifiableHashingAlgo(hashingAlgo.name);

  if (version == jwsEnvelopeVersion) {
    return _signJwsEnvelope(payload,
        keys: keys,
        enrollmentId: enrollmentId,
        hashingAlgo: hashingAlgo,
        signingAlgo: signingAlgo,
        toEncodable: toEncodable);
  }
  if (version != signedEnvelopeVersion) {
    throw ArgumentError.value(
        version, 'version', 'no envelope shape with this version to emit');
  }

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
    'v': signedEnvelopeVersion,
    'payload': payload,
    'signature': signature,
    'hashingAlgo': hashingAlgo.name,
    'signingAlgo': signingAlgo.name,
    if (enrollmentId != null) 'enrollmentId': enrollmentId,
  };
}

/// The [jwsEnvelopeVersion] arm of [signEnvelope]: RFC 7515 Flattened JSON,
/// signing input `ASCII(protected || '.' || payload)`.
Map<String, Object?> _signJwsEnvelope(
  Object? payload, {
  required ApkamSigningKeys keys,
  required String? enrollmentId,
  required HashingAlgoType hashingAlgo,
  required SigningAlgoType signingAlgo,
  required Object? Function(Object? nonEncodable)? toEncodable,
}) {
  final String alg;
  switch (signingAlgo) {
    case SigningAlgoType.rsa2048:
      if (hashingAlgo != HashingAlgoType.sha256) {
        throw ArgumentError.value(
            hashingAlgo,
            'hashingAlgo',
            'the JWS shape signs RSA as $_jwsAlgRs256, which is SHA-256 by '
                'definition; no producer emits any other RSA hash, so no '
                'other mapping exists');
      }
      alg = _jwsAlgRs256;
    case SigningAlgoType.mldsa65:
      // ML-DSA signs the message directly (RFC 9964); no hash to name.
      alg = _jwsAlgMlDsa65;
    default:
      throw ArgumentError.value(
          signingAlgo, 'signingAlgo', 'no envelope signing support');
  }

  // The payload is always its JSON encoding — including a String payload,
  // which version 1 signs verbatim. That keeps decode unconditional: what
  // comes out of base64url is JSON, whatever went in.
  final payloadB64 = _base64UrlUnpadded(
      utf8.encode(jsonEncode(payload, toEncodable: toEncodable)));
  final protectedB64 = _base64UrlUnpadded(utf8.encode(jsonEncode({
    'alg': alg,
    if (enrollmentId != null) 'kid': enrollmentId,
    'v': jwsEnvelopeVersion,
  })));
  final signingInput = utf8.encode('$protectedB64.$payloadB64');

  final Uint8List signatureBytes;
  switch (signingAlgo) {
    case SigningAlgoType.rsa2048:
      signatureBytes = RsaSigningAlgo(
              RsaKeyPair.create(keys.publicKey, keys.privateKey),
              HashingAlgoType.sha256)
          .sign(signingInput);
    case SigningAlgoType.mldsa65:
      signatureBytes = MlDsa65PureDartAlgo.signBytesSync(signingInput,
          secretKey: base64Decode(keys.privateKey));
    default:
      throw ArgumentError.value(
          signingAlgo, 'signingAlgo', 'no envelope signing support');
  }

  return {
    'v': jwsEnvelopeVersion,
    'payload': payloadB64,
    'protected': protectedB64,
    'signature': _base64UrlUnpadded(signatureBytes),
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
///
/// Both wrapper shapes are accepted, dispatched on the wrapper's `v` — see
/// [envelopeVersionOf]. In the JWS shape the signature covers the protected
/// header, so `alg` (and `kid`) are authenticated claims; the key's own
/// declaration is still authoritative over `alg`, exactly as it is over
/// version 1's `signingAlgo`.
Future<void> verifyEnvelope(
  Map envelope, {
  required String signerPublicKey,
  Object? Function(Object? nonEncodable)? toEncodable,
}) async {
  final parsed = parseApskValue(signerPublicKey);
  if (envelopeVersionOf(envelope) == jwsEnvelopeVersion) {
    return _verifyJwsEnvelope(envelope,
        parsed: parsed, signerPublicKey: signerPublicKey);
  }

  final claimed = envelope['signingAlgo'];
  if (claimed is String && claimed != parsed.signingAlgo.name) {
    throw AtSigningVerificationException(
        'the envelope claims signingAlgo "$claimed" but the published _apsk '
        'is a ${parsed.signingAlgo.name} key — refusing the mismatch rather '
        'than letting the claim choose the routine');
  }
  final signature = envelope['signature'];
  if (signature is! String) {
    // Refusal, not a cast error: a malformed envelope must land in the same
    // `on AtSigningVerificationException` guards every caller already has.
    throw AtSigningVerificationException(
        'the envelope carries no signature to check');
  }
  final String signableText =
      signableTextOf(envelope['payload'], toEncodable: toEncodable);

  final bool ok;
  switch (parsed.signingAlgo) {
    case SigningAlgoType.mldsa65:
      ok = await MlDsa65PureDartAlgo().verifyBytes(
        utf8.encode(signableText),
        signature: base64Decode(signature),
        publicKey: base64Decode(parsed.publicKey),
      );
    case SigningAlgoType.rsa2048:
      final hashingAlgo = _verifiableHashingAlgo(envelope['hashingAlgo']);
      ok = RsaSigningAlgo(null, hashingAlgo).verify(
        utf8.encode(signableText),
        base64Decode(signature),
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

/// The [jwsEnvelopeVersion] arm of [verifyEnvelope].
///
/// The signing input is the received `protected` and `payload` strings
/// verbatim — never a re-encoding of anything decoded — which is what makes
/// canonicalisation irrelevant in this shape.
Future<void> _verifyJwsEnvelope(
  Map envelope, {
  required ParsedApsk parsed,
  required String signerPublicKey,
}) async {
  final protected = envelope['protected'];
  final payload = envelope['payload'];
  final signature = envelope['signature'];
  if (protected is! String || payload is! String || signature is! String) {
    throw AtSigningVerificationException(
        'a JWS envelope must carry protected, payload and signature as '
        'strings');
  }
  final header = _decodeProtectedHeader(envelope);
  if (header['v'] != jwsEnvelopeVersion) {
    throw AtSigningVerificationException(
        'the protected header claims version "${header['v']}" where the '
        'wrapper says $jwsEnvelopeVersion — the signed claim is the one that '
        'counts, and it does not match');
  }

  void requireAlg(String expected) {
    if (header['alg'] != expected) {
      throw AtSigningVerificationException(
          'the envelope claims alg "${header['alg']}" but the published '
          '_apsk is a ${parsed.signingAlgo.name} key, which verifies '
          '$expected — refusing the mismatch rather than letting the claim '
          'choose the routine');
    }
  }

  final signingInput = utf8.encode('$protected.$payload');
  final signatureBytes = _base64UrlDecode(signature, 'signature');

  final bool ok;
  switch (parsed.signingAlgo) {
    case SigningAlgoType.mldsa65:
      requireAlg(_jwsAlgMlDsa65);
      ok = await MlDsa65PureDartAlgo().verifyBytes(
        signingInput,
        signature: signatureBytes,
        publicKey: base64Decode(parsed.publicKey),
      );
    case SigningAlgoType.rsa2048:
      // RS256 names its hash: RSASSA-PKCS1-v1_5 with SHA-256. Nothing
      // unsigned selects a routine in this shape.
      requireAlg(_jwsAlgRs256);
      ok = RsaSigningAlgo(null, HashingAlgoType.sha256).verify(
        signingInput,
        signatureBytes,
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
