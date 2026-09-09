// `EnvelopeSigning` carries at_client's `@experimental` marker in both builds.
// UC-G1.14's claim is about what a DEPLOYED reader makes of a rollout-1
// `_apsk`, and only that reader's own code path can settle it.
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
/// Never throws: the returned map reports every outcome, `fetched` for the
/// read through at_client's own `EnvelopeSigning.getApkamPublicKey` and `rsa`
/// for whether `RSAPublicKey.fromString` then accepted the value.
Future<Map<String, Object?>> readPeerApskAsReleasedReader(
    AtClient client, String peerAtSign, String peerEnrollmentId) async {
  final reader = _ReleasedApskReader(client);
  String value;
  try {
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
/// tree; a mixin member present in only one of them would make this file
/// uncompilable on the released arm.
class _ReleasedApskReader with ApkamSigning, EnvelopeSigning {
  _ReleasedApskReader(this.atClient);

  @override
  final AtClient atClient;

  @override
  final AtSignLogger logger = AtSignLogger('pqReleasedApskReader');

  /// Null so that each read fetches the record as it stands rather than
  /// returning an earlier read's answer.
  @override
  final ({Duration cacheExpiry, bool resetOnLookup})? publicKeyCacheSettings =
      null;
}
