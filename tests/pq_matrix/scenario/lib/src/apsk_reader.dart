// `EnvelopeSigning` carries at_client's `@experimental` marker in both builds,
// and reaching for it anyway is the point rather than a compromise. UC-G1.14's
// claim is about what a DEPLOYED reader makes of a rollout-1 `_apsk`, and only
// that reader's own code path can settle it — the marker warns app authors
// that the API may move, which is a different question from whether this
// harness may call the exact version it pins.
// ignore_for_file: experimental_member_use

import 'package:at_client/at_client.dart' show AtClient;
// ignore: implementation_imports
import 'package:at_client/src/mixins/apkam_signing.dart' show ApkamSigning;
// ignore: implementation_imports
import 'package:at_client/src/mixins/envelope_signing.dart'
    show EnvelopeSigning;
import 'package:at_utils/at_utils.dart' show AtSignLogger;
import 'package:crypton/crypton.dart' show RSAPublicKey;

/// What a **released** at_client makes of an enrollment's `_apsk` — the
/// measurement UC-G1.14 turns on.
///
/// Reached through at_client's `EnvelopeSigning.getApkamPublicKey` rather than
/// a lookup written here, and the `src/` import is the point rather than a
/// shortcut. The property under test is that *a deployed peer* can still read
/// a rollout-1 sender's advertisement, and only the deployed build's own code
/// path can settle that — a fetch reimplemented in this file would test the
/// reimplementation.
///
/// `RSAPublicKey.fromString` is the call at_chops makes when it verifies a
/// pkam signature, so `rsa: true` means the value is one a released verifier
/// could actually have used — not merely that it looked like base64.
///
/// Never throws: every outcome is reported, because "the released reader threw"
/// is the result this row exists to detect and an exception here would be
/// indistinguishable from the harness failing.
Future<Map<String, Object?>> readPeerApskAsReleasedReader(
    AtClient client, String peerAtSign, String peerEnrollmentId) async {
  final reader = _ReleasedApskReader(client);
  String value;
  try {
    // The sender's own enrollment id — `primary` when its keyfile names
    // none. A released reader can read any enrollment's record given the
    // id; what it cannot do is guess one, which is why the caller threads it.
    value = await reader.getApkamPublicKey(peerAtSign, peerEnrollmentId);
  } on Object catch (e) {
    return {'fetched': false, 'rsa': false, 'error': '$e'};
  }

  try {
    RSAPublicKey.fromString(value);
    return {'fetched': true, 'rsa': true, 'value': value};
  } on Object catch (e) {
    return {'fetched': true, 'rsa': false, 'value': value, 'error': '$e'};
  }
}

/// The smallest thing that can hold [EnvelopeSigning].
///
/// Its three members are declared identically in at_client 3.14.0 and in this
/// tree — checked, because a mixin member present in only one of them would
/// make this file uncompilable on the released arm.
class _ReleasedApskReader with ApkamSigning, EnvelopeSigning {
  _ReleasedApskReader(this.atClient);

  @override
  final AtClient atClient;

  @override
  final AtSignLogger logger = AtSignLogger('pqReleasedApskReader');

  /// Null: caching is what would make a second read return the first read's
  /// answer, and each read wants the record as it stands now.
  @override
  final ({Duration cacheExpiry, bool resetOnLookup})? publicKeyCacheSettings =
      null;
}
