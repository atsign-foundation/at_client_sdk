import 'dart:convert' show jsonEncode;

import 'package:at_auth/at_auth.dart'
    show ApskSigningKey, KeyEntryStatus, apskAdvertisement;
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/src/signing/envelope_signature.dart'
    show ApkamSigningKeys;
import 'package:at_commons/at_commons.dart' show AtKeyNotFoundException;

/// The `_apsk` entries an enrollment advertises: [signing], strongest first,
/// followed by the signing keys it has withdrawn from service.
///
/// Each [withdrawn] entry keeps the status it is given, a key already listed as
/// an active signer is not listed again, and the [authentication] keypair is
/// listed only while [signing] is empty.
///
/// Throws [AtKeyNotFoundException] when no entry is active — [signing] empty
/// and no [authentication] — since such a record names nothing this enrollment
/// signs with and is never published.
List<ApskSigningKey> apskEntries({
  required List<ApkamSigningKeys> signing,
  required List<
          ({
            SigningAlgoType algorithm,
            String publicKey,
            KeyEntryStatus status
          })>
      withdrawn,
  required ApkamSigningKeys? authentication,
}) {
  final entries = [
    for (final key in signing)
      ApskSigningKey.forPublicKey(alg: key.algorithm, pub: key.publicKey)
  ];

  // NOTE: this condition must match the fallback in ApkamSigning.signingKeys —
  // what signs and what is advertised cannot disagree.
  if (entries.isEmpty && authentication != null) {
    entries.add(ApskSigningKey.forPublicKey(
        alg: authentication.algorithm, pub: authentication.publicKey));
  }

  for (final key in withdrawn) {
    if (entries.any((entry) => entry.pub == key.publicKey)) continue;
    entries.add(ApskSigningKey.forPublicKey(
        alg: key.algorithm, pub: key.publicKey, status: key.status));
  }
  if (!entries.any((entry) => entry.offeredForNewOperations)) {
    throw AtKeyNotFoundException('an _apsk advertisement must name at least '
        'one active signing key, and this one names none, so it is not '
        'published');
  }
  return entries;
}

/// The bare `_apsk` value for [entries] — the public key itself — or null when
/// only the JSON array can express them.
///
/// A bare value says `rsa2048` by convention and can name one key, so a second
/// algorithm or a withdrawn entry forces the array.
String? bareApskValueOf(List<ApskSigningKey> entries) {
  if (entries.length == 1 &&
      entries.single.alg == SigningAlgoType.rsa2048 &&
      entries.single.offeredForNewOperations) {
    return entries.single.pub;
  }
  return null;
}

/// The `_apsk` value for [entries]: the bare public key when
/// [bareApskValueOf] can say it, and the JSON advertisement otherwise.
String apskValueOf(List<ApskSigningKey> entries) =>
    bareApskValueOf(entries) ?? jsonEncode(apskAdvertisement(keys: entries));
