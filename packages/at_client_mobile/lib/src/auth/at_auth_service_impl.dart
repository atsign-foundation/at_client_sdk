import 'dart:convert';

import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_client_mobile/src/atsign_key.dart';
import 'package:at_client_mobile/src/auth/at_keys_file.dart';
import 'package:at_client_mobile/src/auth/at_security_keys.dart';
import 'package:at_client_mobile/src/auth/cram_authenticator.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_chops/at_chops.dart';

import 'package:at_client_mobile/src/auth/at_authenticator.dart';
import 'package:at_client_mobile/src/auth/pkam_authenticator.dart';

import 'at_auth_service.dart';
import 'package:at_utils/at_logger.dart';

import 'enroll/at_enrollment_service.dart';

class AtAuthServiceImpl implements AtAuthService {
  final AtSignLogger _logger = AtSignLogger('AtAuthServiceImpl');
  PkamAuthenticator? pkamAuthenticator;
  CramAuthenticator? cramAuthenticator;
  AtClient? _atClient;
  AtLookUp? _atLookUp;
  final KeyChainManager _keyChainManager = KeyChainManager.getInstance();
  @override
  AtChops? atChops;
  AtServiceFactory? atServiceFactory;
  String _atSign;
  AtClientPreference _atClientPreference;
  KeyChainManager keyChainManager = KeyChainManager.getInstance();
  AtClientManager atClientManager = AtClientManager.getInstance();
  AtEnrollmentService? atEnrollmentService;

  AtAuthServiceImpl(this._atSign, this._atClientPreference);

  @override
  Future<AtAuthResponse> authenticate(AtAuthRequest atAuthRequest) async {
    var atAuthResponse = AtAuthResponse(atAuthRequest.atSign);
    var decryptKey = atAuthRequest.atKeysData!.decryptionKey;

    AtSecurityKeys atSecurityKeys;
    // 1. check if atsign is already onboarded
    if (await isOnboarded(atSign: atAuthRequest.atSign)) {
      // read keys from keychain/local secondary
      atSecurityKeys = await _readKeys(atAuthRequest.authMode);
      var enrollmentId = atAuthRequest.enrollmentId;
      if (enrollmentId == null || enrollmentId.isEmpty) {
        enrollmentId = atSecurityKeys.enrollmentId;
      }
      await _init(atSecurityKeys, enrollmentId: enrollmentId);
      return _pkamAuth(atAuthRequest.atSign);
    } else {
      // read keys file data
      atSecurityKeys =
          _decodeAndDecryptKeys(atAuthRequest.atKeysData!.jsonData, decryptKey);
      if (atSecurityKeys.apkamPrivateKey == null ||
          atSecurityKeys.apkamPrivateKey!.isEmpty) {
        throw AtPrivateKeyNotFoundException(
            'Unable to read PkamPrivateKey from provided atKeys file. Please provide a valid atKeys file',
            exceptionScenario: ExceptionScenario.invalidValueProvided);
      }
    }

    // 2. Create atChops instance if not injected
    atChops ??= _createAtChops(atSecurityKeys);
    // 3. init at client
    await _initAtClient(atChops!);

    // 4. pkam auth using the created atClient instance
    try {
      atAuthResponse.isSuccessful = await atClientManager.atClient
          .getRemoteSecondary()!
          .atLookUp
          .pkamAuthenticate(enrollmentId: atSecurityKeys.enrollmentId);
    } on UnAuthenticatedException {
      atAuthResponse.isSuccessful = false;
    }

    if (!atAuthResponse.isSuccessful) {
      _logger.severe('Authentication failed. ${atAuthRequest.atSign}.');
      atAuthResponse.isSuccessful = false;
      return atAuthResponse;
    }
    // 5. if auth is successful,persist keys to keychain and local secondary
    await _storeToKeyChainManager(atAuthRequest.atSign, atSecurityKeys);
    await _persistKeysLocalSecondary(atSecurityKeys);
    return atAuthResponse;
  }

  @override
  Future<bool> isOnboarded({String? atSign}) {
    return _atClient!.isOnboarded();
  }

