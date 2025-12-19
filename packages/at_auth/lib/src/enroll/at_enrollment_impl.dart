import 'dart:async';
import 'dart:convert';

import 'package:at_auth/src/enroll/at_enrollment.dart';
import 'package:at_auth/src/enroll/models/at_enrollment_response.dart';
import 'package:at_auth/src/enroll/models/at_enrollment_request.dart';
import 'package:at_auth/src/enroll/models/enrollment_request_decision.dart';
import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_utils/at_progress.dart';
import 'package:crypton/crypton.dart';

/// A concrete implementation of [AtEnrollment] for managing enrollments.
///
/// This class provides functionality to submit and manage enrollment requests.
class AtEnrollmentImpl implements AtEnrollment {
  AtEnrollmentImpl();

  final StreamController<ProgressEvent> _progressStreamController =
      StreamController<ProgressEvent>.broadcast();

  @override
  Stream<ProgressEvent> get progressStream => _progressStreamController.stream;
  void _addProgress(
      String group, String message, ProgressEventType progressEventType) {
    var progressEvent =
        ProgressEvent(group: group, msg: message, type: progressEventType);
    _progressStreamController.add(progressEvent);
  }

  @override
  Future<AtEnrollmentResponse> submit(
      EnrollmentRequest enrollmentRequest, AtLookUp atLookUp) async {
    AtEnrollmentResponse atEnrollmentResponse;
    switch (enrollmentRequest) {
      case FirstEnrollmentRequest _:
        atEnrollmentResponse =
            await _handleFirstEnrollmentRequest(enrollmentRequest, atLookUp);
        break;
      case AtEnrollmentRequest _:
        atEnrollmentResponse =
            await _handleAtEnrollmentRequest(enrollmentRequest, atLookUp);
      default:
        _addProgress('enrollment', 'Invalid Enrollment request received',
            ProgressEventType.error);
        throw InvalidRequestException('Invalid Enrollment request received');
    }
    _addProgress('enrollment', 'Enrollment request submitted',
        ProgressEventType.success);
    return atEnrollmentResponse;
  }

  /// Handles the FirstEnrollmentRequest, which is submitted when an atSign is first onboarded.
  Future<AtEnrollmentResponse> _handleFirstEnrollmentRequest(
      FirstEnrollmentRequest enrollmentRequest, AtLookUp atLookUp) async {
    EnrollVerbBuilder enrollVerbBuilder = EnrollVerbBuilder()
      ..appName = enrollmentRequest.appName
      ..deviceName = enrollmentRequest.deviceName;
    enrollVerbBuilder.apkamPublicKey = enrollmentRequest.apkamPublicKey;

    String? serverResponse =
        await _executeEnrollCommand(enrollVerbBuilder, atLookUp);
    var enrollJson = jsonDecode(serverResponse);
    var enrollmentIdFromServer = enrollJson[AtConstants.enrollmentId];
    var enrollStatus = getEnrollStatusFromString(enrollJson['status']);

    return AtEnrollmentResponse(
      enrollmentIdFromServer,
      enrollStatus,
      atSign: enrollmentRequest.atSign,
      rootDomain: enrollmentRequest.rootDomain,
    );
  }

  /// Handles the subsequent enrollment requests.
  Future<AtEnrollmentResponse> _handleAtEnrollmentRequest(
      AtEnrollmentRequest atEnrollmentRequest, AtLookUp atLookUp) async {
    EnrollVerbBuilder enrollVerbBuilder = EnrollVerbBuilder()
      ..appName = atEnrollmentRequest.appName
      ..deviceName = atEnrollmentRequest.deviceName;

    // Generate APKAM Key pair
    AtPkamKeyPair apkamKeyPair = AtChopsUtil.generateAtPkamKeyPair();
    enrollVerbBuilder.apkamPublicKey = apkamKeyPair.atPublicKey.publicKey;
    SymmetricKey apkamSymmetricKey =
        AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256);
    String defaultEncryptionPublicKey = await _getDefaultEncryptionPublicKey(
        atLookUp, atEnrollmentRequest.atSign);
    // Encrypting the Encryption Public key with APKAM Symmetric key.
    enrollVerbBuilder.encryptedAPKAMSymmetricKey =
        RSAPublicKey.fromString(defaultEncryptionPublicKey)
            .encrypt(apkamSymmetricKey.key);
    enrollVerbBuilder.otp = atEnrollmentRequest.otp;
    enrollVerbBuilder.namespaces = atEnrollmentRequest.namespaces;
    enrollVerbBuilder.apkamKeysExpiryDuration =
        atEnrollmentRequest.apkamKeysExpiryDuration;

