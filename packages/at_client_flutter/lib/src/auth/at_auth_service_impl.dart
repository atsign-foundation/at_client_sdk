import 'dart:async';
import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_client_flutter/src/at_onboarding_status.dart';
import 'package:at_client_flutter/src/services/onboarding_util.dart';
import 'package:at_client_flutter/src/utils/at_onboarding_app_constants.dart';
import 'package:at_server_status/at_server_status.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client_flutter/src/auth/at_auth_service.dart';
import 'package:at_client_flutter/src/keychain/keychain_io_impl.dart';
import 'package:at_client_flutter/src/keychain/keychain_manager.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_utils/at_logger.dart';
import 'package:flutter/cupertino.dart';
import 'package:at_client_flutter/src/enrollment/enrollment_info.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

final atAuthServiceProvider =
    Provider<AtAuthService>((ref) => AtAuthService.create());

class AtAuthServiceImpl implements AtAuthService {
  final AtSignLogger _logger = AtSignLogger('AtAuthServiceImpl');
  final AtOnboardingStatusStream _atOnboardingStatusStream = AtOnboardingStatusStream();
  
  @override
  AtOnboardingStatusStream get onboardingStatusStream => _atOnboardingStatusStream;
  AtServiceFactory? atServiceFactory;
  AtClient? _atClient;
  AtLookUp? _atLookUp;
  AtClientPreference? _atClientPreference;
  late String atSign;

  @override
  AtClientPreference? get atClientPreference => _atClientPreference;
  @override
  set atClientPreference(AtClientPreference? preference) {
    _atClientPreference = preference;
  }

  @override
  String? get currentAtSign => atSign;
  @override
  set currentAtSign(String? value) {
    atSign = value!;
  }

  @visibleForTesting
  KeychainAtKeysIo keychainAtKeysIo;
  late AtAuth _atAuth;

  @visibleForTesting
  late AtEnrollmentBase atEnrollmentBase;

  /// The maximum number of retries for verify approval/denial of an enrollment request
  final int _maxEnrollmentAuthenticationRetryInHours = 48;

  // Represents the delay to start next run.
  int _secondsUntilNextRun = 1;

  /// A boolean flag which represents the "enrollmentAuthScheduler" running status.
  bool _enrollmentAuthSchedulerStarted = false;

  final Map<String, Completer<EnrollmentStatus>> _outcomes = {};

  /// Returns an instance of [AtAuthService] used for authentication and onboarding of an atSign in Flutter.
  ///
  /// Usage:
  /// ```dart
  ///  AtAuthService authService = AtAuthServiceImpl(atSign!, _atClientPreference);
  /// ```
  ///
  /// Optional parameters:
  /// - atLookUp: An instance of [AtLookUp] used to perform lookups on the secondary server. If not provided, a default instance will be created.
  /// - atClient: An instance of [AtClient] used to interact with the secondary server. If not provided, a default instance will be created.
  /// - keyChainManager (VISIBLE FOR TESTING): Only used for testing purposes to inject a mock [KeyChainManager] instance.
  ///
  AtAuthServiceImpl(
      {AtLookUp? atLookUp,
      AtClient? atClient,
      AtClientPreference? atClientPreference,
      KeychainAtKeysIo? keychainAtKeysIo})
      : _atLookUp = atLookUp,
        _atClient = atClient,
        _atClientPreference = atClientPreference,
        keychainAtKeysIo = keychainAtKeysIo ?? KeychainAtKeysIo() {
    _atAuth = AtAuth.create(atLookUp: _atLookUp);
    atEnrollmentBase = AtEnrollmentBase.create();
  }

