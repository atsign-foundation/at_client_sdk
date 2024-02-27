import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/src/auth_constants.dart' as auth_constants;
import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client_mobile/src/enrollment/at_enrollment_service.dart';
import 'package:at_file_saver/at_file_saver.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_utils/at_utils.dart';
import 'package:biometric_storage/biometric_storage.dart';

class AtEnrollmentServiceImpl implements AtEnrollmentService {
  final AtSignLogger _logger = AtSignLogger('AtEnrollmentServiceImpl');

  /// A flutter key-chain to store the enrollment keys (APKAM key-pair and APKAM
  /// Symmetric key) on submission of enrollment request.
  ///
  /// In the event of app closure following the submission of an enrollment request,
  /// the enrollment keys may be lost. To facilitate APKAM authentication retries,
  /// the keys are stored in the key-chain.
  /// Removal of the keys occurs upon successful approval or denial of the enrollment.
  final _enrollmentKeychainStore = BiometricStorage();

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

  final Map<String, Completer<EnrollmentStatus>> _outcomes = {};

  AtEnrollmentServiceImpl(this._atSign, this._atClientPreference) {
    // Prefix "@" to the atSign is missed.
    _atSign = AtUtils.fixAtSign(_atSign);
    _atEnrollmentImpl = AtEnrollmentImpl(_atSign);
  }

  @override
  Future<String> submitEnrollmentRequest(
      AtEnrollmentRequest atEnrollmentRequest) async {
    // Only one enrollment request can be submitted at a time.
    // Subsequent requests cannot be submitted until the pending one is fulfilled.
    var enrollmentStore = await _getEnrollmentStorage();
    String? enrollmentInfoJsonString = await enrollmentStore.read();
    // if enrollmentInfoJsonString is not null, it indicates that there is a pending
    // enrollment request. So, do not allow another enrollment request.
    if (enrollmentInfoJsonString != null) {
      throw InvalidRequestException(
          'Cannot submit new enrollment request until the pending enrollment request is fulfilled');
    }
    _atLookUp ??= AtLookupImpl(
        _atSign, _atClientPreference.rootDomain, _atClientPreference.rootPort);
    AtEnrollmentResponse atEnrollmentResponse = await _atEnrollmentImpl
        .submitEnrollment(atEnrollmentRequest, _atLookUp!);

    EnrollmentInfo enrollmentInfo = EnrollmentInfo(
      atEnrollmentResponse.enrollmentId,
      atEnrollmentResponse.atAuthKeys!,
      DateTime.now().toUtc().millisecondsSinceEpoch,
      atEnrollmentRequest.namespaces,
    );
    // Store the enrollment keys into keychain
    await enrollmentStore.write(jsonEncode(enrollmentInfo));

    return atEnrollmentResponse.enrollmentId;
  }

  @override
  Future<EnrollmentStatus> getFinalEnrollmentStatus() async {
    var enrollmentStore = await _getEnrollmentStorage();

    String? enrollmentInfoJsonString = await enrollmentStore.read();
    // If there is no enrollment data in keychain, then the enrollment
    // is expired and hence deleted from the keychain.
    if (enrollmentInfoJsonString == null) {
      _logger.finest(
          'No pending enrollment found. Returning ${EnrollmentStatus.expired}');
      return Future.value(EnrollmentStatus.expired);
    }
    EnrollmentInfo enrollmentInfo =
        EnrollmentInfo.fromJson(jsonDecode(enrollmentInfoJsonString));
    // "putIfAbsent" to avoid creating a new Completer for the same enrollmentId
    // when getFinalEnrollmentStatus is called more than once.
    _outcomes.putIfAbsent(enrollmentInfo.enrollmentId, () => Completer());
    // Init scheduler which poll authentication at regular intervals
    _initEnrollmentAuthScheduler(enrollmentInfo);

    return _outcomes[enrollmentInfo.enrollmentId]!.future;
  }

  /// Runs a scheduler which check if an enrollment is approved.
  ///
  /// Retrieves the [EnrollmentInfo] from the key-chain manager. If
  /// If an enrollment is approved, then atKeys file is generated and removes the [EnrollmentInfo] from
  /// the key-chain.
  ///
  /// Handles the scheduled enrollment authentication.
  ///
  /// - This method is invoked by a timer, attempting to authenticate an enrollment
  /// based on the [EnrollmentInfo] stored in the key-chain manager
  ///
  /// - If there is no pending enrollment to retry authentication, the scheduler stops.
  /// - If the maximum retry count for enrollment authentication is reached,
  ///   the enrollment info is removed from the flutter key-chain, and the scheduler stops.
  /// - If authentication succeeds, then generated the atKeys file for authentication
  ///   and removes the enrollment info from the key-chain manager and stops the scheduler.
  /// - If authentication fails, the method retries with an incremented retry count.
  void _initEnrollmentAuthScheduler(EnrollmentInfo _enrollmentInfo) {
    Timer(Duration(seconds: _secondsUntilNextRun), () async {
      if (_enrollmentAuthSchedulerStarted) {
        _logger.finest(
            'Enrollment Auth Scheduler is currently in-progress. Skipping this run');
        return;
      }
      await _enrollmentAuthenticationScheduler(_enrollmentInfo);
    });
  }

