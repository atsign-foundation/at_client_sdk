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

import 'package:at_auth/at_auth.dart'
    show ApskSigningKey, apskSigningKeys, publicKeyKidOfBase64;
import 'package:collection/collection.dart' show ListEquality;
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

/// What an envelope was signed **for**, stamped into the protected header as
/// the JOSE `typ` and required by the verifier that reads it.
///
/// Every use below is signed by one key — an enrollment's signing key, or the
/// APKAM authentication key it falls back to — and before this existed the
/// only thing telling two of them apart was which field names their payload
/// happened to carry. Nothing said "this was signed as a chain link", so an
/// envelope produced by any other use whose payload carried
/// `childEnrollmentId` and `apkamPublicKey` was a chain link from that signer.
/// The signature was never the weak part: it was that a signature over one
/// document meant the same thing in every context that read it.
///
/// A verifier is handed the type it expects rather than reading the envelope's
/// and dispatching on it. Reading it would let the document choose which
/// checks run, which is the confusion this closes rather than a cure for it.
///
/// The wire values are frozen and pinned in `test/wire_literal_pins_test.dart`.
/// They follow the JOSE convention of a media type with the `application/`
/// prefix dropped, which is what RFC 8725 asks explicit typing to look like.
enum EnvelopeType {
  /// Whatever an application passes to `EnvelopeSigning.wrapAndSign`.
  ///
  /// The default, and deliberately a type **no** internal verifier accepts: an
  /// app that signs data someone else influenced cannot be walked into
  /// producing a chain link, a key package or an advertisement, whatever the
  /// payload it was handed looks like.
  app('at-app+jws'),

  /// A parent enrollment vouching for a child's APKAM key —
  /// `PqSigningChain.signLinkFor`.
  chainLink('at-chain-link+jws'),

  /// An enrollment's public encapsulation key package, signed either at
  /// `enroll:request` time or when registered afterwards. One type for both:
  /// they are the same document, read by the same verifier.
  keyPackage('at-key-package+jws'),

  /// A published nskey key ring advertisement.
  nskeyRing('at-nskey-ring+jws'),

  /// A sealed secret addressed to one enrollment's key package.
  secretEnvelope('at-secret-envelope+jws');

  const EnvelopeType(this.typ);

  /// The `typ` value on the wire.
  final String typ;
}

/// The JOSE `alg` names the JWS shape signs under, keyed by the signing
/// algorithm. RSA is `RS256` exactly: nothing anywhere produces an RSA
/// envelope under any hash but SHA-256, so no other RSA mapping exists until
/// a producer does.
const String _jwsAlgRs256 = 'RS256';
const String _jwsAlgMlDsa65 = 'ML-DSA-65';

/// The JOSE `alg` [algo] signs under, or null when this build produces no
/// envelope signature for it.
///
/// One mapping for both directions, read by the signer choosing what to stamp
/// and by the verifier matching an `_apsk` entry against an envelope entry. Two
/// switches would be two chances to disagree, and a disagreement here presents
/// as a signature that will not verify with nothing to say for itself.
String? _joseAlgFor(SigningAlgoType algo) => switch (algo) {
      SigningAlgoType.rsa2048 => _jwsAlgRs256,
      // ML-DSA signs the message directly (RFC 9964); no hash to name.
      SigningAlgoType.mldsa65 => _jwsAlgMlDsa65,
      _ => null,
    };

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

/// One entry of a [SignedEnvelope]'s `signatures` array: a protected header
/// and the signature over it.
///
/// Both halves are kept as the base64url text they arrived as, never as
/// something decoded and re-encoded. The signing input is those exact
/// characters joined by a dot, so a round trip through any decoder is a
/// chance to change the bytes the signature covers — which is precisely what
/// makes canonicalisation irrelevant in this shape, and only stays true if
/// nothing re-encodes them.
class EnvelopeSignature {
  /// The protected header, base64url, verbatim.
  final String protected;

  /// The signature, base64url, verbatim.
  final String signature;

  /// The decoded protected header. Decoded once at construction, because an
  /// entry whose header cannot be read is not an entry.
  final Map<String, Object?> header;

  const EnvelopeSignature._(this.protected, this.signature, this.header);

