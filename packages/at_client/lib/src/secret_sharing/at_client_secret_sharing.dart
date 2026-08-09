import 'package:at_auth/at_auth.dart' show AtEnrollment;
import 'package:at_client/at_client.dart' show AtClient;
import 'package:at_client/src/mixins/apkam_signing.dart';
import 'package:at_client/src/mixins/envelope_signing.dart';
import 'package:at_client/src/secret_sharing/key_package_registration.dart';
import 'package:at_client/src/secret_sharing/pairwise_secret_sharing.dart';
import 'package:at_client/src/secret_sharing/secret_store.dart';
import 'package:at_client/src/service/enrollment_service_impl.dart'
    show EnrollmentServiceImpl;
import 'package:at_utils/at_utils.dart' show AtSignLogger;
import 'package:meta/meta.dart' show experimental;

/// Ready-made composition of the same-atSign secret-sharing mixins, for
/// apps that don't want to mix them into their own classes.
///
/// ```dart
/// final sharing = AtClientSecretSharing.forClient(atClient);
/// await sharing.register();
/// await sharing.startListening();
/// sharing.receivedSecrets.listen((r) => ...);
/// ```
///
/// Prefer [AtClientSecretSharing.forClient] over the plain constructor: a
/// secret-sharing instance is this APKAM keypair's recipient identity (its
/// KEM enc keypair, registered key package, and envelope listener) plus its
/// [SecretStore]. Reusing one instance per [AtClient] lets every consumer (the
/// app and SDK-internal ones, e.g. a future CryptoProvider that distributes
/// its keys as secrets) share a single store and a single registration rather
/// than minting duplicate enc keypairs. (Correctness does not depend on it —
/// kpid-addressed envelopes converge idempotently via [SecretStore.putIfNewer]
/// — but a single instance avoids redundant registration and double delivery.)
///
/// > **⚠ Experimental.** The recipient key package a sender seals to is
/// > discovered via the gated `enroll:listns` verb, and is APKAM-signed by the
/// > enrollment that generated it and verified against that enrollment's
/// > `_apsk` before anything is sealed to it — so a tampering atServer cannot
/// > substitute the encapsulation target under an honest `_apsk`. What remains
/// > is that the atServer serves the `_apsk` too, so the **operator** of the
/// > atSign's own atServer is still in the confidentiality boundary; removing
/// > that needs an anchor the operator does not control (key transparency).
/// > Durable storage of received secrets is also still an app-supplied hook.
@experimental
class AtClientSecretSharing
    with
        ApkamSigning,
        EnvelopeSigning,
        KeyPackageRegistration,
        PairwiseSecretSharing {
  static final Expando<AtClientSecretSharing> _instances =
      Expando('AtClientSecretSharing');

  /// The shared secret-sharing instance for [atClient], created on first
  /// call. [persistence] and [publicKeyCacheSettings] take effect only on
  /// the creating call; later calls return the cached instance unchanged
  /// (one [SecretStorePersistence] per APKAM keypair — see
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
  /// enc keypair. Use [forClient] unless that is what you want (tests,
  /// custom compositions).
  AtClientSecretSharing(
    this.atClient, {
    this.publicKeyCacheSettings = const (
      cacheExpiry: Duration(minutes: 5),
      resetOnLookup: true,
    ),
  }) {
    perEnrollmentSecretRequestGate = _requesterIsFullyPrivileged;
  }

  /// The production gate for per-enrollment secret requests: the requester's
  /// enrollment record — the server's word, not the requester's — must grant
  /// write (`w`) on both `*` and `__manage`.
  Future<bool> _requesterIsFullyPrivileged(String requesterEnrollmentId) async {
    final theirs = (await EnrollmentServiceImpl(atClient, AtEnrollment.create())
            .fetchEnrollmentRequests())
        .where((e) => e.enrollmentId == requesterEnrollmentId)
        .firstOrNull
        ?.namespace;
    return EnrollmentServiceImpl.isFullyPrivileged(theirs);
  }
}
