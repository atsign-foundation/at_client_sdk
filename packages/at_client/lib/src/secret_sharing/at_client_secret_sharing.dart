import 'package:at_client/at_client.dart' show AtClient;
import 'package:at_client/src/mixins/apkam_signing.dart';
import 'package:at_client/src/mixins/envelope_signing.dart';
import 'package:at_client/src/secret_sharing/pairwise_client_registration.dart';
import 'package:at_client/src/secret_sharing/pairwise_secret_sharing.dart';
import 'package:at_client/src/secret_sharing/secret_store.dart';
import 'package:at_utils/at_utils.dart' show AtSignLogger;

/// Ready-made composition of the same-atSign secret-sharing mixins, for
/// apps that don't want to mix them into their own classes.
///
/// ```dart
/// final sharing = AtClientSecretSharing.forClient(atClient);
/// await sharing.registerClient(namespaces: ['myapp']);
/// await sharing.startListening();
/// sharing.receivedSecrets.listen((r) => ...);
/// ```
///
/// Prefer [AtClientSecretSharing.forClient] over the plain constructor: a
/// secret-sharing instance IS a client identity (clientId, keypair,
/// published bundle, envelope listener), and an AtClient must have exactly
/// one — if the app and an SDK-internal consumer (e.g. a future
/// CryptoProvider that distributes its keys as secrets) each constructed
/// their own, the atSign's roster would show two clients per process and
/// every secret would be shared twice.
class AtClientSecretSharing
    with
        ApkamSigning,
        EnvelopeSigning,
        PairwiseClientRegistration,
        PairwiseSecretSharing {
  static final Expando<AtClientSecretSharing> _instances =
      Expando('AtClientSecretSharing');

  /// The shared secret-sharing instance for [atClient], created on first
  /// call. [persistence] and [publicKeyCacheSettings] take effect only on
  /// the creating call; later calls return the cached instance unchanged
  /// (one [SecretStorePersistence] per client — see
  /// [SecretStore.persistence]).
  factory AtClientSecretSharing.forClient(
    AtClient atClient, {
    SecretStorePersistence? persistence,
    ({
      Duration cacheExpiry,
      bool resetOnLookup
    })? publicKeyCacheSettings = const (
      cacheExpiry: Duration(minutes: 5),
      resetOnLookup: true,
    ),
  }) {
    var instance = _instances[atClient];
    if (instance == null) {
      instance = AtClientSecretSharing(atClient,
          publicKeyCacheSettings: publicKeyCacheSettings);
      instance.secretStore.persistence = persistence;
      _instances[atClient] = instance;
    }
    return instance;
  }

  @override
  final AtClient atClient;

  @override
  final AtSignLogger logger = AtSignLogger('AtClientSecretSharing');

  @override
  final ({Duration cacheExpiry, bool resetOnLookup})? publicKeyCacheSettings;

  /// Direct construction creates an independent instance with its own
  /// client identity. Use [forClient] unless that is what you want (tests,
  /// custom compositions).
  AtClientSecretSharing(
    this.atClient, {
    this.publicKeyCacheSettings = const (
      cacheExpiry: Duration(minutes: 5),
      resetOnLookup: true,
    ),
  });
}