  @override
  Future<AtOnboardingResponse> onboard(AtOnboardingRequest atOnboardingRequest,
      {String? cramSecret}) async {
    var atSign = atOnboardingRequest.atSign;
    var atOnboardingResponse = AtOnboardingResponse(atSign);
    cramSecret ??= atOnboardingRequest.preference.cramSecret!;
    try {
      _atLookUp ??= AtLookupImpl(
          atSign,
          atOnboardingRequest.preference.rootDomain,
          atOnboardingRequest.preference.rootPort);
      cramAuthenticator ??=
          CramAuthenticator(cramSecret, atOnboardingRequest.preference)
            ..atLookup = _atLookUp;
      final cramAuthResult =
          await cramAuthenticator!.authenticate(atOnboardingRequest.atSign);
      _logger.finer('cram auth result for $atSign : $cramAuthResult');
      if (cramAuthResult.isSuccessful) {
        await _activateNewAtSign(atOnboardingRequest, atOnboardingResponse);
      } else {
        atOnboardingResponse.isSuccessful = false;
        throw AtClientException(
            error_codes['UnAuthenticatedException'], 'cram auth failed');
      }
      return atOnboardingResponse;
    } on AtClientException catch (e) {
      _logger
          .severe('exception in onboard -_activateNewAtSign : ${e.toString()}');
      rethrow;
    }
  }

  Future<AtSecurityKeys> _readKeys(PkamAuthMode authMode) async {
    var atSecurityKeys = AtSecurityKeys();
    if (authMode != PkamAuthMode.sim) {
      var pkamPrivateKey = await keyChainManager.getPkamPrivateKey(_atSign);
      if (pkamPrivateKey == null || pkamPrivateKey.isEmpty) {
        pkamPrivateKey = await _atClient!.getLocalSecondary()!.getPrivateKey();
      }
      if (pkamPrivateKey == null || pkamPrivateKey.isEmpty) {
        throw AtPrivateKeyNotFoundException(
            'Pkam private key not found in keychain/local secondary');
      }
      atSecurityKeys.apkamPrivateKey = pkamPrivateKey;
    }
    var pkamPublicKey = await keyChainManager.getPkamPublicKey(_atSign);
    if (pkamPublicKey == null || pkamPublicKey.isEmpty) {
      pkamPublicKey = await _atClient!.getLocalSecondary()!.getPrivateKey();
    }
    if (pkamPublicKey == null || pkamPublicKey.isEmpty) {
      throw AtPublicKeyNotFoundException(
          'Pkam public key not found in keychain/local secondary');
    }
    atSecurityKeys.apkamPublicKey = pkamPublicKey;

    var encryptionPublicKey =
        await keyChainManager.getEncryptionPublicKey(_atSign);
    if (encryptionPublicKey == null || encryptionPublicKey.isEmpty) {
      encryptionPublicKey =
          await _atClient!.getLocalSecondary()!.getEncryptionPublicKey(_atSign);
    }
    if (encryptionPublicKey == null || encryptionPublicKey.isEmpty) {
      throw AtPublicKeyNotFoundException(
          'Encryption public key not found in keychain/local secondary');
    }
    atSecurityKeys.defaultEncryptionPublicKey = encryptionPublicKey;

    var encryptionPrivateKey =
        await keyChainManager.getEncryptionPrivateKey(_atSign);
    if (encryptionPrivateKey == null || encryptionPrivateKey.isEmpty) {
      encryptionPrivateKey =
          await _atClient!.getLocalSecondary()!.getEncryptionPrivateKey();
    }
    if (encryptionPrivateKey == null || encryptionPrivateKey.isEmpty) {
      throw AtPrivateKeyNotFoundException(
          'Encryption private key not found in keychain/local secondary');
    }
    atSecurityKeys.defaultEncryptionPrivateKey = encryptionPrivateKey;

    var selfEncryptionKey =
        await keyChainManager.getSelfEncryptionAESKey(_atSign);
    if (selfEncryptionKey == null || selfEncryptionKey.isEmpty) {
      selfEncryptionKey =
          await _atClient!.getLocalSecondary()!.getEncryptionSelfKey();
    }
    if (selfEncryptionKey == null || selfEncryptionKey.isEmpty) {
      throw AtKeyNotFoundException(
          'Self encryption key not found in keychain/local secondary');
    }

    atSecurityKeys.defaultSelfEncryptionKey = selfEncryptionKey;
    return atSecurityKeys;
  }

