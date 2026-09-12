import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/src/enroll/models/approver_key_material.dart';
import 'package:at_auth/src/enroll/models/at_enrollment_response.dart';
import 'package:at_auth/src/enroll/models/enrollment_request_decision.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';

/// The verbs of the app that manages an atSign's enrollments: deciding a
/// pending request, enumerating the roster, and issuing the passcodes a new
/// request has to quote.
///
/// They are one family because they need one thing — a connection
/// authenticated as an enrollment that holds `__manage`. The requesting side
/// (see `EnrollmentSubmitter`) never has that, and the passcode verbs are
/// here rather than with submission for the same reason: an OTP is minted by
/// the app that will approve, and handed to the app that will request.
class EnrollmentApprover {

  /// [approverKeys] is what approval reads of the approving client's own
  /// material, and all of it: the atSign's encryption private key, which
  /// unwraps the symmetric key a legacy enrollee RSA-wrapped to it, and the
  /// self-encryption key, one of the two secrets sealed for the enrollee under
  /// that symmetric key. Required: approval never reaches through [atLookUp]
  /// for key material, which made a network object the carrier of an app's
  /// keys.
  Future<AtEnrollmentResponse> approve(
      EnrollmentRequestDecision enrollmentRequestDecision, AtLookUp atLookUp,
      {required ApproverKeyMaterial approverKeys}) async {
    // An enrollment that advertised a key package sent no wrapped key, because
    // this approver minted it — there is nothing to unwrap, and the RSA step is
    // skipped entirely rather than being fed an empty string. Every other
    // enrollment still arrives RSA-wrapped to the atSign's encryption public
    // key, and is unwrapped here with the private half.
    final String apkamSymmetricKey =
        enrollmentRequestDecision.mintedApkamSymmetricKey ??
            utf8.decode((RsaEncryptionAlgo()
                  ..atPrivateKey =
                      AtPrivateKey.fromString(approverKeys.encryptionPrivateKey))
                .decrypt(base64Decode(
                    enrollmentRequestDecision.encryptedAPKAMSymmetricKey)));

    // NOTE: the enrollee opens these with at_chops' string AES under the same
    // key and IV, so the pair is a wire contract; approver_key_material_test
    // opens them that way.
    final sealer = AESEncryptionAlgo(AESKey(apkamSymmetricKey));
    Future<String> sealed(String value, InitialisationVector iv) async =>
        base64.encode(await sealer
            .encrypt(Uint8List.fromList(utf8.encode(value)), iv: iv));

    final encryptionPrivateKeyIV = InitialisationVector.random(16);
    final encryptedDefaultEncryptionPrivateKey =
        await sealed(approverKeys.encryptionPrivateKey, encryptionPrivateKeyIV);

    final selfEncryptionKeyIV = InitialisationVector.random(16);
    final encryptedDefaultSelfEncryptionKey =
        await sealed(approverKeys.selfEncryptionKey, selfEncryptionKeyIV);

    String command = 'enroll:approve:${jsonEncode({
          'enrollmentId': enrollmentRequestDecision.enrollmentId,
          'encryptedDefaultEncryptionPrivateKey':
              encryptedDefaultEncryptionPrivateKey,
          AtConstants.apkamEncryptionPrivateKeyIV:
              base64Encode(encryptionPrivateKeyIV.ivBytes),
          AtConstants.apkamEncryptedDefaultSelfEncryptionKey:
              encryptedDefaultSelfEncryptionKey,
          AtConstants.apkamSelfEncryptionKeyIV:
              base64Encode(selfEncryptionKeyIV.ivBytes)
        })}';

    String? enrollResponse =
        await atLookUp.executeCommand('$command\n', auth: true);
    enrollResponse = enrollResponse?.replaceFirst(RegExp(r'^data:'), '');
    var enrollmentJsonMap = jsonDecode(enrollResponse!);
    AtEnrollmentResponse enrollmentResponse = AtEnrollmentResponse(
        enrollmentJsonMap['enrollmentId'],
        getEnrollStatusFromString(enrollmentJsonMap['status']));
    return enrollmentResponse;
  }

  /// Denies [enrollmentRequestDecision]'s enrollment, for the submitter to
  /// tidy up a self-enrollment the atServer did not auto-approve; the
  /// approving side's own verb is at_client's `client.enrollments.deny`.
  Future<AtEnrollmentResponse> deny(
      EnrollmentRequestDecision enrollmentRequestDecision,
      AtLookUp atLookUp) async {
    EnrollVerbBuilder denyEnrollmentBuilder = EnrollVerbBuilder()
      ..enrollmentId = enrollmentRequestDecision.enrollmentId
      ..operation = enrollmentRequestDecision.enrollOperationEnum;

    String? enrollResponse = await atLookUp
        .executeCommand(denyEnrollmentBuilder.buildCommand(), auth: true);

    enrollResponse = enrollResponse?.replaceFirst(RegExp(r'^data:'), '');
    var enrollmentJsonMap = jsonDecode(enrollResponse!);
    return AtEnrollmentResponse(enrollmentJsonMap['enrollmentId'],
        getEnrollStatusFromString(enrollmentJsonMap['status']));
  }
}