  /// The JOSE algorithm this signature is under (`RS256`, `ML-DSA-65`).
  /// Null when the header names none, which [verifyEnvelope] refuses.
  String? get alg => header['alg'] is String ? header['alg'] as String : null;

  /// The signer's enrollment-id claim, or null when it makes none.
  String? get kid => header['kid'] is String ? header['kid'] as String : null;

  /// What this signature was made **for** — the [EnvelopeType.typ] the signer
  /// stamped. Null when the header names none, which [verifyEnvelope] refuses:
  /// an envelope that declares no purpose is one a verifier would have to
  /// assume a purpose for, and assuming is what typing replaced.
  String? get typ => header['typ'] is String ? header['typ'] as String : null;

  /// The envelope-shape version this entry was signed under.
  Object? get version => header['v'];

  /// Parses one entry, refusing anything malformed.
  factory EnvelopeSignature.fromJson(Object? json) {
    if (json is! Map) {
      throw AtSigningVerificationException(
          'a signatures entry must be a JSON object');
    }
    final protected = json['protected'];
    final signature = json['signature'];
    if (protected is! String || signature is! String) {
      // Refusal, not a cast error: a malformed envelope must land in the same
      // `on AtSigningVerificationException` guards every caller already has.
      throw AtSigningVerificationException(
          'a signature entry must carry its protected header and its '
          'signature as strings');
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
    return EnvelopeSignature._(
        protected, signature, decoded.cast<String, Object?>());
  }

  Map<String, Object?> toJson() =>
      {'protected': protected, 'signature': signature};

  // Value equality on the two wire members. The header is derived from
  // `protected`, so comparing it too would be comparing the same bytes twice.
  @override
  bool operator ==(Object other) =>
      other is EnvelopeSignature &&
      other.protected == protected &&
      other.signature == signature;

  @override
  int get hashCode => Object.hash(protected, signature);
}

/// A signed envelope: RFC 7515 general JSON serialization, and the only shape
/// this build signs or verifies.
///
/// It is a type rather than a `Map` on purpose. Every consumer of this
/// document reaches for a member of it, and a `Map` makes each of those reads
/// invisible to the analyzer — `envelope['signature']` on a shape that keeps
/// its signature one level down compiles fine and yields null. That is not
/// hypothetical: it is how the signing chain's already-published check came
/// to compare null against null and silently stop publishing. Holding a
/// [SignedEnvelope] means the structure was checked once, at the boundary,
/// and every read after that is a field the compiler knows about.
///
/// [fromJson] validates structure — a string payload, a non-empty
/// `signatures` array, each entry carrying a readable protected header. It
/// deliberately does NOT check the envelope's version or decode the payload:
/// version is a question about whether this build can *act* on the envelope,
/// which [verifyEnvelope] answers, and a payload is only decoded by whoever
/// wants it.
class SignedEnvelope {
  /// The payload, base64url, verbatim — see [EnvelopeSignature.protected] for
  /// why it is never held decoded.
  final String payloadB64;

  /// One entry per signing key of one signer, in the order the signer listed
  /// them — every entry over the same payload, each under its own algorithm,
  /// all naming the same signer.
  ///
  /// Several is the point: a verifier takes the strongest algorithm this
  /// envelope and the signer's published `_apsk` share, so an envelope
  /// carrying two is readable both by a peer that implements the stronger one
  /// and by a peer that does not. In practice there is exactly one until
  /// something files per-algorithm signing material, because a signer with one
  /// key emits one signature.
  final List<EnvelopeSignature> signatures;

  const SignedEnvelope._(this.payloadB64, this.signatures);

  /// The first entry, for the callers that want *an* entry — the payload's
  /// encoding and the signer claim are the same in all of them.
  ///
  /// **Not the entry a verifier checks.** `verifyEnvelope` resolves that from
  /// the algorithms the envelope and the signer's `_apsk` share, taking the
  /// strongest; taking the first would let the signer's ordering decide.
  EnvelopeSignature get signature => signatures.first;

  /// The signer's enrollment-id claim, or null when the envelope makes none —
  /// a key package signed at `enroll:request` time has no id to stamp, and
  /// its authority is the record binding it to the request that created it.
  ///
  /// The claim is under the signature, so it cannot be edited in flight. It
  /// is still a *claim*: what makes it true is the signature verifying
  /// against the named enrollment's own `_apsk`.
  String? get signerEnrollmentId => signature.kid;