  Future<AtAuthResponse> _pkamAuth(String atSign) async {
    final atAuthResponse = AtAuthResponse(atSign);
    try {
      final pkamAuthResult = await pkamAuthenticator!.authenticate(atSign);
      atAuthResponse.isSuccessful = pkamAuthResult.isSuccessful;
    } on AtClientException catch (e) {
      _logger.severe('pkam auth failed for atSign: $e');
      atAuthResponse.isSuccessful = false;
    }
    return atAuthResponse;
  }

  Future<void> _activateNewAtSign(AtOnboardingRequest onboardingRequest,
      AtOnboardingResponse atOnboardingResponse) async {
    try {
      // 1. generate pkam keypair/read public key from secure element using atChops
      var atSecurityKeys = AtSecurityKeys();
      if (onboardingRequest.authMode == PkamAuthMode.sim) {
        if (atChops == null) {
          throw AtClientException(error_codes['AtClientException'],
              'atChops instance not set when auth mode is sim');
        }
        if (onboardingRequest.publicKeyId == null) {
          throw AtClientException(error_codes['AtClientException'],
              'publicKeyId from secure element has to be set when auth mode is sim');
        }
        atSecurityKeys.apkamPublicKey =
            atChops!.readPublicKey(onboardingRequest.publicKeyId!);
      } else {
        var pkamKeypair = _keyChainManager.generateKeyPair();
        atSecurityKeys.apkamPublicKey = pkamKeypair.publicKey.toString();
        atSecurityKeys.apkamPrivateKey = pkamKeypair.privateKey.toString();
      }
      //1.1 generate encryption key pair, self encryption key and AES key
      var encryptionKeyPair = _keyChainManager.generateKeyPair();
      atSecurityKeys.defaultEncryptionPublicKey =
          encryptionKeyPair.publicKey.toString();
      atSecurityKeys.defaultEncryptionPrivateKey =
          encryptionKeyPair.privateKey.toString();
      atSecurityKeys.defaultSelfEncryptionKey = EncryptionUtil.generateAESKey();
      atSecurityKeys.apkamSymmetricKey = EncryptionUtil.generateAESKey();
      //2.Send enroll request
      var enrollBuilder = EnrollVerbBuilder()
        ..appName = onboardingRequest.preference.appName
        ..deviceName = onboardingRequest.preference.deviceName;

      enrollBuilder.encryptedDefaultEncryptedPrivateKey =
          EncryptionUtil.encryptValue(
              atSecurityKeys.defaultEncryptionPrivateKey!,
              atSecurityKeys.apkamSymmetricKey!);
      enrollBuilder.encryptedDefaultSelfEncryptionKey =
          EncryptionUtil.encryptValue(atSecurityKeys.defaultSelfEncryptionKey!,
              atSecurityKeys.apkamSymmetricKey!);
      enrollBuilder.apkamPublicKey = atSecurityKeys.apkamPublicKey;
      var enrollResult = await _atLookUp!
          .executeCommand(enrollBuilder.buildCommand(), auth: false);
      //#TODO change the error codes
      if (enrollResult == null || enrollResult.isEmpty) {
        throw AtClientException(
            'AT0401', 'Enrollment response is null or empty');
      } else if (enrollResult.startsWith('error:')) {
        throw AtClientException('AT0401', 'Enrollment error:$enrollResult');
      }
      enrollResult = enrollResult.replaceFirst('data:', '');
      _logger.finer('enrollResult: $enrollResult');
      var enrollResultJson = jsonDecode(enrollResult);
      var enrollmentIdFromServer = enrollResultJson[enrollmentId];
      var enrollmentStatus = enrollResultJson['status'];
      if (enrollmentStatus != 'approved') {
        throw AtClientException('AT0401',
            'initial enrollment is not approved. Status from server: $enrollmentStatus');
      }
      atSecurityKeys.enrollmentId = enrollmentIdFromServer;
      //3. Close connection to server
      try {
        await (_atLookUp! as AtLookupImpl).close();
      } on Exception catch (e) {
        _logger.severe('error while closing connection to server: $e');
      }
      //4. try pkam auth to server
      var isPkamAuthenticated;
      try {
        atChops ??= _createAtChops(atSecurityKeys);
        _atLookUp!.atChops = atChops;
        isPkamAuthenticated = await _atLookUp!
            .pkamAuthenticate(enrollmentId: enrollmentIdFromServer);
      } on UnAuthenticatedException {
        throw AtClientException('AT0401',
            'Pkam auth with enrollmentId-$enrollmentIdFromServer failed');
      }
      //5.1 init atClient and atChops.
      //5.2 Store keys to keychain manager
      //5.3 Delete cram secret
      if (isPkamAuthenticated) {
        await _init(atSecurityKeys, enrollmentId: enrollmentIdFromServer);
        var atSignItem = await _keyChainManager.readAtsign(name: _atSign) ??
            AtsignKey(atSign: _atSign);
        atSignItem = atSignItem.copyWith(
            encryptionPrivateKey: atSecurityKeys.defaultEncryptionPrivateKey,
            encryptionPublicKey: atSecurityKeys.defaultEncryptionPublicKey,
            selfEncryptionKey: atSecurityKeys.defaultSelfEncryptionKey,
            apkamSymmetricKey: atSecurityKeys.apkamSymmetricKey);
        await _keyChainManager.storeAtSign(atSign: atSignItem);
        var deleteBuilder = DeleteVerbBuilder()..atKey = AT_CRAM_SECRET;
        var deleteResponse = await _atLookUp!.executeVerb(deleteBuilder);
        _logger.finer('cram secret delete response : $deleteResponse');
        await _persistKeysLocalSecondary(atSecurityKeys);
        atOnboardingResponse.isSuccessful = true;
        atOnboardingResponse.atKeysData = AtKeysFileData(
            jsonEncode(atSecurityKeys.toMap()),
            atSecurityKeys.defaultSelfEncryptionKey!);
        atOnboardingResponse.enrollmentId = enrollmentIdFromServer;
      }
    } on AtClientException {
      rethrow;
    }
  }