  @override
  Future<AtAuthResponse> authenticate(AtAuthRequest atAuthRequest) async {
    // If the user does not provide the keys data then fetch for the keys in the
    // keychain manager.
    // User provides keys data either by
    //  - 1. atAuthRequest.atKeysIo - The AtKeysIo instance which reads the keys from etc
    //  - 2. atAuthRequest.atAuthKeys - The AtAuthKeys instance which contains the keys
    //  - 3. atAuthRequest.encryptedKeysMap - Provide the contents of atKeys file which
    //    contains keys in encrypted format
    AtKeysIo? atKeysIo;
    atSign = atAuthRequest.atSign;
    _atClientPreference ??=
        await _loadAtClientPreference(atAuthRequest.rootDomain);
    if (atAuthRequest.atKeysIo != null) {
      atKeysIo = atAuthRequest.atKeysIo;
    } else {
      atKeysIo = keychainAtKeysIo;
    }
    atAuthRequest.atKeysIo = atKeysIo;
    // Invoke authenticate method in AtAuth package.
    AtAuthResponse atAuthResponse = AtAuthResponse(atSign);
    try {
      atAuthResponse = await _atAuth.authenticate(atAuthRequest);
    } on AtAuthenticationException {
      // AtAuthenticationException could be because of authentication failure or due to network failure.
      // If due to network failure, initialize atClient for offline access. To initialize atClient in offline,
      // check if the atSign is already onboarded. If already onboarded, initialize atClient for offline usage.
      if (await isOnboarded(atSign)) {
        // Initialize atClient for offline access.
        _logger.info(
            'Network connectivity not available. Initializing at_client for offline usage');
        await _init(_atAuth.atChops!, enrollmentId: atAuthRequest.enrollmentId);
        return atAuthResponse
          ..isSuccessful = true
          ..atAuthKeys = atAuthRequest.atAuthKeys
          ..enrollmentId = atAuthRequest.enrollmentId;
      }
    }
    // If authentication is failed, return the atAuthResponse. Do nothing.
    if (atAuthResponse.isSuccessful == false) {
      return atAuthResponse;
    }
    // If authentication is successful, initialize AtClient instance.
    await _init(
      _atAuth.atChops!,
      enrollmentId: atAuthResponse.enrollmentId,
    );
    // When an atSign is authenticated via the .atKeys on a new device, the keys
    // will not be present in keychain manager. Add keys to key-chain manager.
    AtKeys atSignKey;
    try {
      atSignKey = await keychainAtKeysIo.read(atSign);
    } catch (_) {
      await keychainAtKeysIo.write(atSign, atAuthResponse.atAuthKeys!);
      atSignKey = await keychainAtKeysIo.read(atSign);
      await _persistKeysLocalSecondary(atSign, atAuthResponse.atAuthKeys!);
    }
    atAuthResponse.atAuthKeys = atSignKey;

    return atAuthResponse;
  }

  @override

  /// Onboards an atSign by performing CRAM authentication.
  ///
  /// The [cramSecret] is mandatory to perform CRAM authentication.
  /// If the [cramSecret] is not provided, then an [AtException] is thrown.
  ///
  /// The [atOnboardingRequest] contains the details of the atSign to be onboarded.
  /// The [atOnboardingRequest] must contain the following details:
  /// - atSign: The atSign to be onboarded.
  /// - AtKeysIo: The AtKeysIo instance which reads/writes the keys from/to the storage.
  ///
  /// returns [AtOnboardingResponse] which contains the details of the onboarding process.
  Future<AtOnboardingResponse> onboard(AtOnboardingRequest atOnboardingRequest,
      {String? cramSecret, String? registrarUrl}) async {
    atSign = atOnboardingRequest.atSign;
    _atClientPreference ??=
        await _loadAtClientPreference(atOnboardingRequest.rootDomain);

    //If the user is providing atKeysIo, they might be onboarding via key file (qr code etc)
    atOnboardingRequest.atKeysIo ??= keychainAtKeysIo;
    try{
      atOnboardingRequest.atKeys = await atOnboardingRequest.atKeysIo?.read(atSign); //otherwise, we'll check the keychain, maybe it exists already
    }catch(e,s){
      _logger.info('Failed to read keys for atSign: $atSign | Cause: $e', s); //swallow the error, we just want to know if keys exist or not
    }

     //if no cram key is provided, then try and enroll via otp
    if (cramSecret == null) {
      final util = OnboardingUtil();
      await util.requestAuthenticationOtp(
        atOnboardingRequest.atSign,
      );

      String otp = util.getVerificationCodeFromUser();

      cramSecret = await util.getCramKey(
        atOnboardingRequest.atSign,
        otp,
      );
    }

    await _validateAtServerForOnboarding(atOnboardingRequest);
    AtOnboardingResponse atOnboardingResponse =
        await _atAuth.onboard(atOnboardingRequest, cramSecret);
    // If onboarding is not successful, return the onboarding response
    // with the isSuccessful set to false.
    if (!atOnboardingResponse.isSuccessful) {
      return atOnboardingResponse;
    }
    if (_atAuth.atChops == null) {
      throw AtAuthenticationException(
          'Failed to onboard atSign: $atSign. AtChops is not initialized in AtAuth Package');
    }
    await _init(
      _atAuth.atChops!,
      enrollmentId: atOnboardingResponse.enrollmentId,
    );
    await keychainAtKeysIo.write(
        atOnboardingResponse.atSign, atOnboardingResponse.atAuthKeys!);
    await _persistKeysLocalSecondary(atSign, atOnboardingResponse.atAuthKeys!);
    return atOnboardingResponse;
  }

