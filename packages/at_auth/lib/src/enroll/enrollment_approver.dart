import 'dart:convert';

import 'package:at_auth/src/enroll/models/at_enrollment_response.dart';
import 'package:at_auth/src/enroll/models/enrollment_request_decision.dart';
import 'package:at_auth/src/enroll/models/otp.dart';
import 'package:at_auth/src/exception/at_auth_exceptions.dart';
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

  /// [approverChops] is the approving client's own crypto.
  ///
  /// None of what this method needs is authentication: it wants the atSign's
  /// **encryption** private key, its self-encryption key, and somewhere to put
  /// the APKAM symmetric key it derives. Reaching through `atLookUp.atChops`
  /// for those made a network object the carrier of an app's key material.
  /// Passing it keeps at_lookup out of it, and lets that field go.
  Future<AtEnrollmentResponse> approve(
      EnrollmentRequestDecision enrollmentRequestDecision, AtLookUp atLookUp,
      {AtChops? approverChops}) async {
    final chops = approverChops ?? atLookUp.atChops;
    if (chops == null) {
      throw AtAuthenticationException(
          'The authentication keys are not initialized');
    }
    // An enrollment that advertised a key package sent no wrapped key, because
    // this approver minted it — there is nothing to unwrap, and the RSA step is
    // skipped entirely rather than being fed an empty string. Every other
    // enrollment still arrives RSA-wrapped to the atSign's encryption public
    // key, and is decrypted here with the private half from the atChops
    // instance, via at_chops (wraps crypton's RSAPrivateKey.decrypt:
    // utf8.decode(decryptData(base64(msg)))).
    String apkamSymmetricKey = enrollmentRequestDecision
            .mintedApkamSymmetricKey ??
        utf8.decode((RsaEncryptionAlgo()
              ..atPrivateKey = AtPrivateKey.fromString(chops.atChopsKeys.atEncryptionKeyPair!.atPrivateKey.privateKey))
            .decrypt(base64Decode(
                enrollmentRequestDecision.encryptedAPKAMSymmetricKey)));

    // Set the APKAM Symmetric key to the AtChops Instance.
    chops.atChopsKeys.apkamSymmetricKey = AESKey(apkamSymmetricKey);

    InitialisationVector encryptionPrivateKeyIV =
        AtChopsUtil.generateRandomIV(16);
    // Fetch the encryptionPrivateKey from the atChops and encrypt with APKAM Symmetric key.
    String encryptedDefaultEncryptionPrivateKey = (await chops.encryptString(
                chops.atChopsKeys.atEncryptionKeyPair!.atPrivateKey.privateKey,
                EncryptionKeyType.aes256,
                keyName: 'apkamSymmetricKey',
                iv: encryptionPrivateKeyIV))
        .result;

    InitialisationVector selfEncryptionKeyIV = AtChopsUtil.generateRandomIV(16);
    // Fetch the selfEncryptionKey from the atChops and encrypt with APKAM Symmetric key.
    String encryptedDefaultSelfEncryptionKey = (await chops.encryptString(
                chops.atChopsKeys.selfEncryptionKey!.key,
                EncryptionKeyType.aes256,
                keyName: 'apkamSymmetricKey',
                iv: selfEncryptionKeyIV))
        .result;

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
