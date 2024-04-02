import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_client_mobile/src/atsign_key.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';
import 'package:biometric_storage/biometric_storage.dart';
import 'package:flutter/cupertino.dart';

class AtAuthServiceImpl implements AtAuthService {
  final AtSignLogger _logger = AtSignLogger('AtAuthServiceImpl');

  AtServiceFactory? atServiceFactory;
  AtClient? _atClient;

  @visibleForTesting
  AtLookUp? atLookUp;

  String _atSign;
  final AtClientPreference _atClientPreference;

  KeyChainManager keyChainManager = KeyChainManager.getInstance();
  AtClientManager atClientManager = AtClientManager.getInstance();
  late AtAuth atAuth;
  late AtEnrollmentBase atEnrollmentBase;

  /// A flutter key-chain to store the enrollment keys (APKAM key-pair and APKAM
  /// Symmetric key) on submission of enrollment request.
  ///
  /// In the event of app closure following the submission of an enrollment request,
  /// the enrollment keys may be lost. To facilitate APKAM authentication retries,
  /// the keys are stored in the key-chain.
  /// Removal of the keys occurs upon successful approval or denial of the enrollment.
  @visibleForTesting
  BiometricStorage enrollmentKeychainStore = BiometricStorage();

  /// The maximum number of retries for verify approval/denial of an enrollment request
  final int _maxEnrollmentAuthenticationRetryInHours = 48;

  // Represents the delay to start next run.
  int _secondsUntilNextRun = 1;

  /// A boolean flag which represents the "enrollmentAuthScheduler" running status.
  bool _enrollmentAuthSchedulerStarted = false;

  /// The key name which stores the [_EnrollmentInfo] in the key-chain.
  final enrollmentInfoKey = 'enrollmentInfo';

  final Map<String, Completer<EnrollmentStatus>> _outcomes = {};

  AtAuthServiceImpl(this._atSign, this._atClientPreference) {
    // If the '@' symbol is omitted, it leads to an incorrect format for the AtKey when retrieving the
    // encrypted defaultEncryptionPrivateKey and encrypted defaultSelfEncryptionKey.
    if (!_atSign.startsWith('@')) {
      _atSign = '@$_atSign';
    }
    atAuth = atAuthBase.atAuth();
    atEnrollmentBase = atAuthBase.atEnrollment(_atSign);
  }

  @override
  Future<AtAuthResponse> authenticate(AtAuthRequest atAuthRequest) async {
    // If the user does not provide the keys data then fetch for the keys in the
    // keychain manager.
    // User provides keys data either by
    //  - 1. atAuthRequest.atKeysFilePath - The file path of .atKeys file.
    //  - 2. atAuthRequest.atAuthKeys - The AtAuthKeys instance which contains the keys
    //  - 3. atAuthRequest.encryptedKeysMap - Provide the contents of atKeys file which
    //    contains keys in encrypted format
    if (atAuthRequest.atKeysFilePath == null &&
        atAuthRequest.atAuthKeys == null &&
        atAuthRequest.encryptedKeysMap == null) {
      _logger.info(
          'Fetching the keys from Keychain Manager of atSign: ${atAuthRequest.atSign}');
      atAuthRequest.atAuthKeys = await _fetchKeysFromKeychainManager();
    }
    // Invoke authenticate method in AtAuth package.
    AtAuthResponse atAuthResponse = await atAuth.authenticate(atAuthRequest);
    // If authentication is failed, return the atAuthResponse. Do nothing.
    if (atAuthResponse.isSuccessful == false) {
      return atAuthResponse;
    }
    // If authentication is successful, initialize AtClient instance.
    await _init(atAuth.atChops!, enrollmentId: atAuthResponse.enrollmentId);
    // When an atSign is authenticated via the .atKeys on a new device, the keys
    // will not be present in keychain manager. Add keys to key-chain manager.
    AtsignKey? atSignKey = await keyChainManager.readAtsign(name: _atSign);
    if (atSignKey == null) {
      await _storeToKeyChainManager(_atSign, atAuthResponse.atAuthKeys);
    }
    return atAuthResponse;
  }