  @override
  Future<bool> isOnboarded(String atSign) async {
    AtKeys? atKeys;
    try {
      atKeys = await keychainAtKeysIo.read(atSign);
    } catch (_) {
      return false;
    }
    if (atKeys.defaultEncryptionPublicKey == null) {
      return false;
    }
    return true;
  }

  @override
  Future<List<String>> getAllAtsigns() async {
    return await keychainAtKeysIo.getAtsignsFromKeychain();
  }

  @override
  Future<ServerStatus?> checkAtSignServerStatus(String atsign) async {
    AtStatus status = await AtStatusImpl().get(atsign);
    return status.serverStatus;
  }

  @override
  Future<bool> isExistingAtsign(String? atsign) async {
    if (atsign == null) {
      return false;
    }
    List<String> atSignsList = await getAllAtsigns();
    ServerStatus? status = await checkAtSignServerStatus(atsign).timeout(
        Duration(seconds: AtOnboardingConstants.responseTimeLimit),
        onTimeout: () => throw AtOnboardingStatus.timeOut);
    bool isExist =
        atSignsList.isNotEmpty ? atSignsList.contains(atsign) : false;
    if (status == ServerStatus.teapot) {
      isExist = false;
    }
    return isExist;
  }

  /// Stores the atKeys to Key-Chain Manager.
  Future<void> _persistKeysLocalSecondary(
      String atSign, AtKeys? atAuthKeys) async {
    if (atAuthKeys == null) {
      throw AtException(
          'Failed to store keys in Keychain manager for atSign: $atSign. AtAuthKeys instance is null');
    }

    await _atClient!.getLocalSecondary()!.putValue(
        AtConstants.atPkamPublicKey, atAuthKeys.apkamPublicKey!.toString());

    // pkam private will not be available in case of secure element
    if (atAuthKeys.apkamPrivateKey != null) {
      await _atClient!.getLocalSecondary()!.putValue(
          AtConstants.atPkamPrivateKey, atAuthKeys.apkamPrivateKey!.toString());
    }

    await _atClient!.getLocalSecondary()!.putValue(
        AtConstants.atEncryptionPrivateKey,
        atAuthKeys.defaultEncryptionPrivateKey!.toString());

    var updateBuilder = UpdateVerbBuilder()
      ..atKey = AtKey.public('publickey', sharedBy: atSign).build();
    updateBuilder.atKey.metadata.ttr = -1;
    updateBuilder.value = atAuthKeys.defaultEncryptionPublicKey;

    await _atClient!
        .getLocalSecondary()!
        .executeVerb(updateBuilder, sync: true);

    await _atClient!
        .getLocalSecondary()!
        .executeVerb(updateBuilder, sync: true);

    await _atClient!.getLocalSecondary()!.putValue(
        AtConstants.atEncryptionSelfKey,
        atAuthKeys.defaultSelfEncryptionKey!.toString());
  }

