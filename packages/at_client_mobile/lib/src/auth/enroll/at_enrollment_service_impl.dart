import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_client_mobile/src/auth/at_auth_service.dart';
import 'package:at_client_mobile/src/auth/at_security_keys.dart';
import 'package:at_client_mobile/src/auth/enroll/at_enrollment_service.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_file_saver/at_file_saver.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';
import 'package:crypton/crypton.dart';

class AtEnrollmentServiceImpl implements AtEnrollmentService {
  final AtSignLogger _logger = AtSignLogger('AtEnrollmentServiceImpl');
  KeyChainManager keyChainManager = KeyChainManager.getInstance();
  AtClientManager atClientManager = AtClientManager.getInstance();
  String _atSign;
  AtClientPreference _atClientPreference;
  final StreamController<String> _pkamSuccessController =
      StreamController<String>();

  Stream<dynamic> get _onPkamSuccess => _pkamSuccessController.stream;

  AtEnrollmentServiceImpl(this._atSign, this._atClientPreference);

  @override
  Future<EnrollResponse> enroll(EnrollRequest atEnrollmentRequest) async {
    final Duration retryInterval =
        Duration(minutes: atEnrollmentRequest.pkamRetryIntervalMins);
    _logger.info('Generating apkam encryption keypair and apkam symmetric key');
    //1. Generate new apkam key pair and apkam symmetric key
    var apkamKeyPair = keyChainManager.generateKeyPair();
    var apkamSymmetricKey = keyChainManager.generateAESKey();

    AtLookupImpl atLookUpImpl = AtLookupImpl(
        _atSign, _atClientPreference.rootDomain, _atClientPreference.rootPort);

    //2. Retrieve default encryption public key and encrypt apkam symmetric key
    var defaultEncryptionPublicKey =
        await _retrieveEncryptionPublicKey(atLookUpImpl);
    var encryptedApkamSymmetricKey = EncryptionUtil.encryptKey(
        apkamSymmetricKey, defaultEncryptionPublicKey);

    //3. Send enroll request to server
    var enrollmentResponse = await _sendEnrollRequest(
        atEnrollmentRequest.appName,
        atEnrollmentRequest.deviceName,
        atEnrollmentRequest.otp,
        atEnrollmentRequest.namespaces,
        apkamKeyPair.publicKey.toString(),
        encryptedApkamSymmetricKey,
        atLookUpImpl);
    _logger.finer('EnrollmentResponse from server: $enrollmentResponse');

    //4. Create at chops instance
    var atChopsKeys = AtChopsKeys.create(
        null,
        AtPkamKeyPair.create(apkamKeyPair.publicKey.toString(),
            apkamKeyPair.privateKey.toString()));
    atLookUpImpl.atChops = AtChopsImpl(atChopsKeys);

    // Pkam auth will be attempted asynchronously until enrollment is approved/denied
    _attemptPkamAuthAsync(
        atLookUpImpl,
        enrollmentResponse.enrollmentId,
        retryInterval,
        apkamSymmetricKey,
        defaultEncryptionPublicKey,
        apkamKeyPair);

    // Upon successful pkam auth, callback _listenToPkamSuccessStream will  be invoked
    _listenToPkamSuccessStream(atLookUpImpl, apkamSymmetricKey,
        defaultEncryptionPublicKey, apkamKeyPair);

    return enrollmentResponse;
  }

  Future<String> _retrieveEncryptionPublicKey(AtLookUp atLookupImpl) async {
    var lookupVerbBuilder = LookupVerbBuilder()
      ..atKey = 'publickey'
      ..sharedBy = _atSign;
    var lookupResult = await atLookupImpl.executeVerb(lookupVerbBuilder);
    if (lookupResult == null || lookupResult.isEmpty) {
      throw AtEnrollmentException(
          'Unable to lookup encryption public key. Server response is null/empty');
    }
    var defaultEncryptionPublicKey = lookupResult.replaceFirst('data:', '');
    return defaultEncryptionPublicKey;
  }

  void _listenToPkamSuccessStream(
      AtLookupImpl atLookUpImpl,
      String apkamSymmetricKey,
      String defaultEncryptionPublicKey,
      RSAKeypair apkamKeyPair) {
    _onPkamSuccess.listen((enrollmentIdFromServer) async {
      _logger.finer('_listenToPkamSuccessStream invoked');
      var decryptedEncryptionPrivateKey = EncryptionUtil.decryptValue(
          await _getEncryptionPrivateKeyFromServer(
              enrollmentIdFromServer, atLookUpImpl),
          apkamSymmetricKey);
      var decryptedSelfEncryptionKey = EncryptionUtil.decryptValue(
          await _getSelfEncryptionKeyFromServer(
              enrollmentIdFromServer, atLookUpImpl),
          apkamSymmetricKey);

      var atSecurityKeys = AtSecurityKeys()
        ..defaultEncryptionPrivateKey = decryptedEncryptionPrivateKey
        ..defaultEncryptionPublicKey = defaultEncryptionPublicKey
        ..apkamSymmetricKey = apkamSymmetricKey
        ..defaultSelfEncryptionKey = decryptedSelfEncryptionKey
        ..apkamPublicKey = apkamKeyPair.publicKey.toString()
        ..apkamPrivateKey = apkamKeyPair.privateKey.toString();
      _logger.finer('Generating keys file for $enrollmentIdFromServer');
      await _generateAtKeysFile(enrollmentIdFromServer, atSecurityKeys);
    });
  }

