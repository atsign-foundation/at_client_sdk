import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/src/auth/cram_authenticator.dart';
import 'package:at_auth/src/auth/pkam_authenticator.dart';
import 'package:at_auth/src/auth_constants.dart' as auth_constants;
import 'package:at_auth/src/enroll/first_enrollment_request.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';

import 'enroll/at_enrollment_impl.dart';

class AtAuthImpl implements AtAuth {
  final AtSignLogger _logger = AtSignLogger('AtAuthServiceImpl');
  final String _defaultAppNameForOnboarding = 'firstApp';
  final String _defaultDeviceNameForOnboarding = 'firstDevice';
  @override
  AtChops? atChops;

  CramAuthenticator? cramAuthenticator;

  PkamAuthenticator? pkamAuthenticator;

  AtEnrollmentBase? atEnrollmentBase;

  AtLookUp? atLookUp;

  AtAuthImpl(
      {this.atLookUp,
      this.atChops,
      this.cramAuthenticator,
      this.pkamAuthenticator,
      this.atEnrollmentBase});

  @override
  Future<AtAuthResponse> authenticate(AtAuthRequest atAuthRequest) async {
    if (atAuthRequest.atKeysFilePath == null &&
        atAuthRequest.atAuthKeys == null &&
        atAuthRequest.encryptedKeysMap == null) {
      throw AtAuthenticationException(
          'Keyfile path or atAuthKeys object has to be set in atAuthRequest');
    }
    // decrypts all the keys in .atKeysFile using the SelfEncryptionKey
    // and stores the keys in a map
    AtAuthKeys? atAuthKeys;
    var enrollmentIdFromRequest = atAuthRequest.enrollmentId;
    if (atAuthRequest.atKeysFilePath != null) {
      atAuthKeys = await _prepareAtAuthKeysFromFilePath(atAuthRequest);
    } else if (atAuthRequest.encryptedKeysMap != null) {
      atAuthKeys = await _decryptAtKeysWithSelfEncKey(
          atAuthRequest.encryptedKeysMap!, PkamAuthMode.keysFile);
    } else {
      atAuthKeys = atAuthRequest.atAuthKeys;
    }
    if (atAuthKeys == null) {
      throw AtAuthenticationException(
          'keys either were not provided in the AtAuthRequest,'
          ' or could not be read from provided keys file');
    }
    enrollmentIdFromRequest ??= atAuthKeys.enrollmentId;
    var pkamPrivateKey = atAuthKeys.apkamPrivateKey;

    if (atAuthRequest.authMode == PkamAuthMode.keysFile &&
        pkamPrivateKey == null) {
      throw AtPrivateKeyNotFoundException(
          'Unable to read PkamPrivateKey from provided atKeys file/atAuthKeys object',
          exceptionScenario: ExceptionScenario.invalidValueProvided);
    }
    atLookUp ??= AtLookupImpl(
        atAuthRequest.atSign, atAuthRequest.rootDomain, atAuthRequest.rootPort);
    // ??= to support mocking
    atChops ??= _createAtChops(atAuthKeys);
    atLookUp!.atChops = atChops;

    _logger.finer('Authenticating using PKAM');
    var isPkamAuthenticated = false;
    pkamAuthenticator ??= PkamAuthenticator(atAuthRequest.atSign, atLookUp!);
    try {
      var pkamResponse = (await pkamAuthenticator!
          .authenticate(enrollmentId: enrollmentIdFromRequest));
      isPkamAuthenticated = pkamResponse.isSuccessful;
    } on AtException catch (e) {
      _logger.severe('Caught $e');
      throw AtAuthenticationException(
          'Unable to authenticate | Cause: ${e.message}');
    } on Exception catch (e) {
      throw AtAuthenticationException('Unable to authenticate | Cause: $e');
    }
    _logger.finer(
        'PKAM auth result: ${isPkamAuthenticated ? 'success' : 'failed'}');
    return AtAuthResponse(atAuthRequest.atSign)
      ..isSuccessful = isPkamAuthenticated
      ..enrollmentId = enrollmentIdFromRequest
      ..atAuthKeys = atAuthKeys;
  }