    String? serverResponse =
        await _executeEnrollCommand(enrollVerbBuilder, atLookUp);
    var enrollJson = jsonDecode(serverResponse);
    var enrollmentIdFromServer = enrollJson[AtConstants.enrollmentId];
    var enrollStatus = getEnrollStatusFromString(enrollJson['status']);
    AtKeys atAuthKeys = AtKeys()
      ..apkamPrivateKey =
          AtBytes.fromString(apkamKeyPair.atPrivateKey.privateKey)
      ..apkamPublicKey = AtBytes.fromString(apkamKeyPair.atPublicKey.publicKey)
      ..apkamSymmetricKey = AtBytes.fromString(apkamSymmetricKey.key)
      ..enrollmentId = enrollJson[AtConstants.enrollmentId]
      ..defaultEncryptionPublicKey =
          AtBytes.fromString(defaultEncryptionPublicKey);

    return AtEnrollmentResponse(enrollmentIdFromServer, enrollStatus,
        atSign: atEnrollmentRequest.atSign,
        rootDomain: atEnrollmentRequest.rootDomain,
        atAuthKeys: atAuthKeys);
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

    InitialisationVector encryptionPrivateKeyIV =
        AtChopsUtil.generateRandomIV(16);
    // Fetch the encryptionPrivateKey from the atChops and encrypt with APKAM Symmetric key.
    String encryptedDefaultEncryptionPrivateKey = (await atLookUp.atChops
            ?.encryptString(
                atLookUp.atChops!.atChopsKeys.atEncryptionKeyPair!.atPrivateKey
                    .privateKey,
                EncryptionKeyType.aes256,
                keyName: 'apkamSymmetricKey',
                iv: encryptionPrivateKeyIV))
        ?.result;

    InitialisationVector selfEncryptionKeyIV = AtChopsUtil.generateRandomIV(16);
    // Fetch the selfEncryptionKey from the atChops and encrypt with APKAM Symmetric key.
    String encryptedDefaultSelfEncryptionKey = (await atLookUp.atChops
            ?.encryptString(
                atLookUp.atChops!.atChopsKeys.selfEncryptionKey!.key,
                EncryptionKeyType.aes256,
                keyName: 'apkamSymmetricKey',
                iv: selfEncryptionKeyIV))
        ?.result;

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

    enrollResponse = enrollResponse?.replaceFirst(RegExp(r'^data:'), '');
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