  Future<AtAuthKeys> _fetchKeysFromKeychainManager() async {
    AtsignKey? atSignKey = await keyChainManager.readAtsign(name: _atSign);
    if (atSignKey == null) {
      throw AtAuthenticationException(
          'Failed to authenticate. Keys not found in Keychain manager for atSign: $_atSign');
    }

    AtAuthKeys atAuthKeys = AtAuthKeys()
      ..apkamPrivateKey = atSignKey.pkamPrivateKey
      ..apkamPublicKey = atSignKey.pkamPublicKey
      ..defaultEncryptionPrivateKey = atSignKey.encryptionPrivateKey
      ..defaultEncryptionPublicKey = atSignKey.encryptionPublicKey
      ..defaultSelfEncryptionKey = atSignKey.selfEncryptionKey
      ..apkamSymmetricKey = atSignKey.apkamSymmetricKey
      ..enrollmentId = atSignKey.enrollmentId;

    return atAuthKeys;
  }

  @override
  Future<bool> isOnboarded(String atSign) async {
    AtsignKey? atsignKey = await keyChainManager.readAtsign(name: atSign);
    if (atsignKey == null) {
      return false;
    }
    if (atsignKey.encryptionPublicKey == null ||
        atsignKey.encryptionPublicKey!.isEmpty) {
      return false;
    }
    return true;
  }

  @override
  Future<AtOnboardingResponse> onboard(AtOnboardingRequest atOnboardingRequest,
      {String? cramSecret}) async {
    if (cramSecret == null || cramSecret.isEmpty) {
      throw AtException(
          'CRAM Secret cannot be null or empty for atSign: $_atSign');
    }
    AtOnboardingResponse atOnboardingResponse =
        await atAuth.onboard(atOnboardingRequest, cramSecret);
    // If onboarding is not successful, return the onboarding response
    // with the isSuccessful set to false.
    if (!atOnboardingResponse.isSuccessful) {
      return atOnboardingResponse;
    }
    if (atAuth.atChops == null) {
      throw AtAuthenticationException(
          'Failed to onboard atSign: $_atSign. AtChops is not initialized in AtAuth Package');
    }
    await _init(atAuth.atChops!,
        enrollmentId: atOnboardingResponse.enrollmentId);
    await _storeToKeyChainManager(
        atOnboardingResponse.atSign, atOnboardingResponse.atAuthKeys);
    await _persistKeysLocalSecondary(atOnboardingResponse.atAuthKeys);
    return atOnboardingResponse;
  }

  /// Stores the atKeys to Key-Chain Manager.
  Future<void> _storeToKeyChainManager(
      String atSign, AtAuthKeys? atAuthKeys) async {
    if (atAuthKeys == null) {
      throw AtException(
          'Failed to store keys in Keychain manager for atSign: $_atSign. AtAuthKeys instance is null');
    }

    var atSignItem = await keyChainManager.readAtsign(name: atSign) ??
        AtsignKey(atSign: atSign);
    atSignItem = atSignItem.copyWith(
        pkamPrivateKey: atAuthKeys.apkamPrivateKey,
        pkamPublicKey: atAuthKeys.apkamPublicKey,
        encryptionPrivateKey: atAuthKeys.defaultEncryptionPrivateKey,
        encryptionPublicKey: atAuthKeys.defaultEncryptionPublicKey,
        selfEncryptionKey: atAuthKeys.defaultSelfEncryptionKey,
        apkamSymmetricKey: atAuthKeys.apkamSymmetricKey,
        enrollmentId: atAuthKeys.enrollmentId);

    await keyChainManager.storeAtSign(atSign: atSignItem);
  }

