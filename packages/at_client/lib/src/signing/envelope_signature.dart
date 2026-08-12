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
    show base64, base64Decode, base64Url, jsonDecode, jsonEncode, utf8;
import 'dart:typed_data' show Uint8List;

import 'package:at_auth/at_auth.dart' show apskSigningKeys;
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

/// The envelope's payload version, carried **inside** each protected header
/// where the signature covers it.
///
/// There is one envelope shape and this is its first version. The two shapes
/// that preceded it — a tagged wrapper numbered 1 and RFC 7515 *Flattened*
/// numbered 2 — were deleted rather than carried, because nothing released
/// reads or writes an envelope, so there was no reader to stay compatible
/// with. The numbering restarts with the shape.
///
/// It sits in `protected` rather than at the top level deliberately: a version
/// outside the signature is a claim an attacker can edit, which is what made
/// the old wrapper's `v` a parsing hint rather than something a verifier could
/// rely on.
const int envelopeVersion = 1;

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

/// The `signatures` entries [envelope] carries, refusing anything malformed.
///
/// RFC 7515 general serialization always carries an array, even for one
/// signature. An empty one is refused rather than treated as unsigned: an
/// envelope nobody signed is not an envelope that verifies vacuously.
List _signaturesOf(Map envelope) {
  final signatures = envelope['signatures'];
  if (signatures is! List || signatures.isEmpty) {
    throw AtSigningVerificationException(
        'an envelope must carry a non-empty signatures array');
  }
  return signatures;
}