  /// Stores the atKeys to Key-Chain Manager.
  Future<void> _storeToKeyChainManager(
      String atsign, AtSecurityKeys atSecurityKeys) async {
    await keyChainManager.storePkamKeysToKeychain(atsign,
        privateKey: atSecurityKeys.apkamPrivateKey,
        publicKey: atSecurityKeys.apkamPublicKey);

    var atSignItem = await keyChainManager.readAtsign(name: atsign) ??
        AtsignKey(atSign: atsign);
    atSignItem = atSignItem.copyWith(
        encryptionPrivateKey: atSecurityKeys.defaultEncryptionPrivateKey,
        encryptionPublicKey: atSecurityKeys.defaultEncryptionPublicKey,
        selfEncryptionKey: atSecurityKeys.defaultSelfEncryptionKey,
        apkamSymmetricKey: atSecurityKeys.apkamSymmetricKey,
        enrollmentId: atSecurityKeys.enrollmentId);

    await keyChainManager.storeAtSign(atSign: atSignItem);

    // Add atSign to the keychain.
    await keyChainManager.storeCredentialToKeychain(atsign,
        privateKey: atSecurityKeys.apkamPrivateKey,
        publicKey: atSecurityKeys.apkamPublicKey);
  }

  Future<void> _persistKeysLocalSecondary(AtSecurityKeys atSecurityKeys) async {
    await _atClient!
        .getLocalSecondary()!
        .putValue(AT_PKAM_PUBLIC_KEY, atSecurityKeys.apkamPublicKey!);

    // pkam private will not be available in case of secure element
    if (atSecurityKeys.apkamPrivateKey != null) {
      await _atClient!
          .getLocalSecondary()!
          .putValue(AT_PKAM_PRIVATE_KEY, atSecurityKeys.apkamPrivateKey!);
    }

    await _atClient!.getLocalSecondary()!.putValue(
        AT_ENCRYPTION_PRIVATE_KEY, atSecurityKeys.defaultEncryptionPrivateKey!);

    var updateBuilder = UpdateVerbBuilder()
      ..atKey = 'publickey'
      ..isPublic = true
      ..sharedBy = _atSign
      ..value = atSecurityKeys.defaultEncryptionPublicKey
      ..metadata.ttr = -1;

    await _atClient!
        .getLocalSecondary()!
        .executeVerb(updateBuilder, sync: true);

    await _atClient!.getLocalSecondary()!.putValue(
        AT_ENCRYPTION_SELF_KEY, atSecurityKeys.defaultSelfEncryptionKey!);
  }

