import 'dart:convert' show base64Decode;
import 'dart:typed_data' show Uint8List;

import 'package:at_auth/src/enroll/key_entry_status.dart'
    show KeyEntryStatus;
import 'package:at_chops/at_chops.dart' show SHA256HashingAlgo, SigningAlgoType;

/// The `_apsk` value an enrollment publishes: the signing keys that verify
/// what it signs.
///
/// Composed here rather than by the atServer. The server stores this map
/// verbatim on the enrollment record and writes its JSON encoding to
/// `public:_apsk.<enrollmentId>.a.__e@<atSign>` when the enrollment is
/// approved; it never composes one and publishes nothing when a request
/// carries none. PKAM verification reads the enrollment record, so the server
/// has no use for this key and no business knowing how a signing key is
/// spelled — which is what lets a new signing-key shape ship without a server
/// release.
///
/// The entry spelling is the key package's (`PackageKey` in at_client), so
/// that one vocabulary covers every "list of keys with algorithms" in the
/// protocol. `keys` is an array from the
/// outset even though an enrollment holds exactly one signing key today: a
/// second algorithm's key is added beside the first rather than replacing it,
/// because envelopes are stored durably and verified later, so a key that
/// stops being used must still be able to verify what it already signed.
///
/// ```json
/// {"v": 1, "keys": [
///   {"kid": "…", "use": "sign", "alg": "mldsa65", "pub": "…"}
/// ]}
/// ```
Map<String, dynamic> apskAdvertisement({
  required String apkamPublicKey,
  required SigningAlgoType signingAlgo,
}) =>
    {
      'v': 1,
      'keys': [
        {
          'kid': publicKeyKidOfBase64(apkamPublicKey),
          'use': 'sign',
          'alg': signingAlgo.name,
          'pub': apkamPublicKey,
        }
      ],
    };

/// One signing key read back out of an `_apsk` advertisement.
class ApskSigningKey {
  final String kid;
  final SigningAlgoType alg;
  final String pub;

  /// Whether this key still signs — see [KeyEntryStatus].
  ///
  /// A retired entry is **kept** rather than skipped, because the keys an
  /// enrollment has retired are exactly the ones its stored envelopes were
  /// signed with, and this list is what verifies them. What a caller must not
  /// do is choose a retired key to sign something new with.
  final KeyEntryStatus status;

  const ApskSigningKey({
    required this.kid,
    required this.alg,
    required this.pub,
    this.status = KeyEntryStatus.active,
  });
}

/// The signing keys an [apskAdvertisement] advertises, in published order.
///
/// Entries this build cannot use are skipped — a `use` other than `sign`, or
/// an `alg` with no [SigningAlgoType] — which is what lets an enrollment
/// advertise a new algorithm beside an old one without breaking readers that
/// predate it. An advertisement whose entries are *all* skipped therefore
/// comes back empty, and a caller must refuse outright rather than fall back
/// to a key it derived some other way: the whole point of the signature is
/// that the verifier used the key the signer published.
///
/// A `retired` entry is **not** skipped — it is returned with its
/// [ApskSigningKey.status] — because this list is what verifies stored
/// envelopes, and the keys an enrollment has retired are precisely the ones
/// that signed its older ones. Filtering here would retroactively unverify
/// them. It is a caller *choosing a key to sign with* that must exclude them,
/// and that caller does not exist yet.
///
/// `kid` is required, like every other field: an entry without one is skipped.
/// The atServer stores this document verbatim and forms no opinion on it, so a
/// writer that omits `kid` produces an advertisement every reader treats as
/// empty — and then refuses outright, rather than half-reading it.
List<ApskSigningKey> apskSigningKeys(Map<String, dynamic> advertisement) {
  final keys = advertisement['keys'];
  if (keys is! List) return const [];
  final result = <ApskSigningKey>[];
  for (final entry in keys) {
    if (entry is! Map) continue;
    final kid = entry['kid'];
    final use = entry['use'];
    final alg = entry['alg'];
    final pub = entry['pub'];
    if (kid is! String || use is! String || alg is! String || pub is! String) {
      continue;
    }
    if (use != 'sign') continue;
    final algo = SigningAlgoType.values.where((a) => a.name == alg).firstOrNull;
    if (algo == null) continue;
    result.add(ApskSigningKey(
        kid: kid,
        alg: algo,
        pub: pub,
        status: KeyEntryStatus.fromWire(entry['status'])));
  }
  return result;
}

/// A short identifier for a public key: the first 8 bytes, hex-encoded, of the
/// SHA-256 of the key's **raw bytes**.
///
/// The one definition in the tree, for every record that advertises keys —
/// `_apsk`, a key package, an nskey advertisement. A kid computed two ways is
/// a verification failure with nothing to say for itself: both sides compile,
/// and the mismatch surfaces only as an envelope that will not verify, or as a
/// sender addressing a kid nobody is listening on.
///
/// Over the key material, not over its encoding. There were two of these and
/// they disagreed about exactly that: this one hashed the base64 **text** as
/// published while the nskey side hashed the decoded bytes, and both dartdocs
/// described themselves as "SHA-256 of the public key". The text and the
/// material are the same thing only for a key whose published form IS its
/// material, so the two agreed for nothing.
String publicKeyKid(Uint8List publicKey) =>
    SHA256HashingAlgo().hash(publicKey).substring(0, 16);

/// [publicKeyKid] for a key held as base64, which is how every advertisement
/// carries one. Decoding here rather than at each call site is what keeps the
/// preimage the material rather than the encoding.
String publicKeyKidOfBase64(String pub) => publicKeyKid(base64Decode(pub));