/// The decoded protected header of one `signatures` entry, refusing anything
/// malformed.
Map _decodeProtectedHeader(Map entry) {
  final protected = entry['protected'];
  if (protected is! String) {
    throw AtSigningVerificationException(
        'a signature entry must carry its protected header as a string');
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

/// The payload [envelope] carries, decoded.
///
/// This is the one way to read a payload out of a signed envelope — a direct
/// `envelope['payload']` read gets the undecoded base64url string. Throws
/// [AtSigningVerificationException] for a payload that does not decode.
Object? envelopePayloadOf(Map envelope) {
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

/// The signer's enrollment-id claim — the first signature's protected-header
/// `kid`. Null when the envelope makes no claim: a key package signed at
/// `enroll:request` time has no id to stamp, and its authority is the record
/// binding it to the request that created it.
///
/// The claim is under the signature, so it cannot be edited in flight. It is
/// still a *claim* — what makes it true is the signature verifying against
/// the named enrollment's own `_apsk`.
///
/// First entry, not a search: an envelope carries one signature per active
/// signing key of **one** signer, so every entry names the same `kid`. The
/// multi-signature reader that walks the rest arrives with signature agility.
String? envelopeSignerOf(Map envelope) {
  final entry = _signaturesOf(envelope).first;
  if (entry is! Map) {
    throw AtSigningVerificationException(
        'a signatures entry must be a JSON object');
  }
  final kid = _decodeProtectedHeader(entry)['kid'];
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
/// The result is RFC 7515 **general** JSON serialization:
/// `{payload, signatures: [{protected, signature}]}`, one entry per signing
/// key. One entry today; the multi-signature writer arrives with signature
/// agility, and the array is what lets it add an entry rather than change the
/// shape.
///
/// There is no hash to choose. `alg` names it: `RS256` **is** RSASSA-PKCS1-v1_5
/// with SHA-256, and ML-DSA signs the message directly. That is a property of
/// the shape rather than a restriction — the old envelope carried `hashingAlgo`
/// as its own unsigned member, so a hash had to be selected, policed, and
/// distrusted on the way back in.
Map<String, Object?> signEnvelope(
  Object? payload, {
  required ApkamSigningKeys keys,
  String? enrollmentId,
  SigningAlgoType signingAlgo = SigningAlgoType.rsa2048,
  Object? Function(Object? nonEncodable)? toEncodable,
}) {
  final String alg;
  switch (signingAlgo) {
    case SigningAlgoType.rsa2048:
      alg = _jwsAlgRs256;
    case SigningAlgoType.mldsa65:
      // ML-DSA signs the message directly (RFC 9964); no hash to name.
      alg = _jwsAlgMlDsa65;
    default:
      throw ArgumentError.value(
          signingAlgo, 'signingAlgo', 'no envelope signing support');
  }

  // The payload is always its JSON encoding, including a String payload.
  // That keeps decode unconditional: what comes out of base64url is JSON,
  // whatever went in.
  final payloadB64 = _base64UrlUnpadded(
      utf8.encode(jsonEncode(payload, toEncodable: toEncodable)));
  final protectedB64 = _base64UrlUnpadded(utf8.encode(jsonEncode({
    'alg': alg,
    if (enrollmentId != null) 'kid': enrollmentId,
    'v': envelopeVersion,
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
    'payload': payloadB64,
    'signatures': [
      {
        'protected': protectedB64,
        'signature': _base64UrlUnpadded(signatureBytes),
      }
    ],
  };
}

/// A parsed `_apsk` value: which algorithm the key is for, and the key itself.
///
/// The published record comes in two forms, and which one it holds depends on
/// what published it:
///
/// - **Bare:** the RSA public key string exactly as `_apsk` has always carried
///   it. Parsed as [SigningAlgoType.rsa2048]. Published by every released
///   client, by `ApkamSigning.publishPublicSigningKey` (the only writer for a
///   connection with no enrollment id, `_apsk.primary`), and by the atServer
///   from a plain-legacy enrollment's `EnrollParams.apskLegacy`.
/// - **Array:** `{"v": 1, "keys": [...]}`, composed by the enrolling client
///   and written verbatim by the atServer when the enrollment is approved. See
///   `apskAdvertisement` in at_auth, which is also where it is parsed. It is
///   the only form that can carry a second algorithm's key beside the first,
///   which is why every non-legacy enrollment uses it.
///
/// The array is deliberately unmistakable to an old bare-RSA parser — a
/// consumer that base64-decodes it as an RSA key fails loudly, never mis-reads
/// it — which is exactly why a plain-legacy enrollment publishes the bare form
/// instead of it.
class ParsedApsk {
  final SigningAlgoType signingAlgo;

  /// The key material: the bare RSA string for [SigningAlgoType.rsa2048], or
  /// base64 of the raw ML-DSA-65 public key for [SigningAlgoType.mldsa65].
  final String publicKey;

  const ParsedApsk({required this.signingAlgo, required this.publicKey});
}

/// Parses a fetched `_apsk` value, bare or array.
///
/// Throws [AtSigningVerificationException] when the value names no algorithm
/// this build has code for — the reader must fail loudly rather than guess,
/// because a guessed algorithm turns a key mismatch into silent acceptance of
/// whatever the server sent. There is deliberately no fallback to a key
/// derived some other way: the signature means something only if the verifier
/// used the key the signer published.
ParsedApsk parseApskValue(String value) {
  final trimmed = value.trim();
  if (!trimmed.startsWith('{')) {
    // The bare legacy form: an RSA public key string, as published today.
    return ParsedApsk(signingAlgo: SigningAlgoType.rsa2048, publicKey: trimmed);
  }

  final Map<String, dynamic> advertisement;
  try {
    advertisement = jsonDecode(trimmed) as Map<String, dynamic>;
  } on FormatException catch (e) {
    throw AtSigningVerificationException(
        'the _apsk value looks structured but is not valid JSON: ${e.message}');
  }

  // The array form an enrollment publishes. Entries whose `use` or `alg` this
  // build does not know are skipped by apskSigningKeys, so an advertisement
  // that is all future algorithms arrives empty rather than half-read.
  final advertised = apskSigningKeys(advertisement);
  if (advertised.isEmpty) {
    throw AtSigningVerificationException(
        'the _apsk advertises no signing key this build understands — '
        'refusing to verify rather than guessing');
  }
  // One key per enrollment today, so first is unambiguous. Ranking several by
  // strength arrives with the strength order beside SigningAlgoType.
  final key = advertised.first;
  return ParsedApsk(signingAlgo: key.alg, publicKey: key.pub);
}

/// Verifies an envelope produced by [signEnvelope] against
/// [signerPublicKey] — the `_apsk` value the signer's enrollment published,
/// in either its bare or its array form.
///
/// **The key's own declaration is authoritative** over the envelope's `alg`
/// claim, matching PKAM's record-authoritative rule
/// (`docs/projects/pq/decisions.md` 34): the published key names its algorithm
/// and the envelope must agree. A lie about `alg` fails the verify — it can
/// never select a weaker routine than the published key calls for. The claim
/// is inside `protected`, so it is signed; the check is not about tamper but
/// about a signer and a published key disagreeing.
///
/// Throws [AtSigningVerificationException] if the signature does not check
/// out. Verification needs no keypair of its own: the public key is the whole
/// input, which is why this works on a client holding no keys at all.
///
/// Verifies the **first** signature entry. One entry per signer is what is
/// written today; the reader that walks every entry and picks the strongest
/// arrives with signature agility.
Future<void> verifyEnvelope(
  Map envelope, {
  required String signerPublicKey,
  Object? Function(Object? nonEncodable)? toEncodable,
}) async {
  final parsed = parseApskValue(signerPublicKey);

  final entry = _signaturesOf(envelope).first;
  if (entry is! Map) {
    throw AtSigningVerificationException(
        'a signatures entry must be a JSON object');
  }
  final protected = entry['protected'];
  final payload = envelope['payload'];
  final signature = entry['signature'];
  if (protected is! String || payload is! String || signature is! String) {
    // Refusal, not a cast error: a malformed envelope must land in the same
    // `on AtSigningVerificationException` guards every caller already has.
    throw AtSigningVerificationException(
        'an envelope must carry payload, and each signature entry its '
        'protected header and signature, as strings');
  }
  final header = _decodeProtectedHeader(entry);
  if (header['v'] != envelopeVersion) {
    throw AtSigningVerificationException(
        'the protected header claims envelope version "${header['v']}", and '
        'this build signs and verifies $envelopeVersion — refusing rather '
        'than reading it as a shape it may not be');
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

  // The signing input is the RECEIVED protected and payload strings verbatim,
  // never a re-encoding of anything decoded — which is what makes
  // canonicalisation irrelevant in this shape.
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