  Future<void> _init(AtSecurityKeys atSecurityKeys,
      {String? enrollmentId}) async {
    await _initAtClient(atChops!, enrollmentId: enrollmentId);
    _atLookUp!.atChops = atChops;
    _atClient!.atChops = atChops;
    _atClient!.getPreferences()!.useAtChops = true;
  }

  Future<void> _initAtClient(AtChops atChops, {String? enrollmentId}) async {
    AtClientManager atClientManager = AtClientManager.getInstance();
    await atClientManager.setCurrentAtSign(
        _atSign, _atClientPreference.namespace, _atClientPreference,
        atChops: atChops,
        serviceFactory: atServiceFactory,
        enrollmentId: enrollmentId);
    // ??= to support mocking
    _atLookUp ??= atClientManager.atClient.getRemoteSecondary()?.atLookUp;
    _atLookUp?.enrollmentId = enrollmentId;
    _atLookUp?.signingAlgoType = _atClientPreference.signingAlgoType;
    _atLookUp?.hashingAlgoType = _atClientPreference.hashingAlgoType;
    _atClient ??= atClientManager.atClient;
  }

  AtChops _createAtChops(AtSecurityKeys atKeysFile) {
    final atEncryptionKeyPair = AtEncryptionKeyPair.create(
        atKeysFile.defaultEncryptionPublicKey!,
        atKeysFile.defaultEncryptionPrivateKey!);
    final atPkamKeyPair = AtPkamKeyPair.create(
        atKeysFile.apkamPublicKey!, atKeysFile.apkamPrivateKey!);
    final atChopsKeys = AtChopsKeys.create(atEncryptionKeyPair, atPkamKeyPair);
    if (atKeysFile.apkamSymmetricKey != null) {
      atChopsKeys.apkamSymmetricKey = AESKey(atKeysFile.apkamSymmetricKey!);
    }
    atChopsKeys.selfEncryptionKey =
        AESKey(atKeysFile.defaultSelfEncryptionKey!);
    return AtChopsImpl(atChopsKeys);
  }

  AtSecurityKeys _decodeAndDecryptKeys(String jsonData, String decryptKey) {
    var extractedJsonData = jsonDecode(jsonData);
    var atSecurityKeys = AtSecurityKeys();
    var pkamPublicKey = EncryptionUtil.decryptValue(
        extractedJsonData[BackupKeyConstants.PKAM_PUBLIC_KEY_FROM_KEY_FILE],
        decryptKey);
    atSecurityKeys.apkamPublicKey = pkamPublicKey;
    var pkamPrivateKeyFromFile =
        extractedJsonData[BackupKeyConstants.PKAM_PRIVATE_KEY_FROM_KEY_FILE];
    if (pkamPrivateKeyFromFile != null) {
      atSecurityKeys.apkamPrivateKey = EncryptionUtil.decryptValue(
          extractedJsonData[BackupKeyConstants.PKAM_PRIVATE_KEY_FROM_KEY_FILE],
          decryptKey);
    }

    atSecurityKeys.defaultEncryptionPublicKey = EncryptionUtil.decryptValue(
        extractedJsonData[BackupKeyConstants.ENCRYPTION_PUBLIC_KEY_FROM_FILE],
        decryptKey);

    atSecurityKeys.defaultEncryptionPrivateKey = EncryptionUtil.decryptValue(
        extractedJsonData[BackupKeyConstants.ENCRYPTION_PRIVATE_KEY_FROM_FILE],
        decryptKey);

    atSecurityKeys.apkamSymmetricKey =
        extractedJsonData[BackupKeyConstants.APKAM_SYMMETRIC_KEY_FROM_FILE];
    atSecurityKeys.enrollmentId =
        extractedJsonData[BackupKeyConstants.APKAM_ENROLLMENT_ID_FROM_FILE];
    return atSecurityKeys;
  }

  @override
  Future<EnrollResponse> enroll(EnrollRequest atEnrollmentRequest) async {
    var enrollResponse = await atEnrollmentService!.enroll(atEnrollmentRequest);
    return enrollResponse;
  }
}
