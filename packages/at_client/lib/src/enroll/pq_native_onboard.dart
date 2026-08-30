import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_client/src/crypto/nskey/pq_signing_root.dart'
    show PqSigningRoot;
import 'package:at_client/src/enroll/signing_key_mint.dart'
    show mintAdvertisedSigningKey;
import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/secret_sharing/enrollment_key_package.dart'
    show enrollmentKeyPackageBuilder;
import 'package:at_client/src/secret_sharing/algo_ids.dart'
    show SecretSharingAlgos;
import 'package:at_commons/at_commons.dart'
    show AtClientException, AtRootDomain;
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:meta/meta.dart' show experimental;

final _logger = AtSignLogger('pqNativeOnboard');

/// Stamps [request] with everything that makes an activation **PQ-native**: an
/// ML-DSA-65 APKAM authentication key, a data signing key the enrollment owns
/// from birth, and the first enrollment's key package — all three on the
/// `enroll:request` that creates the record.
///
/// Exists so that a caller with its own activation flow — `at_onboarding_cli`
/// builds a request carrying retry options, a keyfile path and its own
/// completion step — becomes PQ-native by one call rather than by copying
/// several assignments. Copying them is the failure mode this prevents, and
/// there are now two ways to get it wrong:
///
/// - setting only `signingAlgoType` mints an ML-DSA APKAM with **no key
///   package**, and `metadata.keyPackage` is otherwise written only by the
///   `enroll:request` that creates the enrollment record — so repairing that
///   atSign would take an `enroll:update` it must send for itself, and no
///   client sends one yet;
/// - setting `advertisedSigningKey` without handing the **same** keypair to
///   the key-package builder publishes a record naming one key and a package
///   signed by another. A peer verifies the package against `_apsk` before
///   sealing anything to the enrollment, so the atSign would activate
///   successfully and then never be sent a secret by anyone.
///
/// The signing key's algorithm is [dataSigningKeyAlgorithms]', and it is
/// normally weaker than the authentication key's. The asymmetry is the
/// design: only the **atServer** verifies the authentication key and it is the
/// operator's own infrastructure, while **every peer** verifies the signing
/// key and the fleet is not the operator's to upgrade. At `pqReady` that means
/// a single active `rsa2048` entry, the one `_apsk` spelling every deployed
/// reader can parse; at `pqActive` it is ML-DSA-65, whose readers ship in the
/// same release line as the posture itself.
///
/// [keyEstablishmentAlgo] is read from the caller's preference rather than
/// resolved here, because the builder runs before any client exists. It is
/// decided at this call, and changing it afterwards needs an `enroll:update`
/// the enrollment must send for itself.
///
/// Deliberately says nothing about [AtOnboardingRequest.mintLegacyMaterial]:
/// whether an atSign keeps legacy material is a separate decision from whether
/// its APKAM is post-quantum, and silently resetting a caller's opt-out would
/// be worse than making them state it.
@experimental
Future<void> makeActivationPqNative(
  AtOnboardingRequest request, {
  required String atSign,
  required Set<SigningAlgoType> dataSigningKeyAlgorithms,
  String keyEstablishmentAlgo = SecretSharingAlgos.xWing,
}) async {
  // Minted here, before the request, because the enrollment must own it from
  // its first byte: `_apsk` advertises this key and the key package is signed
  // with it, so a client start that minted it later would leave a window in
  // which the record names the ML-DSA authentication key — and would mint a
  // second keypair, since the first start finds the in-use algorithm missing.
  final advertisedSigningKey =
      await mintAdvertisedSigningKey(dataSigningKeyAlgorithms);

  request
    ..signingAlgoType = SigningAlgoType.mldsa65
    ..advertisedSigningKey = advertisedSigningKey
    ..metadataBuilder = enrollmentKeyPackageBuilder(atSign,
        signingAlgo: SigningAlgoType.mldsa65,
        advertisedSigningKey: advertisedSigningKey,
        keyEstablishmentAlgo: keyEstablishmentAlgo);
}

/// Creates the atSign-level ML-DSA-65 signing root at
/// `public:pq_signing_root@<atSign>`, if it is not already there.
///
/// Runs inside its own guard, and swallows. By the time this is called the
/// activation has already succeeded — the atSign is onboarded and usable — and
/// a root minted later heals nothing worse than a delay, since a start-time
/// pull and a re-run both retry it. Failing the caller over it would leave a
/// live atSign reported as unactivated, with a CRAM secret already spent and no
/// way to run the activation again.
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

