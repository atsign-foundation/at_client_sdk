import 'dart:convert' show utf8;

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
          'kid': apskKid(apkamPublicKey),
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

  const ApskSigningKey(
      {required this.kid, required this.alg, required this.pub});
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
    result.add(ApskSigningKey(kid: kid, alg: algo, pub: pub));
  }
  return result;
}

/// A short identifier for a public key: the first 8 bytes, hex-encoded, of the
/// SHA-256 of [pub].
///
/// The one definition in the tree — `PackageKey.computeKid` calls it — because
/// a kid computed two ways is a verification failure with nothing to say for
/// itself: both sides compile, and the mismatch surfaces only as an envelope
/// that will not verify.
///
/// Hashes the key **string** as published, not decoded key bytes. Those are
/// the same thing only for keys whose published form is their material.
String apskKid(String pub) =>
    SHA256HashingAlgo().hash(utf8.encode(pub)).substring(0, 16);