  Future<void> _init(AtChops atChops, {String? enrollmentId}) async {
    await _initAtClient(atChops, enrollmentId: enrollmentId);
    _atLookUp!.atChops = atChops;
    _atClient!.atChops = atChops;
  }

  Future<void> _initAtClient(AtChops atChops, {String? enrollmentId}) async {
    AtClientManager atClientManager = AtClientManager.getInstance();
    await atClientManager.setCurrentAtSign(
        atSign, _atClientPreference!.namespace, _atClientPreference!,
        atChops: atChops,
        serviceFactory: atServiceFactory,
        enrollmentId: enrollmentId);
    // ??= to support mocking
    _atLookUp ??= atClientManager.atClient.getRemoteSecondary()?.atLookUp;
    _atLookUp?.enrollmentId = enrollmentId;
    _atLookUp?.signingAlgoType = _atClientPreference!.signingAlgoType;
    _atLookUp?.hashingAlgoType = _atClientPreference!.hashingAlgoType;
    _atClient ??= atClientManager.atClient;
  }

  @override
  Future<AtEnrollmentResponse> enroll(
      EnrollmentRequest enrollmentRequest) async {
    // Only one enrollment request can be submitted at a time.
    // Subsequent requests cannot be submitted until the pending one is fulfilled.
    String? enrollmentInfoJsonString = await keychainAtKeysIo
        .readEnrollmentFromKeychain(enrollmentRequest.atSign);
    atSign = enrollmentRequest.atSign;
    _atClientPreference ??=
        await _loadAtClientPreference(enrollmentRequest.rootDomain);
    // if enrollmentInfoJsonString is not null, it indicates that there is a pending
    // enrollment request. So, do not allow another enrollment request.
    if (enrollmentInfoJsonString != null) {
      throw AtEnrollmentException(
          'Cannot submit new enrollment request until the pending enrollment request is fulfilled');
    }
    _atLookUp ??= AtLookupImpl(
        atSign, _atClientPreference!.rootDomain, _atClientPreference!.rootPort);
    AtEnrollmentResponse atEnrollmentResponse =
        await atEnrollmentBase.submit(enrollmentRequest, _atLookUp!);
    await _atLookUp?.close();
    EnrollmentInfo enrollmentInfo = EnrollmentInfo(
      atEnrollmentResponse.enrollmentId,
      atEnrollmentResponse.atAuthKeys!,
      DateTime.now().toUtc().millisecondsSinceEpoch,
      enrollmentRequest.namespaces,
    );
    // Store the enrollment keys into keychain to store the auth keys into keychain, if an enrollment is approved.
    await keychainAtKeysIo.writeEnrollmentToKeychain(
        atSign, jsonEncode(enrollmentInfo));
    return atEnrollmentResponse;
  }

