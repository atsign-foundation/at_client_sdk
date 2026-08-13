import 'dart:convert';

import 'package:at_auth/src/enroll/apkam_possession_proof.dart';
import 'package:at_auth/src/enroll/apsk_advertisement.dart';
import 'package:at_auth/src/enroll/models/at_enrollment_response.dart';
import 'package:at_auth/src/enroll/models/enrollment_update_request.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';

/// An approved enrollment amending its own record: `enroll:update`.
///
/// Its own class rather than a method on `EnrollmentApprover` because it is the
/// other side of the same divide that separates the approver from the
/// submitter. The approver's verbs need a connection holding `__manage` and act
/// on *somebody else's* enrollment; this one needs no privilege at all and can
/// only ever act on the enrollment the connection is authenticated as. The
/// atServer enforces exactly that, refusing an owner connection rather than
/// waving it through.
class EnrollmentUpdater {
  Future<AtEnrollmentResponse> update(
      EnrollmentUpdateRequest request, AtLookUp atLookUp) async {
    final builder = EnrollVerbBuilder()
      ..enrollmentId = request.enrollmentId
      ..operation = EnrollOperationEnum.update
      ..metadata = request.metadata;

    if (request.apkamPublicKey != null) {
      // The algorithm is always sent, so the effective one the atServer
      // interpolates into the string it verifies is the one signed here. A
      // request that omitted it would be signed against whatever the record
      // already holds — including the literal 'null' for a record that names
      // none — which is a value this side does not have.
      builder
        ..apkamPublicKey = request.apkamPublicKey
        ..signingAlgo = request.signingAlgo!.name
        ..apkamPublicKeySignature = apkamPossessionSignature(
          enrollmentId: request.enrollmentId,
          apkamPublicKey: request.apkamPublicKey!,
          apkamPrivateKey: request.apkamPrivateKey!,
          signingAlgo: request.signingAlgo!,
        );
    }

    // Composed here rather than by the caller, for the same reason the
    // enrollment request composes its own: the `kid` in each entry is a
    // function of the key material, and a caller that supplied one could
    // address a key nobody is listening on with nothing to say it had.
    if (request.signingKeys != null) {
      builder.apsk = apskAdvertisement(keys: request.signingKeys!);
    } else if (request.apskLegacy != null) {
      builder.apskLegacy = request.apskLegacy;
    }

    String? response =
        await atLookUp.executeCommand(builder.buildCommand(), auth: true);
    if (response == null || response.isEmpty || response.startsWith('error:')) {
      throw AtEnrollmentException(
          'enroll:update response from server: $response');
    }
    final enrollmentJsonMap =
        jsonDecode(response.replaceFirst(RegExp(r'^data:'), ''));

    return AtEnrollmentResponse(enrollmentJsonMap['enrollmentId'],
        getEnrollStatusFromString(enrollmentJsonMap['status']));
  }
}