  /// The payload, decoded.
  ///
  /// Throws [AtSigningVerificationException] for a payload that does not
  /// decode — which is a different failure from a malformed envelope, and is
  /// why it is not checked at [fromJson].
  Object? get payload {
    try {
      return jsonDecode(utf8.decode(_base64UrlDecode(payloadB64, 'payload')));
    } on FormatException catch (e) {
      throw AtSigningVerificationException(
          "the envelope's payload does not decode to JSON: ${e.message}");
    }
  }

  /// Parses [json], refusing anything that is not structurally an envelope.
  ///
  /// An empty `signatures` array is refused rather than treated as unsigned:
  /// an envelope nobody signed is not one that verifies vacuously.
  factory SignedEnvelope.fromJson(Map json) {
    final payload = json['payload'];
    if (payload is! String) {
      throw AtSigningVerificationException(
          'an envelope must carry its payload as a string');
    }
    final signatures = json['signatures'];
    if (signatures is! List || signatures.isEmpty) {
      throw AtSigningVerificationException(
          'an envelope must carry a non-empty signatures array');
    }
    final parsed = signatures.map(EnvelopeSignature.fromJson).toList();
    // Every entry names one signer, so every entry must name the SAME one.
    // Without this the entry that verifies and the entry a caller reads
    // `signerEnrollmentId` from can be different entries: append a signature
    // under a stronger algorithm carrying someone else's kid, and a caller acts
    // on a signer whose signature was never the one checked. Refused here
    // rather than at verify, because an envelope claiming two signers is not
    // this shape at all.
    final kids = {for (final s in parsed) s.kid};
    if (kids.length > 1) {
      throw AtSigningVerificationException(
          'an envelope carries one signer\'s signatures, and this one names '
          '${kids.map((k) => '"$k"').join(', ')} — refusing rather than '
          'verifying under one of them and reporting another');
    }
    // Every entry signs one document, so every entry must say the document is
    // for the same thing. Refused here for the reason the kid check above is:
    // the entry a verifier resolves is chosen by algorithm, so entries that
    // disagree would let the checked entry and the declared purpose be
    // different entries — append one under a stronger algorithm claiming
    // another type, and the type the verifier enforced is not the one the
    // envelope was read as.
    final types = {for (final s in parsed) s.typ};
    if (types.length > 1) {
      throw AtSigningVerificationException(
          'an envelope is signed for one purpose, and this one is typed '
          '${types.map((t) => '"$t"').join(', ')} — refusing rather than '
          'enforcing one of them and being read as another');
    }
    return SignedEnvelope._(payload, parsed);
  }

  /// The wire form. Reproduces what was parsed byte for byte, because both
  /// halves were kept verbatim.
  Map<String, Object?> toJson() => {
        'payload': payloadB64,
        'signatures': [for (final s in signatures) s.toJson()],
      };

  /// Value equality over the wire bytes, which is what "the same envelope"
  /// means for a document whose whole identity is the characters that were
  /// signed. Two envelopes carrying the same payload under the same signature
  /// ARE the same envelope, whether one was parsed and the other signed.
  ///
  /// Worth having rather than leaving callers to compare a member: comparing
  /// one member of an envelope is how the signing chain's already-published
  /// check came to compare null against null.
  @override
  bool operator ==(Object other) =>
      other is SignedEnvelope &&
      other.payloadB64 == payloadB64 &&
      const ListEquality<EnvelopeSignature>()
          .equals(other.signatures, signatures);

  @override
  int get hashCode =>
      Object.hash(payloadB64, const ListEquality().hash(signatures));

  @override
  String toString() =>
      'SignedEnvelope(alg: ${signature.alg}, kid: $signerEnrollmentId, '
      'v: ${signature.version})';
}

/// One signing keypair and the algorithm it signs under. The public half is
/// what a verifier fetches from the signer's `_apsk`; the private half signs.
///
/// [algorithm] travels **inside** the keypair rather than beside it because a
/// key and an algorithm that arrive separately can disagree, and the signature
/// that results is produced by the wrong routine over the right bytes — it
/// verifies against nothing and says nothing about why. An enrollment holds
/// one of these per algorithm it still signs with.
class ApkamSigningKeys {
  final SigningAlgoType algorithm;
  final String publicKey;
  final String privateKey;