  @override
  Future<EnrollmentStatus> getFinalEnrollmentStatus(String atSign) async {
    String? enrollmentInfoJsonString =
        await keychainAtKeysIo.readEnrollmentFromKeychain(atSign);
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
  Future<EnrollmentInfo?> getSentEnrollmentRequest(String atSign) async {
    String? enrollmentInfoJsonString =
        await keychainAtKeysIo.readEnrollmentFromKeychain(atSign);
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
    _enrollmentAuthSchedulerStarted = true;
    _logger.finest(
        'Polling for authentication for the enrollment id: ${enrollmentInfo.enrollmentId}');
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
      await keychainAtKeysIo.deleteEnrollmentStore(atSign);
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
    _atLookUp ??= AtLookupImpl(
        atSign, _atClientPreference!.rootDomain, _atClientPreference!.rootPort);
    // Create the AtChops instance with the new APKAM keys to verify if enrollment
    // is approved.
    // If enrollment is approved, then apkam authentication will be successful.
    AtChopsKeys atChopsKeys = AtChopsKeys.create(
        null,
        AtPkamKeyPair.create(
            enrollmentInfo.atAuthKeys.apkamPublicKey!.toString(),
            enrollmentInfo.atAuthKeys.apkamPrivateKey!.toString()));
    atChopsKeys.apkamSymmetricKey =
        AESKey(enrollmentInfo.atAuthKeys.apkamSymmetricKey!.toString());
    _atLookUp?.atChops = AtChopsImpl(atChopsKeys);

    return await _atLookUp?.pkamAuthenticate(
        enrollmentId: enrollmentInfo.enrollmentId);
  }

  /// If authentication is successful, then enrollment is approved.
  ///
  /// Fetch the keys pair from the key-chain and generate the atkeys file for subsequent authentication and
  /// remove the enrollment info from keychain.
  Future<void> _handleAuthenticatedEnrollment(
      EnrollmentInfo enrollmentInfo) async {
    // Get the decrypted (plain text) "Encryption Private Key" and "AES Symmetric Key"
    // from the secondary server.
    enrollmentInfo.atAuthKeys.defaultEncryptionPrivateKey =
        await _getDefaultEncryptionPrivateKey(
            atSign, enrollmentInfo.enrollmentId, _atLookUp!.atChops!);
    enrollmentInfo.atAuthKeys.defaultSelfEncryptionKey =
        await _getDefaultSelfEncryptionKey(
            atSign, enrollmentInfo.enrollmentId, _atLookUp!.atChops!);
    // Store the auth keys into keychain manager for subsequent authentications
    await keychainAtKeysIo.write(atSign, enrollmentInfo.atAuthKeys);
    AtChops atChops = _buildAtChops(enrollmentInfo);
    await _initAtClient(atChops, enrollmentId: enrollmentInfo.enrollmentId);
    // Store enrolled namespace to local secondary to perform authorization checks
    // when perform CURD operation on keystore.
    await _storeEnrollmentInfoIntoLocalSecondary(enrollmentInfo);
    await keychainAtKeysIo.deleteEnrollmentStore(atSign);
    _logger.info(
        'Enrollment Id: ${enrollmentInfo.atAuthKeys.enrollmentId} is approved and authentication keys are stored in the keychain');
    _outcomes[enrollmentInfo.enrollmentId]?.complete(EnrollmentStatus.approved);
    _atLookUp?.close();
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
      await keychainAtKeysIo.deleteEnrollmentStore(atSign);
      _outcomes[enrollmentInfo.enrollmentId]?.complete(EnrollmentStatus.denied);
      return;
    }
    _logger.info(
        'Enrollment: ${enrollmentInfo.enrollmentId} failed to authenticate. Retrying...');
    _secondsUntilNextRun = _secondsUntilNextRun * 2;
    _initEnrollmentAuthScheduler(enrollmentInfo);
  }

  /// Retrieves the encrypted "encryption private key" from the server and decrypts.
  /// This process involves using the APKAM symmetric key for decryption.
  /// Returns the original "encryption private key" after decryption.
  Future<AtBytes> _getDefaultEncryptionPrivateKey(
      String atSign, String enrollmentIdFromServer, AtChops atChops) async {
    var privateKeyCommand =
        'keys:get:keyName:$enrollmentIdFromServer.${AtConstants.defaultEncryptionPrivateKey}.__manage$atSign\n';
    String encryptionPrivateKeyFromServer;
    String? encryptionPrivateKeyIV;
    try {
      var getPrivateKeyResult =
          await _atLookUp?.executeCommand('$privateKeyCommand\n', auth: true);
      if (getPrivateKeyResult == null || getPrivateKeyResult.isEmpty) {
        throw AtEnrollmentException('$privateKeyCommand returned null/empty');
      }
      getPrivateKeyResult =
          getPrivateKeyResult.replaceFirst(RegExp('^data:'), '');
      var privateKeyResultJson = jsonDecode(getPrivateKeyResult);
      encryptionPrivateKeyFromServer = privateKeyResultJson['value'];
      encryptionPrivateKeyIV = privateKeyResultJson['iv'];
    } on Exception catch (e) {
      throw AtEnrollmentException(
          'Exception while getting encrypted private key/self key from server: $e');
    }
    AtEncryptionResult? atEncryptionResult = await atChops.decryptString(
        encryptionPrivateKeyFromServer, EncryptionKeyType.aes256,
        keyName: 'apkamSymmetricKey',
        iv: encryptionPrivateKeyIV != null
            ? InitialisationVector(base64Decode(encryptionPrivateKeyIV))
            : AtChopsUtil.generateIVLegacy());
    return AtBytes.fromString(atEncryptionResult.result);
  }

