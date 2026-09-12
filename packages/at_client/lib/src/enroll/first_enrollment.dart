import 'dart:async';

import 'package:at_auth/at_auth.dart' show AtKeysIo;
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_client/src/crypto/nskey/pq_signing_root.dart'
    show PqSigningRoot;
import 'package:at_client/src/enroll/signing_key_mint.dart'
    show mintAdvertisedSigningKey;
import 'package:at_client/src/secret_sharing/algo_ids.dart'
    show SecretSharingAlgos;
import 'package:at_client/src/secret_sharing/enrollment_key_package.dart'
    show enrollmentKeyPackageBuilder;
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:meta/meta.dart' show experimental;

final _logger = AtSignLogger('firstEnrollment');

/// The app an atSign's FIRST enrollment names when nothing else does.
///
/// Onboarding and a pre-enrollment atSign retrofitting itself both spell it
/// here so they cannot drift apart, and at_auth's activation carries the same
/// value as its own default — pinned by a test, because a parameter default
/// in another package is not a constant this one can reference.
const String firstEnrollmentAppName = 'firstApp';

/// The device an atSign's FIRST enrollment names when nothing else does.
///
/// ⚠️ **A retrofit must not use it bare.** The atServer refuses a request
/// naming an `(appName, deviceName)` that an approved enrollment already
/// holds, so sibling clones of one keyfile all naming this would leave every
/// device after the first refused at every start. Callers in that position
/// append something per device.
const String firstEnrollmentDeviceName = 'firstDevice';

/// What a post-quantum activation puts on the request that creates the
/// atSign's first enrollment: a data signing key the enrollment owns from
/// birth, and the builder of the key package signed with that same key.
typedef PqNativeActivationMaterial = ({
  ({
    SigningAlgoType algorithm,
    String publicKey,
    String privateKey
  })? advertisedSigningKey,
  FutureOr<Map<String, dynamic>?> Function(AtKeysIo keysIo) metadataBuilder,
});

/// Mints everything that makes an activation **PQ-native** beyond its
/// ML-DSA-65 APKAM: a data signing key the enrollment owns from birth, and
/// the first enrollment's key package, both on the `enroll:request` that
/// creates the record.
///
/// One call rather than several assignments, because they go out of step:
/// minting the ML-DSA APKAM alone leaves the record with **no key package**,
/// and a signing key handed to the request but not to the key-package builder
/// publishes a record naming one key beside a package signed by another. Only
/// the `enroll:request` that creates the record writes `metadata.keyPackage`,
/// so repairing either takes an `enroll:update` the enrollment must send for
/// itself; and a peer verifies the package against `_apsk` before sealing
/// anything, so a mismatched atSign activates successfully and is then never
/// sent a secret by anyone.
///
/// The signing key's algorithm is [dataSigningKeyAlgorithms]', and it is
/// normally weaker than the authentication key's. The asymmetry is the
/// design: only the **atServer** verifies the authentication key and it is the
/// operator's own infrastructure, while **every peer** verifies the signing
/// key and the fleet is not the operator's to upgrade.
///
/// [keyEstablishmentAlgo] is decided at this call, because the builder runs
/// before any client exists; changing it afterwards needs an `enroll:update`
/// the enrollment must send for itself.
@experimental
Future<PqNativeActivationMaterial> pqNativeActivationMaterial({
  required String atSign,
  required Set<SigningAlgoType> dataSigningKeyAlgorithms,
  String keyEstablishmentAlgo = SecretSharingAlgos.xWing,
}) async {
  final advertisedSigningKey =
      await mintAdvertisedSigningKey(dataSigningKeyAlgorithms);
  return (
    advertisedSigningKey: advertisedSigningKey,
    metadataBuilder: enrollmentKeyPackageBuilder(atSign,
        signingAlgo: SigningAlgoType.mldsa65,
        advertisedSigningKey: advertisedSigningKey,
        keyEstablishmentAlgo: keyEstablishmentAlgo),
  );
}

/// Creates the atSign-level ML-DSA-65 signing root at
/// `public:pq_signing_root@<atSign>`, if it is not already there.
///
/// Swallows its own failure: the activation has already succeeded by the time
/// this runs, a root minted later heals nothing worse than a delay, and failing
/// the caller over it would leave a live atSign reported as unactivated with a
/// CRAM secret already spent.
///
/// [client] must be authenticated as the atSign's **first** enrollment, which
/// the atServer grants `__manage` — that is what entitles it to create the root
/// at all.
@experimental
Future<void> mintSigningRootAfterActivation(
  AtClient client, {
  required AtKeysIo atKeysIo,
}) async {
  try {
    await PqSigningRoot(client, keysIo: atKeysIo)
        .mintIfAbsent(isFullyPrivileged: true);
  } catch (e) {
    _logger.warning('${client.getCurrentAtSign()} activated but its '
        'signing-root step did not complete; a start-time pull or a later '
        'mint retries it: $e');
  }
}
