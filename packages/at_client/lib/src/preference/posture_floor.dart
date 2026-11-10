import 'package:at_auth/at_auth.dart' show AtKeys, CryptographicMaterialRole;
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/src/crypto/nskey/nskey_records.dart'
    show nskeyKeyfileIdPrefix;
import 'package:at_client/src/preference/pq_posture.dart';

/// The stronger of [a] and [b] by [SigningAlgoType.strongestFirst].
SigningAlgoType strongerOf(SigningAlgoType a, SigningAlgoType b) =>
    SigningAlgoType.strongestOf({a, b})!;

/// [floor] when the strongest of [configured] is weaker than the strongest of
/// [floor], or [configured] names none and [floor] does; [configured] itself
/// otherwise.
Set<SigningAlgoType> raisedDataSigning(
    Set<SigningAlgoType> configured, Set<SigningAlgoType> floor) {
  final strongestFloor = SigningAlgoType.strongestOf(floor);
  if (strongestFloor == null) return configured;
  final strongest = SigningAlgoType.strongestOf(configured);
  if (strongest == null || strongerOf(strongest, strongestFloor) != strongest) {
    return floor;
  }
  return configured;
}

/// The floor [enrollmentId]'s own key material sets: [PqPosture.pqActive]
/// when it holds an active ML-DSA-65 client data signing key,
/// [PqPosture.pqReady] when the keyfile holds any namespace-key private, and
/// null otherwise.
PqPosture? floorOfKeyMaterial(AtKeys keys, String enrollmentId) {
  if (keys
      .signingKeysFor(enrollmentId)
      .any((key) => key.algorithm == SigningAlgoType.mldsa65)) {
    return PqPosture.pqActive;
  }
  final holdsNamespaceKey = keys.atSignKeys.any((material) =>
      material.role == CryptographicMaterialRole.privateDecapsulation &&
      material.keyId.startsWith(nskeyKeyfileIdPrefix));
  return holdsNamespaceKey ? PqPosture.pqReady : null;
}

/// How a log line names [posture].
String postureName(PqPosture posture) {
  if (identical(posture, PqPosture.legacy)) return 'PqPosture.legacy';
  if (identical(posture, PqPosture.pqReady)) return 'PqPosture.pqReady';
  if (identical(posture, PqPosture.pqActive)) return 'PqPosture.pqActive';
  return 'a posture no named stage defines';
}