  /// Returns the decrypted selfEncryptionKey.
  /// Fetches the encrypted selfEncryptionKey from the server and decrypts the
  /// key with APKAM Symmetric key to get the original selfEncryptionKey.
  Future<AtBytes> _getDefaultSelfEncryptionKey(
      String atSign, String enrollmentIdFromServer, AtChops atChops) async {
    var selfEncryptionKeyCommand =
        'keys:get:keyName:$enrollmentIdFromServer.${AtConstants.defaultSelfEncryptionKey}.__manage$atSign\n';
    String selfEncryptionKeyFromServer;
    String? selfEncryptionKeyIV;
    try {
      String? encryptedSelfEncryptionKey = await _atLookUp
          ?.executeCommand('$selfEncryptionKeyCommand\n', auth: true);
      if (encryptedSelfEncryptionKey == null ||
          encryptedSelfEncryptionKey.isEmpty) {
        throw AtEnrollmentException(
            '$selfEncryptionKeyCommand returned null/empty');
      }
      encryptedSelfEncryptionKey =
          encryptedSelfEncryptionKey.replaceFirst(RegExp('^data:'), '');
      var selfEncryptionKeyResultJson = jsonDecode(encryptedSelfEncryptionKey);
      selfEncryptionKeyFromServer = selfEncryptionKeyResultJson['value'];
      selfEncryptionKeyIV = selfEncryptionKeyResultJson['iv'];
    } on Exception catch (e) {
      throw AtEnrollmentException(
          'Exception while getting encrypted private key/self key from server: $e');
    }
    AtEncryptionResult? atEncryptionResult = await atChops.decryptString(
        selfEncryptionKeyFromServer, EncryptionKeyType.aes256,
        keyName: 'apkamSymmetricKey',
        iv: selfEncryptionKeyIV != null
            ? InitialisationVector(base64Decode(selfEncryptionKeyIV))
            : AtChopsUtil.generateIVLegacy());
    return AtBytes.fromString(atEncryptionResult.result);
  }

  /// Stores the enrolled namespace in the local secondary to perform authorization checks
  /// when performing CURD operation on local secondary server
  Future<void> _storeEnrollmentInfoIntoLocalSecondary(
      EnrollmentInfo enrollmentInfo) async {
    var localEnrollmentKey = AtKey()
      ..isLocal = true
      ..key = enrollmentInfo.enrollmentId
      ..sharedBy = atSign;
    Enrollment enrollment = Enrollment()..namespace = enrollmentInfo.namespace;
    AtData atData = AtData()..data = jsonEncode(enrollment);
    // The "put" function in AtClient will call the executeVerb function which in turn calls the "_isAuthorized" in the local secondary.
    // The "_isAuthorized" method fetches enrollment info from the key-store. Since there is no enrollment info, it returns null which
    // throws AtKeyNotFoundException.
    // So, directly add the enrollment key to the keystore.

    // During submission of enrollment, the enrollment details are stored in the server. Upon approval of an enrollment,
    // store a copy of enrollment into local secondary for the performing the authorization.
    // So setting skipCommit to true to prevent key being sync to remote secondary.
    await _atClient!
        .getLocalSecondary()
        ?.keyStore
        ?.put(localEnrollmentKey.toString(), atData);
  }