  @override
  Future<AtOnboardingResponse> onboard(
      AtOnboardingRequest atOnboardingRequest, String cramSecret) async {
    var atOnboardingResponse = AtOnboardingResponse(atOnboardingRequest.atSign);
    atEnrollmentBase = AtEnrollmentImpl(atOnboardingRequest.atSign);
    atLookUp ??= AtLookupImpl(atOnboardingRequest.atSign,
        atOnboardingRequest.rootDomain, atOnboardingRequest.rootPort);

    //1. cram auth
    cramAuthenticator ??=
        CramAuthenticator(atOnboardingRequest.atSign, cramSecret, atLookUp);
    var cramAuthResult = await cramAuthenticator!.authenticate();
    if (!cramAuthResult.isSuccessful) {
      throw AtAuthenticationException(
          'Cram authentication failed. Please check the cram key'
          ' and try again (or) contact support@atsign.com');
    }
    //2. generate key pairs
    var atAuthKeys = _generateKeyPairs(atOnboardingRequest.authMode,
        publicKeyId: atOnboardingRequest.publicKeyId);

    atChops ??= _createAtChops(atAuthKeys);
    atLookUp!.atChops = atChops;

    //3. send onboarding enrollment
    String? enrollmentIdFromServer;
    // server will update the apkam public key during enrollment.
    // So don't have to manually update apkam public key in this scenario.
    enrollmentIdFromServer = await _sendOnboardingEnrollment(
        atOnboardingRequest, atAuthKeys, atLookUp!);
    atAuthKeys.enrollmentId = enrollmentIdFromServer;

    //4. Close connection to server
    try {
      await (atLookUp as AtLookupImpl).close();
    } on Exception catch (e) {
      _logger.severe('error while closing connection to server: $e');
    }

    //5. Init _atLookUp again and attempt pkam auth
    // atLookUp = AtLookupImpl(atOnboardingRequest.atSign,
    //     atOnboardingRequest.rootDomain, atOnboardingRequest.rootPort);
    atLookUp!.atChops = atChops;

    var isPkamAuthenticated = false;
    //6. Do pkam auth
    pkamAuthenticator ??=
        PkamAuthenticator(atOnboardingRequest.atSign, atLookUp!);
    try {
      var pkamResponse = await pkamAuthenticator!
          .authenticate(enrollmentId: enrollmentIdFromServer);
      isPkamAuthenticated = pkamResponse.isSuccessful;
    } on UnAuthenticatedException catch (e) {
      throw AtAuthenticationException('Pkam auth failed - $e ');
    }
    if (!isPkamAuthenticated) {
      throw AtAuthenticationException('Pkam auth returned false');
    }

    //7. If Pkam auth is success, update encryption public key to secondary
    // and delete cram key from server
    final encryptionPublicKey = atAuthKeys.defaultEncryptionPublicKey;
    UpdateVerbBuilder updateBuilder = UpdateVerbBuilder()
      ..atKey = (AtKey()
        ..key = 'publickey'
        ..sharedBy = atOnboardingRequest.atSign
        ..metadata = (Metadata()
          ..isPublic = true
          ..ttr = -1))
      ..value = encryptionPublicKey;
    String? encryptKeyUpdateResult = await atLookUp!.executeVerb(updateBuilder);
    _logger.info('Encryption public key update result $encryptKeyUpdateResult');

    //8.  Delete cram secret from the keystore as cram auth is complete
    DeleteVerbBuilder deleteBuilder = DeleteVerbBuilder()
      ..atKey = (AtKey()..key = AtConstants.atCramSecret);
    String? deleteResponse = await atLookUp!.executeVerb(deleteBuilder);
    _logger.info('Cram secret delete response : $deleteResponse');
    atOnboardingResponse.isSuccessful = true;
    atOnboardingResponse.enrollmentId = enrollmentIdFromServer;
    atOnboardingResponse.atAuthKeys = atAuthKeys;
    return atOnboardingResponse;
  }

