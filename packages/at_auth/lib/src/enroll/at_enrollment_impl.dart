import 'dart:async';
import 'dart:convert';

import 'package:at_auth/src/enroll/at_enrollment_base.dart';
import 'package:at_auth/src/enroll/at_enrollment_response.dart';
import 'package:at_auth/src/enroll/base_enrollment_request.dart';
import 'package:at_auth/src/enroll/enrollment_request.dart';
import 'package:at_auth/src/enroll/enrollment_request_decision.dart';
import 'package:at_auth/src/enroll/first_enrollment_request.dart';
import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_auth_keys.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:crypton/crypton.dart';

/// A concrete implementation of [AtEnrollmentBase] for managing enrollments.
///
/// This class provides functionality to submit and manage enrollment requests.
class AtEnrollmentImpl implements AtEnrollmentBase {
  final String _atSign;

  AtEnrollmentImpl(this._atSign);

  @override
  Future<AtEnrollmentResponse> submit(
      BaseEnrollmentRequest baseEnrollmentRequest, AtLookUp atLookUp) async {
    switch (baseEnrollmentRequest) {
      case FirstEnrollmentRequest _:
        return _handleFirstEnrollmentRequest(baseEnrollmentRequest, atLookUp);
      case EnrollmentRequest _:
        return _handleEnrollmentRequest(baseEnrollmentRequest, atLookUp);
      default:
        throw InvalidRequestException('Invalid Enrollment request received');
    }
  }

  /// Handles the FirstEnrollmentRequest, which is submitted when an atSign is first onboarded.
  Future<AtEnrollmentResponse> _handleFirstEnrollmentRequest(
      FirstEnrollmentRequest baseEnrollmentRequest, AtLookUp atLookUp) async {
    EnrollVerbBuilder enrollVerbBuilder = EnrollVerbBuilder()
      ..appName = baseEnrollmentRequest.appName
      ..deviceName = baseEnrollmentRequest.deviceName;
    enrollVerbBuilder.apkamPublicKey = baseEnrollmentRequest.apkamPublicKey;
    enrollVerbBuilder.encryptedDefaultEncryptionPrivateKey =
        baseEnrollmentRequest.encryptedDefaultEncryptionPrivateKey;
    enrollVerbBuilder.encryptedDefaultSelfEncryptionKey =
        baseEnrollmentRequest.encryptedDefaultSelfEncryptionKey;

    String? serverResponse =
        await _executeEnrollCommand(enrollVerbBuilder, atLookUp);
    var enrollJson = jsonDecode(serverResponse);
    var enrollmentIdFromServer = enrollJson[AtConstants.enrollmentId];
    var enrollStatus = getEnrollStatusFromString(enrollJson['status']);

    return AtEnrollmentResponse(enrollmentIdFromServer, enrollStatus);
  }

  /// Handles the subsequent enrollment requests.
  Future<AtEnrollmentResponse> _handleEnrollmentRequest(
      EnrollmentRequest enrollmentRequest, AtLookUp atLookUp) async {
    EnrollVerbBuilder enrollVerbBuilder = EnrollVerbBuilder()
      ..appName = enrollmentRequest.appName
      ..deviceName = enrollmentRequest.deviceName;

    // Generate APKAM Key pair
    AtPkamKeyPair apkamKeyPair = AtChopsUtil.generateAtPkamKeyPair();
    enrollVerbBuilder.apkamPublicKey = apkamKeyPair.atPublicKey.publicKey;
    SymmetricKey apkamSymmetricKey =
        AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256);
    String defaultEncryptionPublicKey =
        await _getDefaultEncryptionPublicKey(atLookUp);
    // Encrypting the Encryption Public key with APKAM Symmetric key.
    enrollVerbBuilder.encryptedAPKAMSymmetricKey =
        RSAPublicKey.fromString(defaultEncryptionPublicKey)
            .encrypt(apkamSymmetricKey.key);
    enrollVerbBuilder.otp = enrollmentRequest.otp;
    enrollVerbBuilder.namespaces = enrollmentRequest.namespaces;
    enrollVerbBuilder.apkamKeysExpiryDuration =
        enrollmentRequest.apkamKeysExpiryDuration;