  Future<void> _persistKeysLocalSecondary(AtAuthKeys? atAuthKeys) async {
    if (atAuthKeys == null) {
      throw AtException(
          'Failed to store keys in Keychain manager for atSign: $_atSign. AtAuthKeys instance is null');
    }

    await _atClient!
        .getLocalSecondary()!
        .putValue(AtConstants.atPkamPublicKey, atAuthKeys.apkamPublicKey!);

    // pkam private will not be available in case of secure element
    if (atAuthKeys.apkamPrivateKey != null) {
      await _atClient!
          .getLocalSecondary()!
          .putValue(AtConstants.atPkamPrivateKey, atAuthKeys.apkamPrivateKey!);
    }

    await _atClient!.getLocalSecondary()!.putValue(
        AtConstants.atEncryptionPrivateKey,
        atAuthKeys.defaultEncryptionPrivateKey!);

    var updateBuilder = UpdateVerbBuilder()
      ..atKey = AtKey.public('publickey', sharedBy: _atSign).build();
    updateBuilder.atKey.metadata.ttr = -1;
    updateBuilder.value = atAuthKeys.defaultEncryptionPublicKey;

    await _atClient!
        .getLocalSecondary()!
        .executeVerb(updateBuilder, sync: true);

    await _atClient!.getLocalSecondary()!.putValue(
        AtConstants.atEncryptionSelfKey, atAuthKeys.defaultSelfEncryptionKey!);
  }

  Future<void> _init(AtChops atChops, {String? enrollmentId}) async {
    await _initAtClient(atChops, enrollmentId: enrollmentId);
    atLookUp!.atChops = atChops;
    _atClient!.atChops = atChops;
  }

  Future<void> _initAtClient(AtChops atChops, {String? enrollmentId}) async {
    AtClientManager atClientManager = AtClientManager.getInstance();
    await atClientManager.setCurrentAtSign(
        _atSign, _atClientPreference.namespace, _atClientPreference,
        atChops: atChops,
        serviceFactory: atServiceFactory,
        enrollmentId: enrollmentId);
    // ??= to support mocking
    atLookUp ??= atClientManager.atClient.getRemoteSecondary()?.atLookUp;
    atLookUp?.enrollmentId = enrollmentId;
    atLookUp?.signingAlgoType = _atClientPreference.signingAlgoType;
    atLookUp?.hashingAlgoType = _atClientPreference.hashingAlgoType;
    _atClient ??= atClientManager.atClient;
  }

  @override
  Future<AtEnrollmentResponse> enroll(EnrollmentRequest enrollmentRequest,
      {String? keysFilePath}) async {
    // Only one enrollment request can be submitted at a time.
    // Subsequent requests cannot be submitted until the pending one is fulfilled.

    String? enrollmentInfoJsonString =
        await keyChainManager.readFromEnrollmentStore(_atSign);
    // if enrollmentInfoJsonString is not null, it indicates that there is a pending
    // enrollment request. So, do not allow another enrollment request.
    if (enrollmentInfoJsonString != null) {
      throw InvalidRequestException(
          'Cannot submit new enrollment request until the pending enrollment request is fulfilled');
    }
    atLookUp ??= AtLookupImpl(
        _atSign, _atClientPreference.rootDomain, _atClientPreference.rootPort);
    AtEnrollmentResponse atEnrollmentResponse =
        await atEnrollmentBase.submit(enrollmentRequest, atLookUp!);
    await atLookUp?.close();
    EnrollmentInfo enrollmentInfo = EnrollmentInfo(
      atEnrollmentResponse.enrollmentId,
      atEnrollmentResponse.atAuthKeys!,
      DateTime.now().toUtc().millisecondsSinceEpoch,
      enrollmentRequest.namespaces,
    );
    enrollmentInfo.keysFilePath = keysFilePath;
    // Store the enrollment keys into keychain to generate the AtKeys file if an enrollment is approved.
    await keyChainManager.writeToEnrollmentStore(
        _atSign, jsonEncode(enrollmentInfo));
    return atEnrollmentResponse;
  }

