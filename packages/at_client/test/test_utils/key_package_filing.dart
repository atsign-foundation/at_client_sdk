import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/src/secret_sharing/key_package_persistence.dart'
    show keyPackageMaterials;
import 'package:at_client/src/signing/envelope_signature.dart'
    show SignedEnvelope;
import 'package:test/test.dart';

/// The kid of the one key the key package in [enrollRequest], an
/// `enroll:request:` command as sent, advertises.
String advertisedKid(String enrollRequest) {
  final params = jsonDecode(enrollRequest.substring(
      enrollRequest.indexOf('{'), enrollRequest.lastIndexOf('}') + 1));
  final envelope =
      SignedEnvelope.fromJson(params['metadata']['keyPackage'] as Map);
  return ((envelope.payload as Map)['keys'] as List).single['kid'] as String;
}

/// Expects [keys] to file the key package [kid] names under [enrollmentId],
/// both halves, to hold no key package filed without an enrollment id, and to
/// load [kid] for [enrollmentId].
void expectKeyPackageFiledUnder(AtKeys keys, String enrollmentId,
    {required String kid}) {
  bool isKeyPackage(CryptographicMaterial m) =>
      m.role == CryptographicMaterialRole.publicEncapsulation ||
      m.role == CryptographicMaterialRole.privateDecapsulation;
  final advertised = keys.keys.where((m) => isKeyPackage(m) && m.keyId == kid);
  expect(
      advertised.map((m) => m.role).toSet(),
      {
        CryptographicMaterialRole.publicEncapsulation,
        CryptographicMaterialRole.privateDecapsulation
      },
      reason: 'both halves of the advertised key package $kid are filed');
  expect(advertised.map((m) => m.enrollmentId).toSet(), {enrollmentId},
      reason: 'the advertised key package is filed under its enrollment id');
  expect(keys.keys.where((m) => isKeyPackage(m) && m.enrollmentId == null),
      isEmpty,
      reason: 'no key package is filed without an enrollment id');
  expect(
      keyPackageMaterials(keys, enrollmentId: enrollmentId).map((m) => m.keyId),
      contains(kid),
      reason: 'a load of the keyfile holds the advertised key package');
}