/// CRAM-activates a brand-new atSign **PQ-native** and hands back a manager
/// whose current client runs under its first enrollment.
///
/// This is the greenfield counterpart of `selfRetrofit`: that one upgrades an
/// atSign that already exists, this one starts a fresh one in the shape a
/// retrofit would have produced, without the legacy generation in between.
///
/// What activation produces:
///
/// - an **ML-DSA-65 APKAM**, filed as typed material under the enrollment id.
///   The flat `apkamPublicKey`/`apkamPrivateKey` fields stay empty, so a
///   reader that cannot handle a PQ enrollment fails loudly rather than
///   signing an ML-DSA key with the RSA routine;
/// - the first enrollment's **key package**, advertised on the `enroll:request`
///   that creates the record. Nothing but the enrollment's own `enroll:update`
///   reaches `metadata.keyPackage` afterwards, so this is effectively the
///   moment its KEM is set, at whatever
///   [AtClientPreference.keyEstablishmentAlgorithms] names first;
/// - the atSign-level **ML-DSA-65 signing root**, published at
///   `public:pq_signing_root@<atSign>` under the `_rootlock` mint lock. A
///   first enrollment is fully privileged
///   by construction — the atServer grants it `__manage` — which is what
///   entitles it to create the root at all;
/// - the **legacy** RSA encryption keypair, `selfEncryptionKey` and
///   `public:publickey`, **by default**. Whether this atSign will ever need to
///   talk to a legacy peer is decided by the apps that adopt it, which is
///   unknowable here. Pass [mintLegacyMaterial] false only if you genuinely
///   know better; it makes a legacy peer's send to this atSign unsupported.
///
/// The signing-root step runs inside its own guard, after the client exists.
/// The activation itself has already succeeded by then — the atSign is
/// onboarded and usable — and a root minted later heals nothing worse than a
/// delay, since a start-time pull and a re-run both retry it. Failing the
/// whole onboard over it would leave a live atSign reported as unactivated,
/// with a CRAM secret already spent and no way to run it again.
/// The app an atSign's FIRST enrollment names when nothing else does.
///
/// Two paths reach it: onboarding, which creates that enrollment; and a
/// pre-enrollment atSign retrofitting itself, which has no record to read a
/// name from and is creating what amounts to the same thing. Both spell it
/// here so they cannot drift apart, and `at_auth`'s `AtOnboardingRequest`
/// carries the same value as its own default — pinned by a test, because a
/// field default in another package is not a constant this one can reference.
const String firstEnrollmentAppName = 'firstApp';

/// The device an atSign's FIRST enrollment names when nothing else does.
///
/// ⚠️ **A retrofit must not use it bare.** The atServer refuses a request
/// naming an `(appName, deviceName)` that an approved enrollment already
/// holds, so sibling clones of one keyfile all naming this would leave every
/// device after the first refused at every start. Callers in that position
/// append something per device.
const String firstEnrollmentDeviceName = 'firstDevice';

@experimental
Future<AtClientManager> pqNativeOnboard({
  required String atSign,
  required String cramSecret,
  required AtClientPreference preference,
  required AtKeysIo atKeysIo,
  String appName = firstEnrollmentAppName,
  String deviceName = firstEnrollmentDeviceName,
  bool? mintLegacyMaterial,
  AtClientManager? manager,
  AtAuth? atAuth,
}) async {
  final request = AtOnboardingRequest(atSign,
      rootDomain: AtRootDomain(preference.rootDomain, preference.rootPort))
    ..atKeysIo = atKeysIo
    ..appName = appName
    ..deviceName = deviceName
    // Carried deliberately: the built client's start-time self-heal — the
    // signing-root pull, the nskey pulls, the store hydration — all key off
    // its namespace, and a client built without one runs none of them while
    // looking perfectly healthy.
    ..namespace = preference.namespace
    ..mintLegacyMaterial = mintLegacyMaterial;
  // Mints the ML-DSA APKAM and advertises the first enrollment's key package.
  await makeActivationPqNative(request,
      atSign: atSign,
      dataSigningKeyAlgorithms: preference.dataSigningKeyAlgorithms,
      keyEstablishmentAlgo: preference.keyEstablishmentAlgorithms.first);

  final response =
      await (atAuth ?? AtAuth.create()).onboard(request, cramSecret);
  if (response.isSuccessful != true || response.session == null) {
    throw AtClientException.message(
        'the PQ-native activation of $atSign did not complete; no client was '
        'built and nothing was minted beyond what the atServer already holds');
  }

  final switched = await (manager ?? AtClientManager.getInstance())
      .fromAuthSession(response.session!, preference);

  await mintSigningRootAfterActivation(switched.atClient, atKeysIo: atKeysIo);

  return switched;
}
