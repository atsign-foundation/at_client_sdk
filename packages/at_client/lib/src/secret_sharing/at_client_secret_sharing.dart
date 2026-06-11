import 'package:at_client/at_client.dart' show AtClient;
import 'package:at_client/src/mixins/apkam_signing.dart';
import 'package:at_client/src/mixins/envelope_signing.dart';
import 'package:at_client/src/secret_sharing/pairwise_client_registration.dart';
import 'package:at_client/src/secret_sharing/pairwise_secret_sharing.dart';
import 'package:at_utils/at_utils.dart' show AtSignLogger;

/// Ready-made composition of the same-atSign secret-sharing mixins, for
/// apps that don't want to mix them into their own classes.
///
/// ```dart
/// final sharing = AtClientSecretSharing(atClient);
/// await sharing.registerClient();
/// await sharing.startListening();
/// sharing.receivedSecrets.listen((r) => ...);
/// ```
class AtClientSecretSharing
    with
        ApkamSigning,
        EnvelopeSigning,
        PairwiseClientRegistration,
        PairwiseSecretSharing {
  @override
  final AtClient atClient;

  @override
  final AtSignLogger logger = AtSignLogger('AtClientSecretSharing');

  @override
  final ({Duration cacheExpiry, bool resetOnLookup})? publicKeyCacheSettings;

  AtClientSecretSharing(
    this.atClient, {
    this.publicKeyCacheSettings = const (
      cacheExpiry: Duration(minutes: 5),
      resetOnLookup: true,
    ),
  });
}