  @override
  Future<EnrollmentStatus> getFinalEnrollmentStatus() async {
    String? enrollmentInfoJsonString =
        await keyChainManager.readFromEnrollmentStore(_atSign);
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

  @override
  Future<EnrollmentInfo?> getSentEnrollmentRequest() async {
    String? enrollmentInfoJsonString =
        await keyChainManager.readFromEnrollmentStore(_atSign);
    if (enrollmentInfoJsonString != null) {
      EnrollmentInfo enrollmentInfo =
          EnrollmentInfo.fromJson(jsonDecode(enrollmentInfoJsonString));
      return enrollmentInfo;
    }
    return null;
  }

  void _initEnrollmentAuthScheduler(EnrollmentInfo enrollmentInfo) {
    Timer(Duration(seconds: _secondsUntilNextRun), () async {
      if (_enrollmentAuthSchedulerStarted) {
        _logger.finest(
            'Enrollment Auth Scheduler is currently in-progress. Skipping this run');
        return;
      }
      await _enrollmentAuthenticationScheduler(enrollmentInfo);
    });
  }

  Future<void> _enrollmentAuthenticationScheduler(
      EnrollmentInfo enrollmentInfo) async {
    try {
      // If "_canProceedWithAuthentication" returns false,
      // stop the enrollment authentication scheduler.
      if (!(await _canProceedWithAuthentication(enrollmentInfo))) {
        return;
      }

      bool? isAuthenticated;
      try {
        isAuthenticated = await _performAPKAMAuthentication(enrollmentInfo);
      } on UnAuthenticatedException catch (e) {
        _handleUnAuthenticatedException(e, enrollmentInfo);
      }
      if (isAuthenticated == true) {
        await _handleAuthenticatedEnrollment(enrollmentInfo);
      }
    } finally {
      _enrollmentAuthSchedulerStarted = false;
    }
  }

  Future<bool> _canProceedWithAuthentication(
      EnrollmentInfo enrollmentInfo) async {
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
      await keyChainManager.deleteEnrollmentStore(_atSign);
      return false;
    }
    return true;
  }