    String? serverResponse =
        await _executeEnrollCommand(enrollVerbBuilder, atLookUp);
    var enrollJson = jsonDecode(serverResponse);
    var enrollmentIdFromServer = enrollJson[AtConstants.enrollmentId];
    var enrollStatus = getEnrollStatusFromString(enrollJson['status']);
    AtAuthKeys atAuthKeys = AtAuthKeys()
      ..apkamPrivateKey = apkamKeyPair.atPrivateKey.privateKey
      ..apkamPublicKey = apkamKeyPair.atPublicKey.publicKey
      ..apkamSymmetricKey = apkamSymmetricKey.key
      ..enrollmentId = enrollJson[AtConstants.enrollmentId]
      ..defaultEncryptionPublicKey = defaultEncryptionPublicKey;

    return AtEnrollmentResponse(enrollmentIdFromServer, enrollStatus)
      ..atAuthKeys = atAuthKeys;
  }

  @override
  Future<AtEnrollmentResponse> approve(
      EnrollmentRequestDecision enrollmentRequestDecision,
      AtLookUp atLookUp) async {
    if (atLookUp.atChops == null) {
      throw AtAuthenticationException(
          'The authentication keys are not initialized');
    }
    // Fetch the encryptionPrivateKey from atChops instance.
    RSAPrivateKey defaultEncryptionPrivateKey = RSAPrivateKey.fromString(
        atLookUp
            .atChops!.atChopsKeys.atEncryptionKeyPair!.atPrivateKey.privateKey);

    // Decrypt the encrypted APKAM Symmetric key to get the original APKAM symmetric key
    String apkamSymmetricKey = defaultEncryptionPrivateKey
        .decrypt(enrollmentRequestDecision.encryptedAPKAMSymmetricKey);

    // Set the APKAM Symmetric key to the AtChops Instance.
    atLookUp.atChops?.atChopsKeys.apkamSymmetricKey = AESKey(apkamSymmetricKey);

    // Fetch the encryptionPrivateKey from the atChops and encrypt with APKAM Symmetric key.
    String encryptedDefaultEncryptionPrivateKey = atLookUp.atChops
        ?.encryptString(
            atLookUp.atChops!.atChopsKeys.atEncryptionKeyPair!.atPrivateKey
                .privateKey,
            EncryptionKeyType.aes256,
            keyName: 'apkamSymmetricKey',
            iv: AtChopsUtil.generateIVLegacy())
        .result;

    // Fetch the selfEncryptionKey from the atChops and encrypt with APKAM Symmetric key.
    String encryptedDefaultSelfEncryptionKey = atLookUp.atChops
        ?.encryptString(atLookUp.atChops!.atChopsKeys.selfEncryptionKey!.key,
            EncryptionKeyType.aes256,
            keyName: 'apkamSymmetricKey', iv: AtChopsUtil.generateIVLegacy())
        .result;

    String command = 'enroll:approve:${jsonEncode({
          'enrollmentId': enrollmentRequestDecision.enrollmentId,
          'encryptedDefaultEncryptionPrivateKey':
              encryptedDefaultEncryptionPrivateKey,
          'encryptedDefaultSelfEncryptionKey': encryptedDefaultSelfEncryptionKey
        })}';

    String? enrollResponse =
        await atLookUp.executeCommand('$command\n', auth: true);
    enrollResponse = enrollResponse?.replaceAll('data:', '');
    var enrollmentJsonMap = jsonDecode(enrollResponse!);
    AtEnrollmentResponse enrollmentResponse = AtEnrollmentResponse(
        enrollmentJsonMap['enrollmentId'],
        _convertEnrollmentStatusToEnum(enrollmentJsonMap['status']));
    return enrollmentResponse;
  }

  @override
  Future<AtEnrollmentResponse> deny(
      EnrollmentRequestDecision enrollmentRequestDecision,
      AtLookUp atLookUp) async {
    EnrollVerbBuilder denyEnrollmentBuilder = EnrollVerbBuilder()
      ..enrollmentId = enrollmentRequestDecision.enrollmentId
      ..operation = enrollmentRequestDecision.enrollOperationEnum;

    String? enrollResponse = await atLookUp
        .executeCommand(denyEnrollmentBuilder.buildCommand(), auth: true);

    enrollResponse = enrollResponse?.replaceAll('data:', '');
    var enrollmentJsonMap = jsonDecode(enrollResponse!);
    AtEnrollmentResponse enrollmentResponse = AtEnrollmentResponse(
        enrollmentJsonMap['enrollmentId'],
        _convertEnrollmentStatusToEnum(enrollmentJsonMap['status']));
    return enrollmentResponse;
  }

  @override
  Future<AtEnrollmentResponse> revoke(
      EnrollmentRequestDecision enrollmentRequestDecision,
      AtLookUp atLookUp) async {
    EnrollVerbBuilder revokeEnrollVerbBuilder = EnrollVerbBuilder()
      ..enrollmentId = enrollmentRequestDecision.enrollmentId
      ..operation = EnrollOperationEnum.revoke
      ..force = enrollmentRequestDecision.force;

    String? enrollmentResponseStr = await atLookUp
        .executeCommand(revokeEnrollVerbBuilder.buildCommand(), auth: true);

    enrollmentResponseStr = enrollmentResponseStr?.replaceAll('data:', '');
    var enrollmentJsonMap = jsonDecode(enrollmentResponseStr!);
    AtEnrollmentResponse enrollmentResponse = AtEnrollmentResponse(
        enrollmentJsonMap['enrollmentId'],
        _convertEnrollmentStatusToEnum(enrollmentJsonMap['status']));
    return enrollmentResponse;
  }

  Future<String> _getDefaultEncryptionPublicKey(AtLookUp atLookupImpl) async {
    var lookupVerbBuilder = LookupVerbBuilder()
      ..atKey = (AtKey()
        ..key = 'publickey'
        ..sharedBy = _atSign);
    String? lookupResult = await atLookupImpl.executeVerb(lookupVerbBuilder);
    if (lookupResult == null || lookupResult.isEmpty) {
      throw AtEnrollmentException(
          'Unable to lookup encryption public key. Server response is null/empty');
    }
    var defaultEncryptionPublicKey = lookupResult.replaceFirst('data:', '');
    return defaultEncryptionPublicKey;
  }

  EnrollmentStatus _convertEnrollmentStatusToEnum(String enrollmentStatus) {
    switch (enrollmentStatus) {
      case 'approved':
        return EnrollmentStatus.approved;
      case 'denied':
        return EnrollmentStatus.denied;
      case 'expired':
        return EnrollmentStatus.expired;
      case 'revoked':
        return EnrollmentStatus.revoked;
      case 'pending':
        return EnrollmentStatus.pending;
      default:
        throw AtEnrollmentException(
            '$enrollmentStatus is not a valid enrollment status');
    }
  }

  Future<String> _executeEnrollCommand(
      EnrollVerbBuilder enrollVerbBuilder, AtLookUp atLookUp) async {
    var enrollResult =
        await atLookUp.executeCommand(enrollVerbBuilder.buildCommand());
    if (enrollResult == null ||
        enrollResult.isEmpty ||
        enrollResult.startsWith('error:')) {
      throw AtEnrollmentException(
          'Enrollment response from server: $enrollResult');
    }
    return enrollResult.replaceFirst('data:', '');
  }
}