  AtChops _createAtChops(AtAuthKeys atKeysFile) {
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

  Future<String> _sendOnboardingEnrollment(
      AtOnboardingRequest atOnboardingRequest,
      AtAuthKeys atAuthKeys,
      AtLookUp atLookup) async {
    atOnboardingRequest.appName ??= _defaultAppNameForOnboarding;
    atOnboardingRequest.deviceName ??= _defaultDeviceNameForOnboarding;
    AESEncryptionAlgo symmetricEncryptionAlgo =
        AESEncryptionAlgo(AESKey(atAuthKeys.apkamSymmetricKey!));
    // Encrypt the defaultEncryptionPrivateKey with APKAM Symmetric key
    String encryptedDefaultEncryptionPrivateKey = atChops!
        .encryptString(
            atAuthKeys.defaultEncryptionPrivateKey!, EncryptionKeyType.aes256,
            encryptionAlgorithm: symmetricEncryptionAlgo,
            iv: AtChopsUtil.generateIVLegacy())
        .result;
    // Encrypt the Self Encryption Key with APKAM Symmetric key
    String encryptedDefaultSelfEncryptionKey = atChops!
        .encryptString(
            atAuthKeys.defaultSelfEncryptionKey!, EncryptionKeyType.aes256,
            encryptionAlgorithm: symmetricEncryptionAlgo,
            iv: AtChopsUtil.generateIVLegacy())
        .result;

    _logger.finer('apkamPublicKey: ${atAuthKeys.apkamPublicKey}');

    FirstEnrollmentRequest firstEnrollmentRequest = FirstEnrollmentRequest(
        appName: atOnboardingRequest.appName!,
        deviceName: atOnboardingRequest.deviceName!,
        apkamPublicKey: atAuthKeys.apkamPublicKey!,
        encryptedDefaultEncryptionPrivateKey:
            encryptedDefaultEncryptionPrivateKey,
        encryptedDefaultSelfEncryptionKey: encryptedDefaultSelfEncryptionKey);

    AtEnrollmentResponse? atEnrollmentResponse;
    try {
      atEnrollmentResponse =
          await atEnrollmentBase?.submit(firstEnrollmentRequest, atLookUp!);
    } on AtEnrollmentException catch (e) {
      throw AtAuthenticationException('Enrollment error:${e.toString}');
    }
    _logger.finer('enrollment response: ${atEnrollmentResponse.toString()}');
    var enrollmentIdFromServer = atEnrollmentResponse?.enrollmentId;
    var enrollmentStatus = atEnrollmentResponse?.enrollStatus;
    if (enrollmentStatus != EnrollmentStatus.approved) {
      throw AtAuthenticationException(
          'initial enrollment is not approved. Status from server: $enrollmentStatus');
    }
    return enrollmentIdFromServer!;
  }

  AtAuthKeys _decryptAtKeysWithSelfEncKey(
      Map<String, dynamic> jsonData, PkamAuthMode authMode) {
    var securityKeys = AtAuthKeys();
    String decryptionKey = jsonData[auth_constants.defaultSelfEncryptionKey]!;
    var atChops =
        AtChopsImpl(AtChopsKeys()..selfEncryptionKey = AESKey(decryptionKey));
    securityKeys.defaultEncryptionPublicKey = atChops
        .decryptString(jsonData[auth_constants.defaultEncryptionPublicKey]!,
            EncryptionKeyType.aes256,
            keyName: 'selfEncryptionKey', iv: AtChopsUtil.generateIVLegacy())
        .result;
    securityKeys.defaultEncryptionPrivateKey = atChops
        .decryptString(jsonData[auth_constants.defaultEncryptionPrivateKey]!,
            EncryptionKeyType.aes256,
            keyName: 'selfEncryptionKey', iv: AtChopsUtil.generateIVLegacy())
        .result;
    securityKeys.defaultSelfEncryptionKey = decryptionKey;
    securityKeys.apkamPublicKey = atChops
        .decryptString(
            jsonData[auth_constants.apkamPublicKey]!, EncryptionKeyType.aes256,
            keyName: 'selfEncryptionKey', iv: AtChopsUtil.generateIVLegacy())
        .result;
    // pkam private key will not be saved in keyfile if auth mode is sim/any other secure element.
    // decrypt the private key only when auth mode is keysFile
    if (authMode == PkamAuthMode.keysFile) {
      securityKeys.apkamPrivateKey = atChops
          .decryptString(jsonData[auth_constants.apkamPrivateKey]!,
              EncryptionKeyType.aes256,
              keyName: 'selfEncryptionKey', iv: AtChopsUtil.generateIVLegacy())
          .result;
    }
    securityKeys.apkamSymmetricKey = jsonData[auth_constants.apkamSymmetricKey];
    securityKeys.enrollmentId = jsonData[AtConstants.enrollmentId];
    return securityKeys;
  }

  ///method to read and return data from .atKeysFile
  ///returns map containing encryption keys
  Future<AtAuthKeys> _prepareAtAuthKeysFromFilePath(
      AtAuthRequest atAuthRequest) async {
    if (atAuthRequest.atKeysFilePath == null ||
        atAuthRequest.atKeysFilePath!.isEmpty) {
      throw AtException(
          'atKeys filePath is empty. atKeysFile is required to authenticate');
    }
    if (!File(atAuthRequest.atKeysFilePath!).existsSync()) {
      throw AtException(
          'provided keys file does not exist. Please check whether the file path ${atAuthRequest.atKeysFilePath} is valid');
    }

    String atAuthData =
        await File(atAuthRequest.atKeysFilePath!).readAsString();
    Map<String, dynamic> decodedAtKeysData = jsonDecode(atAuthData);
    // If it contains "iv(InitializationVector)", it means the data is encrypted with a
    // passphrase. Decrypt it.
    if (decodedAtKeysData.containsKey('iv') &&
        atAuthRequest.passPhrase.isNullOrEmpty) {
      throw AtDecryptionException(
          'Pass Phrase is required for password protected atKeys file');
    }
    if (decodedAtKeysData.containsKey('iv')) {
      _logger.info(
          'Found encrypted atKeys files. Decrypting with the given pass-phrase');
      AtEncrypted atEncrypted = AtEncrypted.fromJson(decodedAtKeysData);

      if (atEncrypted.hashingAlgoType == null) {
        throw AtDecryptionException(
            'Hashing algo type is required for decryption of password protected atKeys file');
      }

      String decryptedAtKeys =
          await AtKeysCrypto.fromHashingAlgorithm(atEncrypted.hashingAlgoType!)
              .decrypt(atEncrypted, atAuthRequest.passPhrase!);
      decodedAtKeysData = jsonDecode(decryptedAtKeys);
    }
    // This is to decrypt the atKeys encrypted with self Encryption key.
    return _decryptAtKeysWithSelfEncKey(
        decodedAtKeysData, atAuthRequest.authMode);
  }

  AtAuthKeys _generateKeyPairs(PkamAuthMode authMode, {String? publicKeyId}) {
    // generate user encryption keypair
    _logger.info('Generating encryption keypair');
    var atEncryptionKeyPair = AtChopsUtil.generateAtEncryptionKeyPair();

    //generate selfEncryptionKey
    var selfEncryptionKey =
        AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256);
    var apkamSymmetricKey =
        AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256);
    var atKeysFile = AtAuthKeys();
    _logger.info(
        '[Information] Generating your encryption keys and .atKeys file\n');
    //generating pkamKeyPair only if authMode is keysFile
    String? pkamPublicKey;
    if (authMode == PkamAuthMode.keysFile) {
      _logger.info('Generating pkam keypair');
      var apkamRsaKeypair = AtChopsUtil.generateAtPkamKeyPair();
      pkamPublicKey = apkamRsaKeypair.atPublicKey.publicKey.toString();
      atKeysFile.apkamPrivateKey =
          apkamRsaKeypair.atPrivateKey.privateKey.toString();
    } else if (authMode == PkamAuthMode.sim) {
      // get the public key from secure element
      pkamPublicKey = atChops!.readPublicKey(publicKeyId!);
      _logger.info('pkam  public key from sim: ${atKeysFile.apkamPublicKey}');

      // encryption key pair and self encryption symmetric key
      // are not available to injected at_chops. Set it here
      atChops!.atChopsKeys.atEncryptionKeyPair = atEncryptionKeyPair;
      atChops!.atChopsKeys.selfEncryptionKey = selfEncryptionKey;
      atChops!.atChopsKeys.apkamSymmetricKey = apkamSymmetricKey;
    }
    atKeysFile.apkamPublicKey = pkamPublicKey;
    //Standard order of an atKeys file is ->
    // pkam keypair -> encryption keypair -> selfEncryption key -> enrollmentId --> apkam symmetric key -->
    // @sign: selfEncryptionKey[self encryption key again]
    // note: "->" stands for "followed by"
    atKeysFile.defaultEncryptionPublicKey =
        atEncryptionKeyPair.atPublicKey.publicKey.toString();
    atKeysFile.defaultEncryptionPrivateKey =
        atEncryptionKeyPair.atPrivateKey.privateKey.toString();
    atKeysFile.defaultSelfEncryptionKey = selfEncryptionKey.key;
    atKeysFile.apkamSymmetricKey = apkamSymmetricKey.key;

    return atKeysFile;
  }
}