  Future<void> _enrollmentAuthenticationScheduler(
      EnrollmentInfo enrollmentInfo) async {
    var enrollmentStore = await _getEnrollmentStorage();

    try {
      // If "_canProceedWithAuthentication" returns false,
      // stop the enrollment authentication scheduler.
      if (!(await _canProceedWithAuthentication(enrollmentInfo))) {
        return;
      }

      bool? isAuthenticated = await _performAPKAMAuthentication(enrollmentInfo);
      if (isAuthenticated == true) {
        await _handleAuthenticatedEnrollment(enrollmentInfo);
        // Authentication is completed successfully and APKAM keys file
        // is generated. Stop the scheduler.
        return;
      }
      _logger.info(
          'Enrollment: ${enrollmentInfo.enrollmentId} failed to authenticate. Retrying again');
      // If in case the app is reset, the enrollmentInfo state should be preserved. Hence
      // store the updated enrollment info into keychain.
      await enrollmentStore.write(jsonEncode(enrollmentInfo));
      _secondsUntilNextRun = _secondsUntilNextRun * 2;
      _initEnrollmentAuthScheduler(enrollmentInfo);
    } finally {
      _enrollmentAuthSchedulerStarted = false;
    }
  }

  Future<bool> _canProceedWithAuthentication(
      EnrollmentInfo enrollmentInfo) async {
    var enrollmentStore = await _getEnrollmentStorage();
    // If "_maxEnrollmentAuthenticationRetryInHours" exceeds 48 hours then
    // stop retrying for enrollment approval and remove enrollmentInfo from
    // keychain.
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
      await enrollmentStore.delete();
      return false;
    }
    return true;
  }

  Future<bool?> _performAPKAMAuthentication(
      EnrollmentInfo enrollmentInfo) async {
    _atLookUp ??= AtLookupImpl(
        _atSign, _atClientPreference.rootDomain, _atClientPreference.rootPort);
    // Create the AtChops instance with the new APKAM keys to verify if enrollment
    // is approved.
    // If enrollment is approved, then apkam authentication will be successful.
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
    } on UnAuthenticatedException {
      _logger.finest(
          'Failed to authenticate with enrollmentId - ${enrollmentInfo.enrollmentId}');
    }
    return isAuthenticated;
  }

  Future<void> _handleAuthenticatedEnrollment(
      EnrollmentInfo enrollmentInfo) async {
    _logger.info('Enrollment: ${enrollmentInfo.enrollmentId} is authenticated');

    var enrollmentStore = await _getEnrollmentStorage();
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
    await enrollmentStore.delete();
    _outcomes[enrollmentInfo.enrollmentId]?.complete(EnrollmentStatus.approved);
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
      fileName,
      Uint8List.fromList(atKeysEncodedString.codeUnits),
      extension,
      mimeType: MimeType.OTHER,
    );
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

  Future<AtEnrollmentResponse> approve(
      AtEnrollmentRequest atEnrollmentRequest) {
    return _manageEnrollmentApproval(atEnrollmentRequest);
  }

  Future<AtEnrollmentResponse> deny(AtEnrollmentRequest atEnrollmentRequest) {
    return _manageEnrollmentApproval(atEnrollmentRequest);
  }

  Future<AtEnrollmentResponse> _manageEnrollmentApproval(
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

  Future<BiometricStorageFile> _getEnrollmentStorage() async {
    final data = await _enrollmentKeychainStore.getStorage(
      '${_atSign}_$enrollmentInfoKey',
      options: StorageFileInitOptions(
        authenticationRequired: false,
      ),
    );

    return data;
  }

  @override
  Future<EnrollmentInfo?> getSentEnrollmentRequest() async {
    var enrollmentStore = await _getEnrollmentStorage();
    String? enrollmentInfoJsonString = await enrollmentStore.read();
    if (enrollmentInfoJsonString != null) {
      EnrollmentInfo enrollmentInfo =
          EnrollmentInfo.fromJson(jsonDecode(enrollmentInfoJsonString));
      return enrollmentInfo;
    }
  }
}

/// Class representing the enrollment details to store in the keychain.
class EnrollmentInfo {
  String enrollmentId;
  AtAuthKeys atAuthKeys;
  int enrollmentSubmissionTimeEpoch;
  Map<String, dynamic>? namespace;

  EnrollmentInfo(
    this.enrollmentId,
    this.atAuthKeys,
    this.enrollmentSubmissionTimeEpoch,
    this.namespace,
  );

  Map<String, dynamic> toJson() {
    return {
      'enrollmentId': enrollmentId,
      'atAuthKeys': atAuthKeys.toJson(),
      'enrollmentSubmissionTimeEpoch': enrollmentSubmissionTimeEpoch,
      'namespace': namespace
    };
  }

  EnrollmentInfo.fromJson(Map<String, dynamic> json)
      : enrollmentId = json['enrollmentId'],
        atAuthKeys = AtAuthKeys.fromJson(json['atAuthKeys']),
        enrollmentSubmissionTimeEpoch = json['enrollmentSubmissionTimeEpoch'],
        namespace = json['namespace'];
}