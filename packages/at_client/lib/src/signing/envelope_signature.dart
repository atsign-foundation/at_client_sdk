/// Signing and verification of the JSON envelopes clients exchange, given the
/// key material as an argument.
///
/// These are functions rather than methods on a key-holding object: key state
/// belongs in `AtKeys`, and a key package riding `enroll:request` is signed by
/// an APKAM keypair that lives only between being generated and being sent —
/// before there is an approved enrollment or an `AtClient` to reach through.
library;

import 'dart:convert'
    show base64, base64Decode, base64Url, jsonDecode, jsonEncode, utf8;
import 'dart:typed_data' show Uint8List;

import 'package:at_auth/at_auth.dart'
    show ApskSigningKey, apskSigningKeys, publicKeyKidOfBase64;
import 'package:collection/collection.dart' show ListEquality;
import 'package:at_chops/at_chops.dart'
    show MlDsa65PureDartAlgo, RsaSignatureAlgo, SigningAlgoType;
import 'package:at_commons/at_commons.dart'
    show AtSigningVerificationException, EnrollmentConstants;

/// `public:_apsk.<enrollmentId>.a.__e@<atSign>` — where an enrollment's
/// APKAM public signing key lives, and the one record its own connection may
/// write.
///
/// The atServer mints the record at approval, so the spelling is a
/// cross-implementation contract; it is pinned in
/// `test/wire_literal_pins_test.dart`.
String apskUri(String atSign, String enrollmentId) =>
    'public:_apsk.$enrollmentId.${EnrollmentConstants.perEnrollmentApproved}'
    '$atSign';

/// The envelope's payload version, carried inside each protected header where
/// the signature covers it.
///
/// It sits in `protected` rather than at the top level because a version
/// outside the signature is a claim an attacker can edit, which no verifier
/// could rely on.
const int envelopeVersion = 1;

/// What an envelope was signed for, stamped into the protected header as the
/// JOSE `typ` and required by the verifier that reads it.
///
/// The verifier is handed the type it expects rather than dispatching on the
/// envelope's own, and the wire values are frozen — they are pinned in
/// `test/wire_literal_pins_test.dart`.
enum EnvelopeType {
  /// Whatever an application passes to `EnvelopeSigning.wrapAndSign`.
  ///
  /// The default, and deliberately a type no internal verifier accepts: an app
  /// that signs data someone else influenced cannot be walked into producing a
  /// chain link, a key package or an advertisement, whatever the payload it was
  /// handed looks like.
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

  final String typ;
}

/// The JOSE `alg` names the JWS shape signs under. RSA is `RS256` exactly:
/// nothing produces an RSA envelope under any hash but SHA-256.
const String _jwsAlgRs256 = 'RS256';
const String _jwsAlgMlDsa65 = 'ML-DSA-65';

