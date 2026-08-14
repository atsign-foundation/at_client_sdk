import 'dart:convert' show jsonEncode;

import 'package:at_auth/at_auth.dart'
    show ApskSigningKey, KeyEntryStatus, apskAdvertisement;
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/src/signing/envelope_signature.dart'
    show ApkamSigningKeys;

/// The `_apsk` entries an enrollment advertises: **the keys that sign for it
/// now, plus the signing keys it has retired.**
///
/// One composer for both publishers. `_apsk` is one record whether the
/// atServer writes it from an `enroll:request`/`enroll:update` or a client
/// with no enrollment publishes it directly, and two compositions of one
/// record are two chances to disagree about what an enrollment can verify.
///
/// [signing] is what the enrollment holds of its own, strongest first — the
/// active entries. [retired] is the public half of every signing key it has
/// withdrawn, which stays advertised because envelopes are stored durably and
/// verified whenever they are read: a key is retained for **what it signed**.
///
/// [authentication] is the APKAM authentication keypair, and its treatment is
/// the whole point of this function:
///
/// - **With no signing keys of its own**, an enrollment signs with the
///   authentication key, so that key is the one active entry. The
///   advertisement is byte-for-byte what the single-key composer wrote, which
///   is what every deployed reader parses.
/// - **Once it holds signing keys**, the authentication key never signed
///   anything durable and is **not advertised at all** — neither active nor
///   retained.
///
/// ⚠️ **The authentication key is never retained, and that asymmetry is the
/// design rather than an oversight.** An enrollment that holds signing keys
/// held them from birth, so its authentication key signs nothing that outlives
/// the transition; retaining it would advertise a key with nothing to verify.
/// This rests on a deployment premise recorded with the ruling — that no
/// long-lived auth-key-signed material is extant — and if that turns out to be
/// false the ruling reopens rather than this function growing a special case.
///
/// A key already listed as an active signer is not listed again as retired.
/// One key described twice, once as current and once as withdrawn, is a
/// document a verifier has to choose between with nothing to choose on.
List<ApskSigningKey> apskEntries({
  required List<ApkamSigningKeys> signing,
  required List<({SigningAlgoType algorithm, String publicKey})> retired,
  required ApkamSigningKeys? authentication,
}) {
  final entries = [
    for (final key in signing)
      ApskSigningKey.forPublicKey(alg: key.algorithm, pub: key.publicKey)
  ];

  // The authentication key is the signer exactly while the enrollment holds no
  // active signing key of its own — the same condition ApkamSigning.signingKeys
  // falls back on. Advertising it here and falling back there are one rule, so
  // what signs and what is advertised cannot disagree.
  if (entries.isEmpty && authentication != null) {
    entries.add(ApskSigningKey.forPublicKey(
        alg: authentication.algorithm, pub: authentication.publicKey));
  }

  for (final key in retired) {
    if (entries.any((entry) => entry.pub == key.publicKey)) continue;
    entries.add(ApskSigningKey.forPublicKey(
        alg: key.algorithm,
        pub: key.publicKey,
        status: KeyEntryStatus.retired));
  }
  return entries;
}

/// The **bare** `_apsk` value for [entries] — the public key itself — or null
/// when they cannot be said that way and the array is the only form.
///
/// The bare form is kept for the one case everything deployed can read. Every
/// `_apsk` consumer that predates the array base64-decodes the value as an RSA
/// key, so publishing JSON where a bare key would do breaks them — fail-closed,
/// but service-breaking for anything already running.
///
/// Anything else has to be the array. A bare value says `rsa2048` by convention
/// and can name only one key, so it cannot express a second algorithm or a
/// retained entry at all.
///
/// The rule lives here, once, because two publishers need it and they publish
/// one record. A client with no enrollment writes the value itself
/// ([apskValueOf]); an enrolled client sends `enroll:update`, where the choice
/// is which *field* carries the advertisement — `apskLegacy` for the bare
/// string, `apsk` for the array — and the two are mutually exclusive. A second
/// copy of the rule is a second chance to describe one record two ways.
String? bareApskValueOf(List<ApskSigningKey> entries) {
  if (entries.length == 1 &&
      entries.single.alg == SigningAlgoType.rsa2048 &&
      entries.single.status == KeyEntryStatus.active) {
    return entries.single.pub;
  }
  return null;
}

/// The `_apsk` value for [entries]: the bare public key when
/// [bareApskValueOf] can say it, and the JSON advertisement otherwise.
String apskValueOf(List<ApskSigningKey> entries) =>
    bareApskValueOf(entries) ?? jsonEncode(apskAdvertisement(keys: entries));
