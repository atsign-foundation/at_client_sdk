import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/src/auth_constants.dart' as auth_constants;
import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client_mobile/src/enrollment/at_enrollment_service.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_utils/at_utils.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AtEnrollmentServiceImpl implements AtEnrollmentService {
  final AtSignLogger _logger = AtSignLogger('AtEnrollmentServiceImpl');

  /// A flutter key-chain to store the enrollment keys (APKAM key-pair and APKAM
  /// Symmetric key) on submission of enrollment request.
  ///
  /// In the event of app closure following the submission of an enrollment request,
  /// the enrollment keys may be lost. To facilitate APKAM authentication retries,
  /// the keys are stored in the key-chain.
  /// Removal of the keys occurs upon successful approval or denial of the enrollment.
  final _enrollmentKeychainStore = FlutterSecureStorage();

  /// The maximum number of retries for verify approval/denial of an enrollment request
  final int _maxEnrollmentAuthenticationRetryInHours = 48;

  // Represents the delay to start next run.
  int _secondsUntilNextRun = 1;

  /// A boolean flag which represents the "enrollmentAuthScheduler" running status.
  bool _enrollmentAuthSchedulerStarted = false;

  /// The key name which stores the [_EnrollmentInfo] in the key-chain.
  final enrollmentInfoKey = 'enrollmentInfo';

  late AtEnrollmentImpl _atEnrollmentImpl;
  AtLookUp? _atLookUp;

  String _atSign;
  final AtClientPreference _atClientPreference;

  Function? enrollmentStatusCallback;

  AtEnrollmentServiceImpl(this._atSign, this._atClientPreference) {
    // Prefix "@" to the atSign is missed.
    _atSign = AtUtils.fixAtSign(_atSign);
    _atEnrollmentImpl = AtEnrollmentImpl(_atSign);
  }

  @override
  Future<EnrollResponse> submitEnrollmentRequest(
      AtEnrollmentRequest atEnrollmentRequest) async {
    _atLookUp ??= AtLookupImpl(
        _atSign, _atClientPreference.rootDomain, _atClientPreference.rootPort);
    AtEnrollmentResponse atEnrollmentResponse = await _atEnrollmentImpl
        .submitEnrollment(atEnrollmentRequest, _atLookUp!);

    _EnrollmentInfo enrollmentInfo = _EnrollmentInfo(
        atEnrollmentResponse.enrollmentId,
        atEnrollmentResponse.atAuthKeys!,
        DateTime.now().toUtc().millisecondsSinceEpoch);
    // Store the enrollment keys into keychain
    await _enrollmentKeychainStore.write(
        key: enrollmentInfoKey, value: jsonEncode(enrollmentInfo));
    // After submitting an enrollment, start the "Authentication Scheduler" which
    // periodically checks if enrollment is approved.
    initEnrollmentAuthScheduler();

    return EnrollResponse(
        atEnrollmentResponse.enrollmentId, atEnrollmentResponse.enrollStatus);
  }

  @override
  void initEnrollmentAuthScheduler() {
    Timer(Duration(seconds: _secondsUntilNextRun), () async {
      if (_enrollmentAuthSchedulerStarted) {
        _logger.finest(
            'Enrollment Auth Scheduler is currently in-progress. Skipping this run');
        return;
      }
      await _enrollmentAuthenticationScheduler();
    });
  }

  Future<void> _enrollmentAuthenticationScheduler() async {
    try {
      _enrollmentAuthSchedulerStarted = true;
      String? enrollmentInfoJsonString =
          await _enrollmentKeychainStore.read(key: enrollmentInfoKey);
      // If there is no enrollment data in keychain, then there is no
      // pending enrollment to retry authentication. So, stop the scheduler.
      if (enrollmentInfoJsonString == null) {
        _logger
            .finest('No pending enrollments to retry. Stopping the scheduler');
        return;
      }
      _EnrollmentInfo enrollmentInfo =
          _EnrollmentInfo.fromJson(jsonDecode(enrollmentInfoJsonString));
      // If "_maxEnrollmentAuthenticationRetryInHours" exceeds 48 hours then
      // stop retrying for enrollment approval and remove enrollmentInfo from
      // key-chain.
      if (DateTime.now()
              .toUtc()
              .difference(DateTime.fromMillisecondsSinceEpoch(
                  enrollmentInfo.enrollmentSubmissionTimeEpoch))
              .inHours >=
          _maxEnrollmentAuthenticationRetryInHours) {
        _logger.finest(
            'EnrollmentId: ${enrollmentInfo.enrollmentId} has reached the maximum number of retries. Retry attempts have been stopped.');
        // If enrollment retry has reached the limit, do no retry. Remove
        // the enrollment info from the keychain manager.
        await _enrollmentKeychainStore.delete(key: enrollmentInfoKey);
        if (enrollmentStatusCallback != null) {
          enrollmentStatusCallback!(EnrollmentStatusResponse(
              enrollmentInfo.enrollmentId, EnrollStatus.expired));
        }
        return;
      }

      _atLookUp ??= AtLookupImpl(_atSign, _atClientPreference.rootDomain,
          _atClientPreference.rootPort);
      // Create the AtChops instance with the new APKAM keys to verify if enrollment
      // is approved.
      // If enrollment is approved, then pkam authentication will be successful.
      AtChopsKeys atChopsKeys = AtChopsKeys.create(
          null,
          AtPkamKeyPair.create(enrollmentInfo.atAuthKeys.apkamPublicKey!,
              enrollmentInfo.atAuthKeys.apkamPrivateKey!));
      atChopsKeys.apkamSymmetricKey =
          AESKey(enrollmentInfo.atAuthKeys.apkamSymmetricKey!);
      _atLookUp?.atChops = AtChopsImpl(atChopsKeys);

      bool? isAuthenticated = false;

      try {
        isAuthenticated = await _atLookUp?.pkamAuthenticate(
            enrollmentId: enrollmentInfo.enrollmentId);
      } on UnAuthenticatedException catch (e) {
        // The enrollment is denied. So do not retry and remove the
        // enrollment info from the keychain manager.
        if (e.message.contains('error:AT0025')) {
          _logger.info("The enrollment : ${enrollmentInfoKey} is denied. Stopping the auth scheduler");
          await _enrollmentKeychainStore.delete(key: enrollmentInfoKey);
          if (enrollmentStatusCallback != null) {
            enrollmentStatusCallback!(EnrollmentStatusResponse(
                enrollmentInfo.enrollmentId, EnrollStatus.denied));
          }
        }
        _logger.finest(
            'Failed to authenticate with enrollmentId - ${enrollmentInfo.enrollmentId}');
      }
      if (isAuthenticated == true) {
        await _handleAuthenticatedEnrollment(enrollmentInfo);
        if (enrollmentStatusCallback != null) {
          enrollmentStatusCallback!(EnrollmentStatusResponse(
              enrollmentInfo.enrollmentId, EnrollStatus.approved));
        }
        // Authentication is completed successfully and APKAM keys file
        // is generated. Stop the scheduler.
        return;
      }
      _logger.info(
          'Enrollment: ${enrollmentInfo.enrollmentId} failed to authenticate. Retrying again');
      await _enrollmentKeychainStore.write(
          key: enrollmentInfoKey, value: jsonEncode(enrollmentInfo));
      _secondsUntilNextRun = _secondsUntilNextRun * 2;
      initEnrollmentAuthScheduler();
    } finally {
      _enrollmentAuthSchedulerStarted = false;
    }
  }

  Future<void> _handleAuthenticatedEnrollment(
      _EnrollmentInfo enrollmentInfo) async {
    _logger.info('Enrollment: ${enrollmentInfo.enrollmentId} is authenticated');
    // Get the decrypted (plain text) "Encryption Private Key" and "AES Symmetric Key"
    // from the secondary server.
    enrollmentInfo.atAuthKeys.defaultEncryptionPrivateKey =
        await _getDefaultEncryptionPrivateKey(
            enrollmentInfo.enrollmentId, _atLookUp!.atChops!);
    enrollmentInfo.atAuthKeys.defaultSelfEncryptionKey =
        await _getDefaultSelfEncryptionKey(
            enrollmentInfo.enrollmentId, _atLookUp!.atChops!);

    await _generateAtKeys(enrollmentInfo.atAuthKeys, _atLookUp!.atChops!);
    // Remove the keys from key-chain manager
    await _enrollmentKeychainStore.delete(key: enrollmentInfoKey);
    _atLookUp?.close();
  }

  /// On approving an enrollment request, generates atKeys file which is used to
  /// authenticate an atSign via APKAM.
  Future<void> _generateAtKeys(AtAuthKeys atAuthKeys, AtChops atChops) async {
    Map<String, String?> apkamBackupKeys = atAuthKeys.toJson();

    atChops.atChopsKeys.atEncryptionKeyPair = AtEncryptionKeyPair.create(
        atAuthKeys.defaultEncryptionPublicKey!,
        atAuthKeys.defaultEncryptionPrivateKey!);

    atChops.atChopsKeys.selfEncryptionKey =
        AESKey(atAuthKeys.defaultSelfEncryptionKey!);

    // Add atSign to the backup keys file.
    apkamBackupKeys[_atSign] = atChops.atChopsKeys.selfEncryptionKey!.key;

    try {
      apkamBackupKeys[auth_constants.defaultEncryptionPublicKey] = atChops
          .encryptString(
              atAuthKeys.defaultEncryptionPublicKey!, EncryptionKeyType.aes256,
              keyName: 'selfEncryptionKey', iv: AtChopsUtil.generateIVLegacy())
          .result;

      apkamBackupKeys[auth_constants.defaultEncryptionPrivateKey] = atChops
          .encryptString(
              atAuthKeys.defaultEncryptionPrivateKey!, EncryptionKeyType.aes256,
              keyName: 'selfEncryptionKey', iv: AtChopsUtil.generateIVLegacy())
          .result;

      apkamBackupKeys[auth_constants.apkamPublicKey] = atChops
          .encryptString(atAuthKeys.apkamPublicKey!, EncryptionKeyType.aes256,
              keyName: 'selfEncryptionKey', iv: AtChopsUtil.generateIVLegacy())
          .result;

      apkamBackupKeys[auth_constants.apkamPrivateKey] = atChops
          .encryptString(atAuthKeys.apkamPrivateKey!, EncryptionKeyType.aes256,
              keyName: 'selfEncryptionKey', iv: AtChopsUtil.generateIVLegacy())
          .result;
    } on Exception catch (e) {
      _logger.severe(
          'Failed to generate the atKeys file for enrollmentId - ${atAuthKeys.enrollmentId} caused by ${e.toString()}');
      return;
    } on Error catch (e) {
      _logger.severe(
          'Failed to generate the atKeys file for enrollmentId - ${atAuthKeys.enrollmentId} caused by ${e.toString()}');
      return;
    }

    String atKeysEncodedString = jsonEncode(apkamBackupKeys);
    String fileName = '${_atSign}_apkam_key';
    String extension = '.atKeys';
    String atKeysFilePath = await FileSaver.instance.saveFile(
        name: fileName,
        bytes: Uint8List.fromList(atKeysEncodedString.codeUnits),
        ext: extension,
        mimeType: MimeType.other);
    _logger.info(
        'atKeys file for enrollment id - ${atAuthKeys.enrollmentId} is saved in $atKeysFilePath');
  }

  /// Retrieves the encrypted "encryption private key" from the server and decrypts.
  /// This process involves using the APKAM symmetric key for decryption.
  /// Returns the original "encryption private key" after decryption.
  Future<String> _getDefaultEncryptionPrivateKey(
      String enrollmentIdFromServer, AtChops atChops) async {
    var privateKeyCommand =
        'keys:get:keyName:$enrollmentIdFromServer.${AtConstants.defaultEncryptionPrivateKey}.__manage$_atSign\n';
    String encryptionPrivateKeyFromServer;
    try {
      var getPrivateKeyResult =
          await _atLookUp?.executeCommand('$privateKeyCommand\n', auth: true);
      if (getPrivateKeyResult == null || getPrivateKeyResult.isEmpty) {
        throw AtEnrollmentException('$privateKeyCommand returned null/empty');
      }
      getPrivateKeyResult = getPrivateKeyResult.replaceFirst('data:', '');
      var privateKeyResultJson = jsonDecode(getPrivateKeyResult);
      encryptionPrivateKeyFromServer = privateKeyResultJson['value'];
    } on Exception catch (e) {
      throw AtEnrollmentException(
          'Exception while getting encrypted private key/self key from server: $e');
    }
    AtEncryptionResult? atEncryptionResult = atChops.decryptString(
        encryptionPrivateKeyFromServer, EncryptionKeyType.aes256,
        keyName: 'apkamSymmetricKey', iv: AtChopsUtil.generateIVLegacy());
    return atEncryptionResult.result;
  }

  /// Returns the decrypted selfEncryptionKey.
  /// Fetches the encrypted selfEncryptionKey from the server and decrypts the
  /// key with APKAM Symmetric key to get the original selfEncryptionKey.
  Future<String> _getDefaultSelfEncryptionKey(
      String enrollmentIdFromServer, AtChops atChops) async {
    var selfEncryptionKeyCommand =
        'keys:get:keyName:$enrollmentIdFromServer.${AtConstants.defaultSelfEncryptionKey}.__manage$_atSign\n';
    String selfEncryptionKeyFromServer;
    try {
      String? encryptedSelfEncryptionKey = await _atLookUp
          ?.executeCommand('$selfEncryptionKeyCommand\n', auth: true);
      if (encryptedSelfEncryptionKey == null ||
          encryptedSelfEncryptionKey.isEmpty) {
        throw AtEnrollmentException(
            '$selfEncryptionKeyCommand returned null/empty');
      }
      encryptedSelfEncryptionKey =
          encryptedSelfEncryptionKey.replaceFirst('data:', '');
      var selfEncryptionKeyResultJson = jsonDecode(encryptedSelfEncryptionKey);
      selfEncryptionKeyFromServer = selfEncryptionKeyResultJson['value'];
    } on Exception catch (e) {
      throw AtEnrollmentException(
          'Exception while getting encrypted private key/self key from server: $e');
    }
    AtEncryptionResult? atEncryptionResult = atChops.decryptString(
        selfEncryptionKeyFromServer, EncryptionKeyType.aes256,
        keyName: 'apkamSymmetricKey', iv: AtChopsUtil.generateIVLegacy());
    return atEncryptionResult.result;
  }

  @override
  Future<AtEnrollmentResponse> manageEnrollmentApproval(
      AtEnrollmentRequest atEnrollmentRequest) {
    if (_atLookUp == null) {
      _initAtLookup();
    }
    return _atEnrollmentImpl.manageEnrollmentApproval(
        atEnrollmentRequest, _atLookUp!);
  }

  _initAtLookup() {
    AtClient atClient = AtClientManager.getInstance().atClient;
    _atLookUp = AtLookupImpl(
        atClient.getCurrentAtSign()!,
        atClient.getPreferences()!.rootDomain,
        atClient.getPreferences()!.rootPort);

    _atLookUp!.atChops = atClient.atChops;
  }
}

/// Class representing the enrollment details to store in the keychain.
class _EnrollmentInfo {
  String enrollmentId;
  AtAuthKeys atAuthKeys;
  int enrollmentSubmissionTimeEpoch;

  _EnrollmentInfo(
      this.enrollmentId, this.atAuthKeys, this.enrollmentSubmissionTimeEpoch);

  Map<String, dynamic> toJson() {
    return {
      'enrollmentId': enrollmentId,
      'atAuthKeys': atAuthKeys.toJson(),
      'enrollmentSubmissionTimeEpoch': enrollmentSubmissionTimeEpoch
    };
  }

  _EnrollmentInfo.fromJson(Map<String, dynamic> json)
      : enrollmentId = json['enrollmentId'],
        atAuthKeys = AtAuthKeys.fromJson(json['atAuthKeys']),
        enrollmentSubmissionTimeEpoch = json['enrollmentSubmissionTimeEpoch'];
}

class EnrollmentStatusResponse {
  String enrollmentKey;
  EnrollStatus enrollStatus;

  EnrollmentStatusResponse(this.enrollmentKey, this.enrollStatus);
}