  Future<void> _attemptPkamAuthAsync(
      AtLookupImpl atLookUpImpl,
      String enrollmentIdFromServer,
      Duration retryInterval,
      String apkamSymmetricKey,
      String defaultEncryptionPublicKey,
      RSAKeypair apkamKeyPair) async {
    // Pkam auth will be retried until server approves/denies/expires the enrollment
    while (true) {
      _logger.finer('Attempting pkam for $enrollmentIdFromServer');
      bool pkamAuthResult = await _attemptPkamAuth(
          atLookUpImpl, enrollmentIdFromServer, retryInterval);
      if (pkamAuthResult) {
        _logger.finer('Pkam auth successful for $enrollmentIdFromServer');
        _pkamSuccessController.add(enrollmentIdFromServer);
        break;
      }
      _logger.finer('Retrying pkam after mins: $retryInterval');
      await Future.delayed(retryInterval); // Delay and retry
    }
  }

  Future<bool> _attemptPkamAuth(AtLookUp atLookUp,
      String enrollmentIdFromServer, Duration retryInterval) async {
    try {
      var pkamResult =
          await atLookUp.pkamAuthenticate(enrollmentId: enrollmentIdFromServer);
      if (pkamResult) {
        return true;
      }
    } on UnAuthenticatedException catch (e) {
      if (e.message.contains('error:AT0401') ||
          e.message.contains('error:AT0026')) {
        _logger.finer('Retrying pkam auth');
        await Future.delayed(retryInterval);
      } else if (e.message.contains('error:AT0025')) {
        _logger.finer(
            'enrollmentId $enrollmentIdFromServer denied.Exiting pkam retry logic');
        throw AtEnrollmentException('enrollment denied');
      }
    }
    return false;
  }

  Future<EnrollResponse> _sendEnrollRequest(
      String appName,
      String deviceName,
      String otp,
      Map<String, String> namespaces,
      String apkamPublicKey,
      String encryptedApkamSymmetricKey,
      AtLookupImpl atLookUpImpl) async {
    var enrollVerbBuilder = EnrollVerbBuilder()
      ..appName = appName
      ..deviceName = deviceName
      ..namespaces = namespaces
      ..otp = otp
      ..apkamPublicKey = apkamPublicKey
      ..encryptedAPKAMSymmetricKey = encryptedApkamSymmetricKey;
    var enrollResult =
        await atLookUpImpl.executeCommand(enrollVerbBuilder.buildCommand());
    if (enrollResult == null ||
        enrollResult.isEmpty ||
        enrollResult.startsWith('error:')) {
      throw AtEnrollmentException(
          'Enrollment response from server: $enrollResult');
    }
    enrollResult = enrollResult.replaceFirst('data:', '');
    var enrollJson = jsonDecode(enrollResult);
    var enrollmentIdFromServer = enrollJson[enrollmentId];
    _logger.finer('enrollmentIdFromServer: $enrollmentIdFromServer');
    return EnrollResponse(enrollmentIdFromServer,
        getEnrollStatusFromString(enrollJson['status']));
  }

  Future<String> _getEncryptionPrivateKeyFromServer(
      String enrollmentIdFromServer, AtLookUp atLookUp) async {
    var privateKeyCommand =
        'keys:get:keyName:$enrollmentIdFromServer.$defaultEncryptionPrivateKey.__manage$_atSign\n';
    String encryptionPrivateKeyFromServer;
    try {
      var getPrivateKeyResult =
          await atLookUp.executeCommand(privateKeyCommand, auth: true);
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
    return encryptionPrivateKeyFromServer;
  }

  Future<String> _getSelfEncryptionKeyFromServer(
      String enrollmentIdFromServer, AtLookUp atLookUp) async {
    var selfEncryptionKeyCommand =
        'keys:get:keyName:$enrollmentIdFromServer.$defaultSelfEncryptionKey.__manage$_atSign\n';
    String selfEncryptionKeyFromServer;
    try {
      var getSelfEncryptionKeyResult =
          await atLookUp.executeCommand(selfEncryptionKeyCommand, auth: true);
      if (getSelfEncryptionKeyResult == null ||
          getSelfEncryptionKeyResult.isEmpty) {
        throw AtEnrollmentException(
            '$selfEncryptionKeyCommand returned null/empty');
      }
      getSelfEncryptionKeyResult =
          getSelfEncryptionKeyResult.replaceFirst('data:', '');
      var selfEncryptionKeyResultJson = jsonDecode(getSelfEncryptionKeyResult);
      selfEncryptionKeyFromServer = selfEncryptionKeyResultJson['value'];
    } on Exception catch (e) {
      throw AtEnrollmentException(
          'Exception while getting encrypted private key/self key from server: $e');
    }
    return selfEncryptionKeyFromServer;
  }

  Future<String> _generateAtKeysFile(
      enrollmentIdFromServer, AtSecurityKeys atSecurityKeys) async {
    String atKeysEncodedString = jsonEncode(atSecurityKeys.toMap());
    String fileName = '${_atSign}_key';
    String extension = '.atKeys';
    return await FileSaver.instance.saveFile(
        fileName, Uint8List.fromList(atKeysEncodedString.codeUnits), extension);
  }
}
