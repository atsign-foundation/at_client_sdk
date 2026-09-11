import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/src/enroll/models/approver_key_material.dart';
import 'package:at_auth/src/enroll/models/at_enrollment_response.dart';
import 'package:at_auth/src/enroll/models/enrollment_request_decision.dart';
import 'package:at_auth/src/enroll/models/otp.dart';
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
  static const _kSppRegex = r'[A-Za-z0-9]{6}';

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
    AtEnrollmentResponse enrollmentResponse = AtEnrollmentResponse(
        enrollmentJsonMap['enrollmentId'],
        getEnrollStatusFromString(enrollmentJsonMap['status']));
    return enrollmentResponse;
  }

  Future<AtEnrollmentResponse> revoke(
      EnrollmentRequestDecision enrollmentRequestDecision,
      AtLookUp atLookUp) async {
    EnrollVerbBuilder revokeEnrollVerbBuilder = EnrollVerbBuilder()
      ..enrollmentId = enrollmentRequestDecision.enrollmentId
      ..operation = EnrollOperationEnum.revoke
      ..force = enrollmentRequestDecision.force;

    String? enrollmentResponseStr = await atLookUp
        .executeCommand(revokeEnrollVerbBuilder.buildCommand(), auth: true);

    enrollmentResponseStr =
        enrollmentResponseStr?.replaceFirst(RegExp(r'^data:'), '');
    var enrollmentJsonMap = jsonDecode(enrollmentResponseStr!);
    AtEnrollmentResponse enrollmentResponse = AtEnrollmentResponse(
        enrollmentJsonMap['enrollmentId'],
        getEnrollStatusFromString(enrollmentJsonMap['status']));
    return enrollmentResponse;
  }

  Future<List<EnrollmentServerResponse>> list(
    List<EnrollmentStatus>? filters,
    AtLookUp atLookup, {
    String? arx,
    String? drx,
  }) async {
    String command = 'enroll:list';
    //Handle EnrollmentStatus enum to string
    String statusFilter = '';
    if (filters != null) {
      for (EnrollmentStatus filter in filters) {
        statusFilter += '${filter.name},';
      }

      //remove additional ','
      statusFilter = statusFilter.substring(0, statusFilter.length - 1);
      if (statusFilter.isNotEmpty) {
        command += ':{"enrollmentStatusFilter":["$statusFilter"]}';
      }
    }
    String rawResponse = (await atLookup.executeCommand(
      '$command\n',
      auth: true,
    ))!;

    RegExp? ar;
    RegExp? dr;
    if (arx != null) {
      ar = RegExp(arx);
    }
    if (drx != null) {
      dr = RegExp(drx);
    }
    if (rawResponse.startsWith('data:')) {
      rawResponse = rawResponse.substring(rawResponse.indexOf('data:') + 5);
      Map unfiltered = jsonDecode(rawResponse);
      List<EnrollmentServerResponse> filtered = [];
      for (final String ek in unfiltered.keys) {
        final e = unfiltered[ek];
        String appName = e['appName'] as String;
        if (ar != null) {
          if (!ar.hasMatch(appName)) {
            continue;
          }
        }
        String deviceName = e['deviceName'] as String;
        if (dr != null) {
          if (!dr.hasMatch(deviceName)) {
            continue;
          }
        }
        filtered.add(EnrollmentServerResponse.fromServer(MapEntry(ek, e)));
      }
      return filtered;
    } else {
      throw Exception('Unexpected server response: $rawResponse');
    }
  }

  /// [expiry] has no default here: the defaults of the published API belong
  /// to the class that implements it, so every caller of this one is explicit.
  Future<Otp> generateOtp(AtLookUp atLookUp, {required Duration expiry}) async {
    final command = 'otp:get:ttl:${expiry.inMilliseconds}\n';
    final response = await atLookUp.executeCommand(command, auth: true);
    if (response != null && response.startsWith('data:')) {
      final otp = response.substring(response.indexOf('data:') + 5).trim();
      return Otp.fromDuration(value: otp, duration: expiry);
    }
    throw AtEnrollmentException('Failed to generate OTP. Response: $response');
  }

  Future<Otp> setSpp(String spp, AtLookUp atLookUp,
      {required Duration expiry}) async {
    if (!RegExp('^$_kSppRegex\$').hasMatch(spp)) {
      throw AtEnrollmentException(
          'SPP must be alphanumeric and exactly 6 characters');
    }
    final command = 'otp:put:$spp:ttl:${expiry.inMilliseconds}\n';
    final response = await atLookUp.executeCommand(command, auth: true);
    if (response == null || !response.contains('ok')) {
      throw AtEnrollmentException('Failed to set SPP. Response: $response');
    }
    return Otp.fromDuration(value: spp, duration: expiry);
  }
}