  /// Performs PKAM Authentication to verify if the enrollment is approved.
  ///
  /// Returns true if enrollment is approved.
  ///
  /// Returns UnAuthenticatedException if the enrollment is in pending state or denied.
  Future<bool?> _performAPKAMAuthentication(
      EnrollmentInfo enrollmentInfo) async {
    atLookUp ??= AtLookupImpl(
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
    atLookUp?.atChops = AtChopsImpl(atChopsKeys);

    return await atLookUp?.pkamAuthenticate(
        enrollmentId: enrollmentInfo.enrollmentId);
  }

  /// If authentication is successful, then enrollment is approved.
  ///
  /// Fetch the keys pair from the key-chain and generate the atkeys file for subsequent authentication and
  /// remove the enrollment info from keychain.
  Future<void> _handleAuthenticatedEnrollment(
      EnrollmentInfo enrollmentInfo) async {
    _logger.info('Enrollment: ${enrollmentInfo.enrollmentId} is authenticated');

    // Get the decrypted (plain text) "Encryption Private Key" and "AES Symmetric Key"
    // from the secondary server.
    enrollmentInfo.atAuthKeys.defaultEncryptionPrivateKey =
        await _getDefaultEncryptionPrivateKey(
            enrollmentInfo.enrollmentId, atLookUp!.atChops!);
    enrollmentInfo.atAuthKeys.defaultSelfEncryptionKey =
        await _getDefaultSelfEncryptionKey(
            enrollmentInfo.enrollmentId, atLookUp!.atChops!);

    // updating enrollmentStore
    
    await keyChainManager.writeToEnrollmentStore(
      _atSign,
      jsonEncode(enrollmentInfo),
    );

    await _generateAtKeys(enrollmentInfo.atAuthKeys, atLookUp!.atChops!,
        enrollmentInfo.keysFilePath);
    _outcomes[enrollmentInfo.enrollmentId]?.complete(EnrollmentStatus.approved);
    atLookUp?.close();
  }

  /// When PKAM authentication is failed, return UnAuthenticatedException.
  ///
  /// When UnAuthenticatedException occurs:
  ///   - If the error message contains the error code "AT0025", it implies the enrollment
  /// is denied. So remove [EnrollmentInfo] from the keychain to stop retry process and complete the future in [_outcomes]
  /// with [EnrollmentStatus.denied].
  ///   - Else, the enrollment is in pending state. Set [_secondsUntilNextRun] to start the authentication retry mechanism.
  Future<void> _handleUnAuthenticatedException(
      UnAuthenticatedException e, EnrollmentInfo enrollmentInfo) async {
    // Error code AT0025 represents the enrollment request is denied and hence authentication failed.
    // If an enrollment id denied, then we do not have to retry the authentication and also allow
    // submitting a new enrollment request. So remove the request from key-chain.
    if (e.message.contains('AT0025')) {
      _logger.info(
          'Enrollment id: ${enrollmentInfo.enrollmentId} is denied. Stopping authentication retry.');
      await keyChainManager.deleteEnrollmentStore(_atSign);
      _outcomes[enrollmentInfo.enrollmentId]?.complete(EnrollmentStatus.denied);
      return;
    }
    _logger.info(
        'Enrollment: ${enrollmentInfo.enrollmentId} failed to authenticate. Retrying...');
    _secondsUntilNextRun = _secondsUntilNextRun * 2;
    _initEnrollmentAuthScheduler(enrollmentInfo);
  }

  /// On approving an enrollment request, generates atKeys file which is used to
  /// authenticate an atSign via APKAM.
  Future<void> _generateAtKeys(
      AtAuthKeys atAuthKeys, AtChops atChops, String? filePath) async {
    Map<String, String?> apkamBackupKeys = atAuthKeys.toJson();

    atChops.atChopsKeys.atEncryptionKeyPair = AtEncryptionKeyPair.create(
        atAuthKeys.defaultEncryptionPublicKey!,
        atAuthKeys.defaultEncryptionPrivateKey!);

    atChops.atChopsKeys.selfEncryptionKey =
        AESKey(atAuthKeys.defaultSelfEncryptionKey!);

    // Add atSign to the backup keys file.
    apkamBackupKeys[_atSign] = atChops.atChopsKeys.selfEncryptionKey!.key;

    try {
      apkamBackupKeys[defaultEncryptionPublicKey] = atChops
          .encryptString(
              atAuthKeys.defaultEncryptionPublicKey!, EncryptionKeyType.aes256,
              keyName: 'selfEncryptionKey', iv: AtChopsUtil.generateIVLegacy())
          .result;

      apkamBackupKeys[defaultEncryptionPrivateKey] = atChops
          .encryptString(
              atAuthKeys.defaultEncryptionPrivateKey!, EncryptionKeyType.aes256,
              keyName: 'selfEncryptionKey', iv: AtChopsUtil.generateIVLegacy())
          .result;

      apkamBackupKeys[apkamPublicKey] = atChops
          .encryptString(atAuthKeys.apkamPublicKey!, EncryptionKeyType.aes256,
              keyName: 'selfEncryptionKey', iv: AtChopsUtil.generateIVLegacy())
          .result;

      apkamBackupKeys[apkamPrivateKey] = atChops
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

    /// When enrollment request is approved, enrollment data is copied to keychain and enrollment data is deleted
    await _storeToKeyChainManager(_atSign, atAuthKeys);
    await keyChainManager.deleteEnrollmentStore(_atSign);
    _logger.info(
        'atKeys file for enrollment id - ${atAuthKeys.enrollmentId} is saved in');
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
          await atLookUp?.executeCommand('$privateKeyCommand\n', auth: true);
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
      String? encryptedSelfEncryptionKey = await atLookUp
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
}
