import 'dart:async';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/src/enroll/first_enrollment.dart';
import 'package:at_client/src/lifecycle/atsign_lifecycle.dart';
import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/storage/at_client_storage.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart' show AtLookUp;
import 'package:meta/meta.dart' show experimental;

export 'package:at_client/src/enroll/first_enrollment.dart';

/// CRAM-activates a brand-new atSign **PQ-native** and hands back a manager
/// whose current client runs under its first enrollment.
///
/// `Atsign.activate` with the APKAM algorithm forced to ML-DSA-65 whatever
/// the preference says, then `AtClientManager.use`. What activation produces:
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
///   `public:pq_signing_root@<atSign>` under the `_rootlock` mint lock. A first
///   enrollment is fully privileged by construction, which is what entitles it
///   to create the root at all;
/// - the **legacy** RSA encryption keypair, `selfEncryptionKey` and
///   `public:publickey`, **by default**. Pass [mintLegacyMaterial] false only
///   if you know better; it makes a legacy peer's send to this atSign
///   unsupported.
///
/// The signing-root step runs inside its own guard: the activation has already
/// succeeded by then, and failing the whole onboard over it would leave a live
/// atSign reported as unactivated with a CRAM secret already spent.
///
/// [atKeysIo] must be writable, since the activation mints the keys it holds.
/// [atLookUp] is the connection to activate over; normally omitted, in which
/// case the atServer is found through the atDirectory and waited for.
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

  /// The store the activated client opens. An activation builds the
  /// atSign's first client, so there is no earlier holder to inherit
  /// from and the caller supplies it.
  AtClientStorage? storage,
  AtLookUp? atLookUp,
}) async {
  if (atKeysIo is! WrittenAtKeysIo) {
    throw ArgumentError.value(
        atKeysIo,
        'atKeysIo',
        'an activation mints key material and must write it: supply a '
            'WrittenAtKeysIo');
  }
  final client = await Atsign(atSign).activate(
      cramSecret: cramSecret,
      keys: atKeysIo,
      preference: preference,
      // NOTE: the built client's start-time self-heal — the signing-root pull,
      // the nskey pulls, the store hydration — all key off its namespace, and a
      // client built without one runs none of them while looking perfectly
      // healthy.
      namespace: preference.namespace,
      storage: storage,
      app: appName,
      device: deviceName,
      mintLegacyMaterial: mintLegacyMaterial,
      signingAlgo: SigningAlgoType.mldsa65,
      atLookUp: atLookUp);
  final adopting = manager ?? AtClientManager.getInstance();
  adopting.use(client);
  return adopting;
}
