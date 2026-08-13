import 'dart:convert' show jsonEncode;

import 'package:at_auth/at_auth.dart'
    show ApskSigningKey, KeyEntryStatus, apskAdvertisement;
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/src/signing/envelope_signature.dart'
    show ApkamSigningKeys;

/// The `_apsk` entries an enrollment advertises: the signing keys it signs
/// with now, followed by the APKAM authentication key it used to sign with.
///
/// One composer for both publishers. `_apsk` is one record whether the
/// atServer writes it from an `enroll:request`/`enroll:update` or a client
/// with no enrollment publishes it directly, and two compositions of one
/// record are two chances to disagree about what an enrollment can verify.
///
/// [signing] is what the enrollment holds of its own, strongest first — the
/// active entries. [authentication] is the APKAM authentication keypair, and
/// its treatment is the whole point of this function:
///
/// - **With no signing keys of its own**, an enrollment signs with the
///   authentication key, so that key is the one active entry. This is every
///   enrollment until something mints signing material, and the advertisement
///   is byte-for-byte what the single-key composer wrote.
/// - **Once it holds signing keys**, the authentication key stops signing and
///   is kept as a `retired` entry rather than dropped. Envelopes are stored
///   durably and verified whenever they are read, so withdrawing that key
///   retroactively unverifies everything signed before the split.
///
/// A key already listed as active is not listed again as retired. The two
/// halves can name one key — an enrollment whose signing material was filed
/// from its own authentication keypair — and one key described twice, once as
/// current and once as withdrawn, is a document a verifier has to choose
/// between with nothing to choose on.
List<ApskSigningKey> apskEntries({
  required List<ApkamSigningKeys> signing,
  required ApkamSigningKeys? authentication,
}) {
  final entries = [
    for (final key in signing)
      ApskSigningKey.forPublicKey(alg: key.algorithm, pub: key.publicKey)
  ];
  if (authentication == null) return entries;
  if (entries.any((entry) => entry.pub == authentication.publicKey)) {
    return entries;
  }
  return [
    ...entries,
    ApskSigningKey.forPublicKey(
        alg: authentication.algorithm,
        pub: authentication.publicKey,
        // Active when it is the only thing signing, retired once the
        // enrollment has keys of its own — the same key, in two eras.
        status:
            entries.isEmpty ? KeyEntryStatus.active : KeyEntryStatus.retired),
  ];
}

/// The `_apsk` value for [entries]: the bare public key when they are a single
/// active `rsa2048` key, and the JSON advertisement otherwise.
///
/// The bare form is kept for the one case everything deployed can read. Every
/// `_apsk` consumer that predates the array base64-decodes the value as an RSA
/// key, so publishing JSON where a bare key would do breaks them — fail-closed,
/// but service-breaking for anything already running.
///
/// Anything else has to be the array. A bare value says `rsa2048` by convention
/// and can name only one key, so it cannot express a second algorithm or a
/// retained entry at all.
String apskValueOf(List<ApskSigningKey> entries) {
  if (entries.length == 1 &&
      entries.single.alg == SigningAlgoType.rsa2048 &&
      entries.single.status == KeyEntryStatus.active) {
    return entries.single.pub;
  }
  return jsonEncode(apskAdvertisement(keys: entries));
}