    enrollmentResponseStr =
        enrollmentResponseStr?.replaceFirst(RegExp(r'^data:'), '');
    var enrollmentJsonMap = jsonDecode(enrollmentResponseStr!);
    AtEnrollmentResponse enrollmentResponse = AtEnrollmentResponse(
        enrollmentJsonMap['enrollmentId'],
        _convertEnrollmentStatusToEnum(enrollmentJsonMap['status']));
    return enrollmentResponse;
  }

  @override
  Future<void> waitForApproval(
    AtEnrollmentResponse enrollmentResponse, {
    Duration retryInterval = const Duration(seconds: 2),
    bool logProgress = true,
    int maxRetries = 15,
  }) async {
    if (enrollmentResponse.atSign == null ||
        enrollmentResponse.atSign!.isEmpty) {
      throw InvalidRequestException(
          'atSign is not available in the enrollment response');
    }
    if (enrollmentResponse.rootDomain == null) {
      throw InvalidRequestException(
          'rootDomain is not available in the enrollment response');
    }

    var atLookup = AtLookupImpl(
      enrollmentResponse.atSign!,
      enrollmentResponse.rootDomain!.rootDomain,
      enrollmentResponse.rootDomain!.rootPort,
    );

    AtChopsKeys atChopsKeys = AtChopsKeys.create(
      AtEncryptionKeyPair.create(
          enrollmentResponse.atAuthKeys!.defaultEncryptionPublicKey!.toString(),
          ''),
      AtPkamKeyPair.create(
          enrollmentResponse.atAuthKeys!.apkamPublicKey!.toString(),
          enrollmentResponse.atAuthKeys!.apkamPrivateKey!.toString()),
    );
    atChopsKeys.apkamSymmetricKey = AESKey(
      enrollmentResponse.atAuthKeys!.apkamSymmetricKey!.toString(),
    );

    // Create AtChops instance and assign it to the lookup for PKAM authentication
    AtChopsImpl atChops = AtChopsImpl(atChopsKeys);
    atLookup.atChops = atChops;

    await _waitForPkamAuthSuccess(
      atLookup,
      enrollmentResponse.enrollmentId,
      retryInterval,
      logProgress: logProgress,
      maxRetries: maxRetries,
    );
  }

  Future<String> _getDefaultEncryptionPublicKey(
      AtLookUp atLookupImpl, String atSign) async {
    var lookupVerbBuilder = LookupVerbBuilder()
      ..atKey = (AtKey()
        ..key = 'publickey'
        ..sharedBy = atSign);
    String? lookupResult = await atLookupImpl.executeVerb(lookupVerbBuilder);
    if (lookupResult == null || lookupResult.isEmpty) {
      throw AtEnrollmentException(
          'Unable to lookup encryption public key. Server response is null/empty');
    }
    var defaultEncryptionPublicKey =
        lookupResult.replaceFirst(RegExp(r'^data:'), '');
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
    return enrollResult.replaceFirst(RegExp(r'^data:'), '');
  }

  /// Pkam auth will be retried until server approves/denies/expires the enrollment
  Future<void> _waitForPkamAuthSuccess(
    AtLookUp atLookUp,
    String enrollmentIdFromServer,
    Duration retryInterval, {
    bool logProgress = true,
    required int maxRetries,
  }) async {
    int retryAttempt = 0;
    AtSignLogger logger = AtSignLogger('AtEnrollmentImpl');
    while (true) {
      retryAttempt++;
      logger.info('Attempting pkam auth');
      if (logProgress) {
        _addProgress('PKAM', 'attempting PKAM auth', ProgressEventType.info);
        await waitBriefly();
      }
      bool pkamAuthSucceeded = false;
      try {
        // _attemptPkamAuth returns boolean value true when authentication is successful.
        // Returns UnAuthenticatedException when authentication fails.
        pkamAuthSucceeded = await atLookUp.pkamAuthenticate(
            enrollmentId: enrollmentIdFromServer);
      } on UnAuthenticatedException catch (e) {
        // Error codes AT0401 and AT0026 indicate authentication failure due to unapproved enrollment. Retry until the enrollment is approved.
        // The variable _pkamAuthSucceeded is false, allowing for PKAM authentication retries.
        // Avoid checking "retryAttempt > _maxActivationRetries" here, as we want to continue retrying until enrollment is approved.
        // The check for "retryAttempt > _maxActivationRetries" should only occur when the secondary server is unreachable due to network issues.
        if (e.message.contains('error:AT0401') ||
            e.message.contains('error:AT0026')) {
          logger.info('Pkam auth failed: ${e.message}');
        }
        // Error code AT0025 represents Enrollment denied. Therefore, no need to retry; throw exception.
        else if (e.message.contains('error:AT0025')) {
          throw AtEnrollmentException(
              'The enrollment: $enrollmentIdFromServer is denied');
        }
      } catch (e) {
        String message =
            'Exception occurred when authenticating the atSign caused by ${e.toString()}';
        if (retryAttempt > maxRetries) {
          message += ' Activation failed after $maxRetries attempts';
          logger.severe(message);
          _addProgress('PKAM', message, ProgressEventType.error);
          rethrow;
        }
        logger.severe(message);
      }
      if (pkamAuthSucceeded) {
        if (logProgress) {
          _addProgress(
              'PKAM',
              'Enrollment has been approved'
                  ' (PKAM auth success)',
              ProgressEventType.success);
        }
        logger.info('Authentication succeeded - request was approved');
        return;
      } else {
        if (logProgress) {
          _addProgress(
              'PKAM',
              'Auth failed, not yet approved.'
                  ' Will retry in ${retryInterval.inSeconds} seconds',
              ProgressEventType.info);
        }
        logger.info('Will retry pkam in ${retryInterval.inSeconds} seconds');
        await Future.delayed(retryInterval); // Delay and retry
      }
    }
  }

  Future<void> waitBriefly({int millis = 500}) async {
    await Future.delayed(Duration(milliseconds: millis));
  }
}