/// The JOSE `alg` [algo] signs under, or null when this build produces no
/// envelope signature for it.
///
/// One mapping for both directions: the signer choosing what to stamp, and the
/// verifier matching an `_apsk` entry against an envelope entry.
String? _joseAlgFor(SigningAlgoType algo) => switch (algo) {
      SigningAlgoType.rsa2048 => _jwsAlgRs256,
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
/// Both halves are kept as the base64url text they arrived as, never decoded
/// and re-encoded, because the signing input is those exact characters joined
/// by a dot.
class EnvelopeSignature {
  /// The protected header, base64url, verbatim.
  final String protected;

  /// The signature, base64url, verbatim.
  final String signature;

  /// The decoded protected header; an entry whose header cannot be read is
  /// refused at construction.
  final Map<String, Object?> header;

  const EnvelopeSignature._(this.protected, this.signature, this.header);

  /// The JOSE algorithm this signature is under (`RS256`, `ML-DSA-65`).
  /// Null when the header names none, which [verifyEnvelope] refuses.
  String? get alg => header['alg'] is String ? header['alg'] as String : null;

  /// The signing key this signature was made with — the entry to look up in
  /// the signer's `_apsk`.
  ///
  /// A kid is `SHA256(publicKey)` truncated and is not covered by the
  /// signature: a tampered one narrows to the wrong key or to none, and the
  /// signature then fails on its own.
  String? get kid => header['kid'] is String ? header['kid'] as String : null;

  /// The signer's enrollment-id claim, or null when it makes none — a
  /// connection holding no enrollment id publishes at `_apsk.primary`.
  ///
  /// [enid] says whose advertisement to fetch, [kid] which entry of it to use.
  String? get enid =>
      header['enid'] is String ? header['enid'] as String : null;

  /// What this signature was made for — the [EnvelopeType.typ] the signer
  /// stamped. Null when the header names none, which [verifyEnvelope] refuses
  /// rather than assuming a purpose.
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

  /// The wire form.
  Map<String, Object?> toJson() =>
      {'protected': protected, 'signature': signature};

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
/// [fromJson] validates structure — a string payload, a non-empty `signatures`
/// array, each entry carrying a readable protected header — and checks neither
/// the version, which [verifyEnvelope] answers, nor the payload.
class SignedEnvelope {
  /// The payload, base64url, verbatim — see [EnvelopeSignature.protected] for
  /// why it is never held decoded.
  final String payloadB64;

  /// One entry per signing key of one signer, in the order the signer listed
  /// them — every entry over the same payload, each under its own algorithm,
  /// all naming the same signer.
  ///
  /// A verifier takes the strongest algorithm this envelope and the signer's
  /// published `_apsk` share, so an envelope carrying two is readable both by
  /// a peer that implements the stronger one and by a peer that does not.
  final List<EnvelopeSignature> signatures;

  const SignedEnvelope._(this.payloadB64, this.signatures);

  /// The first entry, for the callers that want *an* entry — the payload's
  /// encoding and the signer claim are the same in all of them.
  ///
  /// Not the entry a verifier checks: [verifyEnvelope] resolves that from the
  /// algorithms the envelope and the signer's `_apsk` share, taking the
  /// strongest, since taking the first would let the signer's ordering decide.
  EnvelopeSignature get signature => signatures.first;

  /// The signer's enrollment-id claim, or null when the envelope makes none —
  /// a key package signed at `enroll:request` time has no id to stamp, and its
  /// authority is the record binding it to the request that created it.
  ///
  /// The claim is under the signature, so it cannot be edited in flight, but
  /// what makes it true is the signature verifying against the named
  /// enrollment's own `_apsk`.
  String? get signerEnrollmentId => signature.enid;

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
    // NOTE: over `enid`, not `kid` — an envelope signed under two algorithms
    // carries a different key per entry by construction. What must not differ
    // is the signer, or the entry that verifies and the entry a caller reads
    // `signerEnrollmentId` from can be different entries.
    final enids = {for (final s in parsed) s.enid};
    if (enids.length > 1) {
      throw AtSigningVerificationException(
          'an envelope carries one signer\'s signatures, and this one names '
          '${enids.map((e) => '"$e"').join(', ')} — refusing rather than '
          'verifying under one of them and reporting another');
    }
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

  /// Value equality over the wire bytes: two envelopes carrying the same
  /// payload under the same signature are the same envelope, whether one was
  /// parsed and the other signed.
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

/// One signing keypair and the algorithm it signs under — the public half is
/// what a verifier fetches from the signer's `_apsk`, the private half signs.
///
/// [algorithm] travels inside the keypair rather than beside it because a key
/// and an algorithm that arrive separately can disagree, producing a signature
/// made by the wrong routine over the right bytes.
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
/// A keyfile can hold a signing key for an algorithm this build has no
/// envelope support for; a signer skips it rather than throwing.
bool canSignEnvelopeWith(SigningAlgoType algo) => _joseAlgFor(algo) != null;

/// The exact text that is signed and verified: a String payload as-is,
/// anything else as its JSON encoding.
///
/// Verification re-derives this from the decoded envelope, which is stable
/// because Dart maps preserve insertion order through a
/// `jsonEncode`/`jsonDecode` round trip.
String signableTextOf(
  Object? payload, {
  Object? Function(Object? nonEncodable)? toEncodable,
}) {
  if (payload is String) {
    return payload;
  }
  return jsonEncode(payload, toEncodable: toEncodable);
}

/// Wraps [payload] in an RFC 7515 general JSON serialization envelope, one
/// signature entry per key in [keys], verifiable by [verifyEnvelope].
///
/// [type] is stamped into every protected header, where the signature covers
/// it, and [enrollmentId] is stamped only when supplied — a signer with no
/// enrollment yet omits the claim rather than guessing one.
SignedEnvelope signEnvelope(
  Object? payload, {
  required List<ApkamSigningKeys> keys,
  required EnvelopeType type,
  String? enrollmentId,
  Object? Function(Object? nonEncodable)? toEncodable,
}) {
  // NOTE: encoded once, so every signature covers the same text — re-encoding
  // per key would let two entries sign different bytes.
  final payloadB64 = _base64UrlUnpadded(
      utf8.encode(jsonEncode(payload, toEncodable: toEncodable)));

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
    'kid': publicKeyKidOfBase64(keys.publicKey),
    if (enrollmentId != null) 'enid': enrollmentId,
    'v': envelopeVersion,
  })));
  final signingInput = utf8.encode('$protectedB64.$payloadB64');

  final Uint8List signatureBytes;
  switch (signingAlgo) {
    case SigningAlgoType.rsa2048:
      signatureBytes = RsaSignatureAlgo.rsa2048().signBytesSync(signingInput,
          secretKey: base64Decode(keys.privateKey));
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

/// A parsed `_apsk` value: which algorithm each key is for, and the key itself.
///
/// The published record is either a bare RSA public key string, read as
/// [SigningAlgoType.rsa2048], or the `{"v": 1, "keys": [...]}` array that
/// `apskAdvertisement` in at_auth writes and parses — the only form that can
/// carry a second algorithm's key beside the first.
class ParsedApsk {
  /// Every advertised key this build has a [SigningAlgoType] for, in published
  /// order — one for a bare value, and one per usable entry for an array.
  ///
  /// Retired entries are in this list, because `_apsk` retains a key so that
  /// envelopes it already signed keep verifying.
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
  /// The first of possibly several — the one to treat as current, since an
  /// advertisement can hold more than one key under one algorithm; a verifier
  /// uses [keysFor].
  ApskSigningKey? keyFor(SigningAlgoType algo) => keysFor(algo).firstOrNull;

  /// Every advertised key for [algo], in published order.
  ///
  /// One algorithm can name several keys: a rotation keeps the superseded
  /// generation advertised as `retired` beside the successor it mints, so a
  /// verifier that took only the first would refuse every envelope signed
  /// before the rotation.
  List<ApskSigningKey> keysFor(SigningAlgoType algo) => [
        for (final key in keys)
          if (key.alg == algo) key
      ];
}

/// Parses a fetched `_apsk` value, bare or array.
///
/// Throws [AtSigningVerificationException] when the value names no algorithm
/// this build has code for, rather than falling back to a key derived some
/// other way: a signature means something only if the verifier used the key
/// the signer published.
ParsedApsk parseApskValue(String value) {
  final trimmed = value.trim();
  if (!trimmed.startsWith('{')) {
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

  // NOTE: an entry whose status this build does not understand is dropped here
  // rather than in apskSigningKeys, which also feeds the writers — they must
  // republish a token they cannot read rather than delete it. Only active and
  // retired vouch for what a key already signed; anything else may be an owner
  // disowning the key, and verifying with it is unrecoverable.
  final advertised = apskSigningKeys(advertisement)
      .where((k) => k.vouchesForPastOperations)
      .toList();
  if (advertised.isEmpty) {
    throw AtSigningVerificationException(
        'the _apsk advertises no signing key this build can verify with — '
        'every entry names an algorithm or a status it does not understand. '
        'Refusing to verify rather than guessing');
  }
  return ParsedApsk(keys: advertised);
}

/// Verifies an envelope produced by [signEnvelope] against [signerPublicKey] —
/// the `_apsk` value the signer's enrollment published, bare or array —
/// throwing [AtSigningVerificationException] if it does not check out.
///
/// [expecting] is the caller's type, never the envelope's, and the algorithm
/// verified is the strongest the envelope and the `_apsk` have in common — its
/// failure is the answer, never a fallback to a weaker signature that happens
/// to check out.
Future<void> verifyEnvelope(
  SignedEnvelope envelope, {
  required String signerPublicKey,
  required EnvelopeType expecting,
}) async {
  final parsed = parseApskValue(signerPublicKey);

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

  // NOTE: the signing input is the received protected and payload strings
  // verbatim, never a re-encoding of anything decoded.
  final signingInput = utf8.encode('${entry.protected}.${envelope.payloadB64}');
  final signatureBytes = _base64UrlDecode(entry.signature, 'signature');

  final String? namedKid = entry.kid;
  if (namedKid == null) {
    throw AtSigningVerificationException(
        'the envelope\'s ${algo.name} signature names no key in its protected '
        'header, and this build resolves the key by name — refusing rather '
        'than trying every ${algo.name} key the published _apsk advertises, '
        'which cannot tell a wrong key from a bad signature');
  }
  ApskSigningKey? named;
  for (final k in candidates) {
    if (k.kid == namedKid) {
      named = k;
      break;
    }
  }
  if (named == null) {
    throw AtSigningVerificationException(
        'the envelope\'s ${algo.name} signature names key "$namedKid", and the '
        'published _apsk advertises '
        '${candidates.map((k) => '"${k.kid}"').join(', ')} under ${algo.name} '
        '— refusing, and naming the key it asked for: a key the advertisement '
        'does not carry is a different failure from a signature that does not '
        'verify');
  }
  var ok = false;
  {
    final key = named;
    switch (algo) {
      case SigningAlgoType.mldsa65:
        ok = await MlDsa65PureDartAlgo().verifyBytes(
          signingInput,
          signature: signatureBytes,
          publicKey: base64Decode(key.pub),
        );
      case SigningAlgoType.rsa2048:
        ok = await RsaSignatureAlgo.rsa2048().verifyBytes(
          signingInput,
          signature: signatureBytes,
          publicKey: base64Decode(key.pub),
        );
      default:
        throw AtSigningVerificationException(
            'no verify routine for ${algo.name}, which this build claims to '
            'sign envelopes with');
    }
  }
  if (!ok) {
    throw AtSigningVerificationException(
        'the envelope\'s ${algo.name} signature does not verify against key '
        '"$namedKid", which the published _apsk advertises and which the '
        'signature itself names. Refusing outright — a weaker signature on the '
        'same envelope is not a second opinion, it is the algorithm being '
        'chosen by whoever wrote it');
  }
}