  AtChops _buildAtChops(EnrollmentInfo enrollmentInfo) {
    AtEncryptionKeyPair atEncryptionKeyPair = AtEncryptionKeyPair.create(
        enrollmentInfo.atAuthKeys.defaultEncryptionPublicKey!.toString(),
        enrollmentInfo.atAuthKeys.defaultEncryptionPrivateKey!.toString());

    AtPkamKeyPair atPkamKeyPair = AtPkamKeyPair.create(
        enrollmentInfo.atAuthKeys.apkamPublicKey!.toString(),
        enrollmentInfo.atAuthKeys.apkamPrivateKey!.toString());

    AtChopsKeys atChopsKeys =
        AtChopsKeys.create(atEncryptionKeyPair, atPkamKeyPair);
    atChopsKeys.selfEncryptionKey =
        AESKey(enrollmentInfo.atAuthKeys.defaultSelfEncryptionKey!.toString());
    atChopsKeys.apkamSymmetricKey =
        AESKey(enrollmentInfo.atAuthKeys.apkamSymmetricKey!.toString());

    AtChops atChops = AtChopsImpl(atChopsKeys);
    return atChops;
  }

  AtChops createAtChops(AtKeys atKeys) {
    AtChopsKeys atChopsKeys = AtChopsKeys.create(
        AtEncryptionKeyPair.create(
            atKeys.defaultEncryptionPublicKey!.toString(),
            atKeys.defaultEncryptionPrivateKey!.toString()),
        AtPkamKeyPair.create(atKeys.apkamPublicKey!.toString(),
            atKeys.apkamPrivateKey!.toString()));
    atChopsKeys.selfEncryptionKey =
        AESKey(atKeys.defaultSelfEncryptionKey!.toString());
    atChopsKeys.apkamSymmetricKey =
        AESKey(atKeys.apkamSymmetricKey!.toString());
    AtChops atChops = AtChopsImpl(atChopsKeys);
    return atChops;
  }

  Future<void> _validateAtServerForOnboarding(
      AtOnboardingRequest atOnboardingRequest) async {
    AtServerStatus status = AtStatusImpl(
        rootUrl: atOnboardingRequest.rootDomain.rootDomain,
        rootPort: atOnboardingRequest.rootDomain.rootPort);
    int retryCount = 1;
    const int maxRetries = 3;
    const Duration retryDelay = Duration(seconds: 2);

    while (retryCount < maxRetries) {
      try {
        var atStatus = await status.get(atOnboardingRequest.atSign);
        if (atStatus.rootStatus != RootStatus.found) {
          throw AtException(
              'Could not find root server: ${atOnboardingRequest.rootDomain.rootDomain}');
        }
        if (atStatus.serverStatus != ServerStatus.activated &&
            atStatus.serverStatus != ServerStatus.ready) {
          throw AtException(
              'Secondary server is not activated for atSign: ${atOnboardingRequest.atSign}');
        }
        if (atStatus.atSignStatus == AtSignStatus.activated) {
          throw AtException(
              'atSign: ${atOnboardingRequest.atSign} is already onboarded. Cannot perform onboarding again.');
        }
        break; // Exit loop if no exception occurs
      } catch (e) {
        _logger.severe('Error during onboarding atServer validation: $e');
        retryCount++;
        if (retryCount >= maxRetries) {
          onboardingStatusStream.add(AtOnboardingStatusError("Unable to validate atServer and atSign for onboarding, error: ${e.toString()}", AtOnboardingStatus.authFailed));
        }
        _logger.warning(
            'Attempt $retryCount failed: $e. Retrying... $retryCount/$maxRetries');
        await Future.delayed(retryDelay); // Wait before retrying
      }
    }
  }
}

Future<AtClientPreference> _loadAtClientPreference(
    AtRootDomain? rootDomain) async {
  var dir = await getApplicationSupportDirectory();
  rootDomain ??= AtRootDomain('root.atsign.org', 64);
  return AtClientPreference()
    ..namespace = 'root'
    ..rootDomain = rootDomain.rootDomain
    ..rootPort = rootDomain.rootPort
    ..hiveStoragePath = dir.path
    ..commitLogPath = dir.path
    ..isLocalStoreRequired = true;
}