  const ApkamSigningKeys({
    required this.algorithm,
    required this.publicKey,
    required this.privateKey,
  });
}

/// Whether [signEnvelope] can produce a signature under [algo].
///
/// The writer's half of "a build cannot claim an algorithm it cannot run": a
/// keyfile can hold a signing key for an algorithm this build has no envelope
/// support for, and a signer skips it rather than throwing.
bool canSignEnvelopeWith(SigningAlgoType algo) => _joseAlgFor(algo) != null;

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
/// [type] says what the envelope is for and is stamped into every protected
/// header, where the signature covers it. It is required rather than defaulted
/// because a default would be whichever use was written first, and every other
/// use would then be signing under it silently — which is the state this
/// replaced. `EnvelopeSigning.wrapAndSign` defaults it for applications,
/// deliberately to a type no internal verifier accepts.
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
/// `{payload, signatures: [{protected, signature}]}`, **one entry per key in
/// [keys]**, in the order given — a signer emits one signature per active
/// signing key it holds, so a verifier can pick the strongest algorithm the
/// two of them share.
///
/// One payload, signed several times: the `payload` member is computed once
/// and every entry signs `<its own protected>.<that payload>`, which is what
/// makes the entries alternatives rather than a chain. Each carries its own
/// `alg`, all carry the same `kid`, and [SignedEnvelope.fromJson] refuses the
/// document if they do not — an envelope naming two signers is not this shape.
///
/// There is no hash to choose. `alg` names it: `RS256` **is** RSASSA-PKCS1-v1_5
/// with SHA-256, and ML-DSA signs the message directly. That is a property of
/// the shape rather than a restriction — the old envelope carried `hashingAlgo`
/// as its own unsigned member, so a hash had to be selected, policed, and
/// distrusted on the way back in.
SignedEnvelope signEnvelope(
  Object? payload, {
  required List<ApkamSigningKeys> keys,
  required EnvelopeType type,
  String? enrollmentId,
  Object? Function(Object? nonEncodable)? toEncodable,
}) {
  // The payload is always its JSON encoding, including a String payload.
  // That keeps decode unconditional: what comes out of base64url is JSON,
  // whatever went in. Encoded once, and every signature covers this same
  // text — re-encoding per key would let two entries sign different bytes.
  final payloadB64 = _base64UrlUnpadded(
      utf8.encode(jsonEncode(payload, toEncodable: toEncodable)));

  // Built through fromJson rather than a private constructor, so what a
  // signer produces has been through exactly the checks a reader applies —
  // including the refusals for an empty signatures array and for entries that
  // do not all name one signer.
  return SignedEnvelope.fromJson({
    'payload': payloadB64,
    'signatures': [
      for (final key in keys)
        _signatureOver(payloadB64,
            keys: key, type: type, enrollmentId: enrollmentId)
    ],
  });
}

/// One `{protected, signature}` entry: [keys] signing
/// `<its own protected>.<payloadB64>`.
Map<String, String> _signatureOver(
  String payloadB64, {
  required ApkamSigningKeys keys,
  required EnvelopeType type,
  String? enrollmentId,
}) {
  final SigningAlgoType signingAlgo = keys.algorithm;
  final String? alg = _joseAlgFor(signingAlgo);
  if (alg == null) {
    throw ArgumentError.value(
        signingAlgo, 'keys.algorithm', 'no envelope signing support');
  }

  final protectedB64 = _base64UrlUnpadded(utf8.encode(jsonEncode({
    'alg': alg,
    'typ': type.typ,
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
          signingAlgo, 'keys.algorithm', 'no envelope signing support');
  }

  return {
    'protected': protectedB64,
    'signature': _base64UrlUnpadded(signatureBytes),
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
  /// Every advertised key this build has a [SigningAlgoType] for, in published
  /// order — one for a bare value, and one per usable entry for an array.
  ///
  /// Retired entries are **in** this list. `_apsk` retains a key so that
  /// envelopes it already signed keep verifying, so a verifier that dropped one
  /// would refuse exactly the history retirement exists to preserve. Excluding
  /// them is the business of a caller choosing a key to sign with.
  final List<ApskSigningKey> keys;

  const ParsedApsk({required this.keys});

  /// The strongest advertised algorithm this build implements, by
  /// [SigningAlgoType.strongestFirst].
  ///
  /// Never the first entry: publication order is the *signer's* choice, so
  /// reading it as preference would let whoever wrote the advertisement pick
  /// the algorithm its envelopes are verified under.
  SigningAlgoType get signingAlgo => _strongest.alg;

  /// The key material for [signingAlgo]: the bare RSA string for
  /// [SigningAlgoType.rsa2048], or base64 of the raw ML-DSA-65 public key for
  /// [SigningAlgoType.mldsa65].
  String get publicKey => _strongest.pub;

  ApskSigningKey get _strongest =>
      keyFor(SigningAlgoType.strongestOf(keys.map((k) => k.alg))!)!;

  /// The advertised key for [algo], or null if this `_apsk` advertises none.
  ///
  /// A verifier resolves the algorithm first — from what the envelope and the
  /// advertisement have in common — and then asks for that key, rather than
  /// taking a key and requiring the envelope to match it.
  ///
  /// **The first of possibly several.** An advertisement can hold more than one
  /// key under one algorithm, so a verifier uses [keysFor] and tries them all;
  /// this answers the singular getters above, where "the" key means "the one to
  /// treat as current", which is the first an enrollment publishes.
  ApskSigningKey? keyFor(SigningAlgoType algo) => keysFor(algo).firstOrNull;

  /// Every advertised key for [algo], in published order.
  ///
  /// One algorithm can name several keys, and the case is not exotic: an
  /// enrollment that mints its own signing key keeps publishing the APKAM
  /// authentication key it used to sign with, because that is what verifies
  /// everything it signed earlier — and where both are ML-DSA, which is what a
  /// post-quantum-native enrollment holds, the two entries share an algorithm.
  /// A verifier that took only the first would refuse every envelope signed
  /// before the split.
  ///
  /// Trying each is **not** the algorithm fallback this signer forbids. That
  /// refusal is about algorithms: dropping to a weaker one after a failure hands the
  /// choice of algorithm to whoever wrote the envelope. The algorithm is
  /// already fixed here by the strongest-shared rule, and every key tried is
  /// one this signer published under it.
  List<ApskSigningKey> keysFor(SigningAlgoType algo) => [
        for (final key in keys)
          if (key.alg == algo) key
      ];
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
    // The bare legacy form: an RSA public key string, as published today. It
    // carries no kid — nothing in the bare form ever did — so one is derived,
    // which is what lets a caller treat both forms as the same list.
    return ParsedApsk(keys: [
      ApskSigningKey(
          kid: publicKeyKidOfBase64(trimmed),
          alg: SigningAlgoType.rsa2048,
          pub: trimmed)
    ]);
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
  // Every usable entry, not a choice made here: which one verifies an envelope
  // depends on what that envelope carries, and only the verifier knows it.
  return ParsedApsk(keys: advertised);
}

/// Verifies an envelope produced by [signEnvelope] against
/// [signerPublicKey] — the `_apsk` value the signer's enrollment published,
/// in either its bare or its array form.
///
/// **[expecting] is the caller's, never the envelope's.** The reader states
/// what it is verifying and an envelope typed anything else is refused, so a
/// signature made over one document cannot be presented as another — the
/// enrollment's signing key signs chain links, key packages, advertisements,
/// sealed secrets and whatever an application hands it, and the payloads of
/// two of those can be made to look alike. Dispatching on the envelope's own
/// `typ` instead would let the document pick which checks run.
///
/// **The key's own declaration is authoritative** over the envelope's `alg`
/// claim, matching PKAM's record-authoritative rule: the published key names
/// its algorithm and the envelope must agree. A lie about `alg` fails the verify — it can
/// never select a weaker routine than the published key calls for. The claim
/// is inside `protected`, so it is signed; the check is not about tamper but
/// about a signer and a published key disagreeing.
///
/// Throws [AtSigningVerificationException] if the signature does not check
/// out. Verification needs no keypair of its own: the public key is the whole
/// input, which is why this works on a client holding no keys at all.
///
/// **The strongest algorithm the envelope and the `_apsk` have in common is
/// the one verified, and its failure is the answer.** There is no fallback to
/// a weaker signature that happens to check out: that would hand the choice of
/// algorithm to whoever tampered with the envelope, and it would read as
/// success in every log. An envelope carrying a valid RSA signature beside a
/// corrupt ML-DSA one, against an `_apsk` advertising both, is refused.
Future<void> verifyEnvelope(
  SignedEnvelope envelope, {
  required String signerPublicKey,
  required EnvelopeType expecting,
}) async {
  final parsed = parseApskValue(signerPublicKey);

  // Resolve the algorithm from what the two documents share, then fetch the
  // key for it — the inversion. This used to take the one advertised key and
  // require the envelope to match it, whose diagnostic ("the published _apsk
  // is a <algo> key") states the singular assumption outright.
  final shared = <SigningAlgoType>{
    for (final k in parsed.keys)
      if (envelope.signatures.any((s) => s.alg == _joseAlgFor(k.alg))) k.alg
  };
  final SigningAlgoType? algo = SigningAlgoType.strongestOf(shared);
  if (algo == null) {
    throw AtSigningVerificationException(
        'the envelope is signed under ${envelope.signatures.map((s) => '"${s.alg}"').join(', ')} '
        'and the published _apsk advertises ${parsed.keys.map((k) => '"${k.alg.name}"').join(', ')} '
        '— no algorithm in common, so there is no signature here this key can '
        'check. Refusing rather than falling back to a key derived some other '
        'way: a signature means something only if the verifier used the key '
        'the signer published');
  }
  final candidates = parsed.keysFor(algo);
  final jose = _joseAlgFor(algo)!;
  final entry = envelope.signatures.firstWhere((s) => s.alg == jose);

  // Before the version, because "this document is not for you" is the more
  // useful answer about a document that is not for you.
  if (entry.typ != expecting.typ) {
    throw AtSigningVerificationException('the envelope is typed '
        '${entry.typ == null ? 'nothing' : '"${entry.typ}"'} and this reader '
        'verifies "${expecting.typ}" — refusing rather than '
        'checking a signature that was made over a document meant for '
        'something else. The signature may well be valid; what it attests to '
        'is not what is being asked here');
  }

  if (entry.version != envelopeVersion) {
    throw AtSigningVerificationException(
        'the protected header claims envelope version "${entry.version}", and '
        'this build signs and verifies $envelopeVersion — refusing rather '
        'than reading it as a shape it may not be');
  }

  // The signing input is the RECEIVED protected and payload strings verbatim,
  // never a re-encoding of anything decoded — which is what makes
  // canonicalisation irrelevant in this shape.
  final signingInput = utf8.encode('${entry.protected}.${envelope.payloadB64}');
  final signatureBytes = _base64UrlDecode(entry.signature, 'signature');

  // Every key advertised under the resolved algorithm, in published order.
  // The current one is first, so the ordinary envelope verifies on the first
  // attempt and the later keys are reached only by an envelope old enough to
  // have been signed by one of them.
  var ok = false;
  for (final key in candidates) {
    switch (algo) {
      case SigningAlgoType.mldsa65:
        ok = await MlDsa65PureDartAlgo().verifyBytes(
          signingInput,
          signature: signatureBytes,
          publicKey: base64Decode(key.pub),
        );
      case SigningAlgoType.rsa2048:
        // RS256 names its hash: RSASSA-PKCS1-v1_5 with SHA-256. Nothing
        // unsigned selects a routine in this shape.
        ok = RsaSigningAlgo(null, HashingAlgoType.sha256).verify(
          signingInput,
          signatureBytes,
          publicKey: key.pub,
        );
      default:
        // Unreachable: _joseAlgFor answered for this algorithm a few lines up,
        // and it answers for exactly the two below. Refusing rather than
        // asserting, because the two would have drifted for it to be reached.
        throw AtSigningVerificationException(
            'no verify routine for ${algo.name}, which this build claims to '
            'sign envelopes with');
    }
    if (ok) break;
  }
  if (!ok) {
    throw AtSigningVerificationException(
        'the envelope\'s ${algo.name} signature does not verify against any of '
        'the ${candidates.length} ${algo.name} key(s) the published _apsk '
        'advertises. Refusing outright — a weaker signature on the same '
        'envelope is not a second opinion, it is the algorithm being chosen by '
        'whoever wrote it');
  }
}
