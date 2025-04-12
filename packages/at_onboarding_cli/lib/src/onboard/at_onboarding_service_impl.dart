// ignore_for_file: unnecessary_null_comparison

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart' as at_auth;
import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_onboarding_cli/src/factory/service_factories.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_server_status/at_server_status.dart';
import 'package:at_utils/at_progress.dart';
import 'package:at_utils/at_utils.dart';
import 'package:crypton/crypton.dart';
import 'package:encrypt/encrypt.dart';
import 'package:image/image.dart';
import 'package:meta/meta.dart';
import 'package:zxing2/qrcode.dart';

import '../util/home_directory_util.dart';
import '../util/onboarding_util.dart';

///class containing service that can onboard/activate/authenticate @signs
class AtOnboardingServiceImpl implements AtOnboardingService {
  late final String _atSign;
  bool _isAtsignOnboarded = false;
  AtSignLogger logger = AtSignLogger('OnboardingCli');
  AtOnboardingPreference atOnboardingPreference;
  AtLookUp? _atLookUp;
  final _maxActivationRetries = 5;

  /// The object which controls what types of AtClients, NotificationServices
  /// and SyncServices get created when we call [AtClientManager.setCurrentAtSign].
  /// If [atServiceFactory] is not set, AtClientManager.setCurrentAtSign will use
  /// a [DefaultAtServiceFactory]
  AtServiceFactory? atServiceFactory;

  at_auth.AtEnrollmentBase? _atEnrollment;

  AtOnboardingServiceImpl(atsign, this.atOnboardingPreference,
      {this.atServiceFactory, String? enrollmentId}) {
    // performs atSign format checks on the atSign
    _atSign = AtUtils.fixAtSign(atsign);
    _atEnrollment ??= at_auth.atAuthBase.atEnrollment(_atSign);
    // set default LocalStorage paths for this instance
    atOnboardingPreference.commitLogPath ??=
        HomeDirectoryUtil.getCommitLogPath(_atSign, enrollmentId: enrollmentId);
    atOnboardingPreference.hiveStoragePath ??=
        HomeDirectoryUtil.getHiveStoragePath(_atSign,
            enrollmentId: enrollmentId);
    atOnboardingPreference.isLocalStoreRequired = true;
    atOnboardingPreference.atKeysFilePath ??=
        HomeDirectoryUtil.getAtKeysPath(_atSign);
  }

  Future<void> _initAtClient(AtChops atChops, {String? enrollmentId}) async {
    AtClientManager atClientManager = AtClientManager.getInstance();
    if (atOnboardingPreference.skipSync) {
      atServiceFactory = ServiceFactoryWithNoOpSyncService();
    }
    await atClientManager.setCurrentAtSign(
        _atSign, atOnboardingPreference.namespace, atOnboardingPreference,
        atChops: atChops,
        serviceFactory: atServiceFactory,
        enrollmentId: enrollmentId);
    // ??= to support mocking
    _atLookUp ??= atClientManager.atClient.getRemoteSecondary()?.atLookUp;
    _atLookUp?.enrollmentId = enrollmentId;
    _atLookUp?.signingAlgoType = atOnboardingPreference.signingAlgoType;
    _atLookUp?.hashingAlgoType = atOnboardingPreference.hashingAlgoType;
    atClient ??= atClientManager.atClient;
    _atLookUp!.atChops = atChops;
  }

  @override
  @Deprecated('Use getter')
  Future<AtClient?> getAtClient() async {
    return atClient;
  }

  @override
  Future<bool> onboard({bool autoCompleteActivation = true}) async {
    // cram auth doesn't use at_chops. So create at_lookup here.
    AtLookupImpl atLookUpImpl = AtLookupImpl(
      _atSign,
      atOnboardingPreference.rootDomain,
      atOnboardingPreference.rootPort,
    );

    // get cram_secret from either from AtOnboardingPreference
    // or fetch from the registrar using verification code sent to email
    atOnboardingPreference.cramSecret ??= await OnboardingUtil()
        .getCramUsingOtp(_atSign, atOnboardingPreference.registrarUrl);
    if (atOnboardingPreference.cramSecret == null) {
      logger.info('Root Server address is ${atOnboardingPreference.rootDomain}:'
          '${atOnboardingPreference.rootPort}');
      logger
          .info('Registrar url is \'${atOnboardingPreference.registrarUrl}\'');
      throw AtKeyNotFoundException(
          'Could not fetch cram secret for \'$_atSign\' from registrar');
    }

    // check and wait till secondary exists
    await _waitUntilSecondaryCreated(atLookUpImpl);

    if (await isOnboarded()) {
      throw AtActivateException('atsign $_atSign is already activated');
    }

    atAuth ??= at_auth.atAuthBase.atAuth();
    var atOnboardingRequest = at_auth.AtOnboardingRequest(_atSign);
    atOnboardingRequest.rootDomain = atOnboardingPreference.rootDomain;
    atOnboardingRequest.rootPort = atOnboardingPreference.rootPort;
    atOnboardingRequest.appName = atOnboardingPreference.appName;
    atOnboardingRequest.deviceName = atOnboardingPreference.deviceName;
    atOnboardingRequest.publicKeyId = atOnboardingPreference.publicKeyId;
    atOnboardingRequest.authMode = atOnboardingPreference.authMode;

    AtOnboardingResponse atOnboardingResponse = await atAuth!.onboard(
      atOnboardingRequest,
      atOnboardingPreference.cramSecret!,
      autoCompleteActivation: false, // we want to control this here
    );

    logger.finer('Onboarding Response: $atOnboardingResponse');
    if (atOnboardingResponse.isSuccessful) {
      logger.finer(
          'Onboarding successful.Generating keyfile in path: ${atOnboardingPreference.atKeysFilePath}');
      await _generateAtKeysFile(
        atOnboardingResponse.atAuthKeys!,
        enrollmentId: atOnboardingResponse.enrollmentId,
      );

      if (autoCompleteActivation) {
        await completeActivation();
      }
    }
    _isAtsignOnboarded = atOnboardingResponse.isSuccessful;
    return _isAtsignOnboarded;
  }

  @override
  Future<void> completeActivation() async {
    await atAuth!.completeActivation();
  }

  @override
  Future<at_auth.AtEnrollmentResponse> enroll(
    String appName,
    String deviceName,
    String otp,
    Map<String, String> namespaces, {
    Duration retryInterval = AtOnboardingService.defaultApkamRetryInterval,
    File? atKeysFile,
    bool allowOverwrite = false,
  }) async {
    AtEnrollmentResponse enrollmentResponse = await sendEnrollRequest(
      appName,
      deviceName,
      otp,
      namespaces,
    );
    logger.finer('EnrollmentResponse from server: $enrollmentResponse');

    await awaitApproval(enrollmentResponse, retryInterval: retryInterval);

    await _initAtClient(_atLookUp!.atChops!,
        enrollmentId: enrollmentResponse.enrollmentId);
    var atData = AtData();
    var enrollmentDetails = EnrollmentDetails();
    enrollmentDetails.namespace = namespaces;
    atData.data = jsonEncode(enrollmentDetails);
    // Cannot use atClient.put since The "_isAuthorized" method fetches enrollment
    // info from the key-store. Since there is no enrollment info,
    // it returns null and throws throws AtKeyNotFoundException.
    var localEnrollmentKey = AtKey()
      ..isLocal = true
      ..key = enrollmentResponse.enrollmentId
      ..sharedBy = atClient!.getCurrentAtSign();
    final putResult = await atClient!
        .getLocalSecondary()!
        .keyStore!
        .put(localEnrollmentKey.toString(), atData);
    logger.finer('putResult for storing enrollment details: $putResult');

    await createAtKeysFile(
      enrollmentResponse,
      atKeysFile: atKeysFile,
      allowOverwrite: allowOverwrite,
    );

    return enrollmentResponse;
  }

  @override
  Future<File> createAtKeysFile(
    AtEnrollmentResponse er, {
    File? atKeysFile,
    bool allowOverwrite = false,
  }) async {
    return await _generateAtKeysFile(
      er.atAuthKeys!,
      enrollmentId: er.enrollmentId,
      atKeysFile: atKeysFile,
      allowOverwrite: allowOverwrite,
    );
  }

  @override
  Future<at_auth.AtEnrollmentResponse> sendEnrollRequest(String appName,
      String deviceName, String otp, Map<String, String> namespaces,
      {Duration? apkamKeysExpiryDuration}) async {
    if (appName == null || deviceName == null) {
      throw AtEnrollmentException(
          'appName and deviceName are mandatory for enrollment');
    }

    at_auth.EnrollmentRequest newClientEnrollmentRequest =
        at_auth.EnrollmentRequest(
            appName: appName,
            deviceName: deviceName,
            namespaces: namespaces,
            otp: otp);
    newClientEnrollmentRequest.apkamKeysExpiryDuration =
        apkamKeysExpiryDuration;

    AtLookupImpl atLookUpImpl = AtLookupImpl(_atSign,
        atOnboardingPreference.rootDomain, atOnboardingPreference.rootPort);
    logger.finer('sendEnrollRequest: submitting enrollment request');
    AtEnrollmentResponse response =
        await _atEnrollment!.submit(newClientEnrollmentRequest, atLookUpImpl);
    logger.finer('sendEnrollRequest: received server response: $response');

    return response;
  }

  @override
  Future<void> awaitApproval(
    AtEnrollmentResponse enrollmentResponse, {
    Duration retryInterval = AtOnboardingService.defaultApkamRetryInterval,
    bool logProgress = true,
  }) async {
    AtChopsKeys atChopsKeys = AtChopsKeys.create(
        AtEncryptionKeyPair.create(
            enrollmentResponse.atAuthKeys!.defaultEncryptionPublicKey!, ''),
        AtPkamKeyPair.create(enrollmentResponse.atAuthKeys!.apkamPublicKey!,
            enrollmentResponse.atAuthKeys!.apkamPrivateKey!));
    atChopsKeys.apkamSymmetricKey =
        AESKey(enrollmentResponse.atAuthKeys!.apkamSymmetricKey!);

    AtLookupImpl atLookUpImpl = AtLookupImpl(_atSign,
        atOnboardingPreference.rootDomain, atOnboardingPreference.rootPort);

    atLookUpImpl.atChops = AtChopsImpl(atChopsKeys);
    // ?? to support mocking
    _atLookUp ??= atLookUpImpl;

    // Pkam auth will be attempted asynchronously until enrollment is approved
    // or denied or times out. If denied or timed out, an exception will be
    // thrown
    await _waitForPkamAuthSuccess(
      _atLookUp!,
      enrollmentResponse.enrollmentId,
      retryInterval,
      logProgress: logProgress,
    );

    // Fetches encrypted "defaultEncryptionPrivateKey" from server. The first
    // argument holds the "defaultEncryptionPrivateKey" and the second argument
    // hold the Initialization Vector(IV) to decrypt the data.
    // Defaults to null to support legacy IV for backward compatibility.
    (String, String?) encryptedPrivateKey =
        await _getEncryptionPrivateKeyFromServer(
            enrollmentResponse.enrollmentId, _atLookUp!);

    var decryptedEncryptionPrivateKey = EncryptionUtil.decryptValue(
        encryptedPrivateKey.$1,
        enrollmentResponse.atAuthKeys!.apkamSymmetricKey!,
        ivBase64: encryptedPrivateKey.$2);

    // Fetches encrypted "selfEncryptionKey" from server. The first
    // argument holds the "selfEncryptionKey" and the second argument
    // hold the Initialization Vector(IV) to decrypt the data.
    // Defaults to null to support legacy IV for backward compatibility.
    (String, String?) selfEncryptionKey = await _getSelfEncryptionKeyFromServer(
        enrollmentResponse.enrollmentId, _atLookUp!);
    var decryptedSelfEncryptionKey = EncryptionUtil.decryptValue(
        selfEncryptionKey.$1, enrollmentResponse.atAuthKeys!.apkamSymmetricKey!,
        ivBase64: selfEncryptionKey.$2);

    enrollmentResponse.atAuthKeys!.defaultEncryptionPrivateKey =
        decryptedEncryptionPrivateKey;
    enrollmentResponse.atAuthKeys!.defaultSelfEncryptionKey =
        decryptedSelfEncryptionKey;
  }

  /// Retrieves the encryption private key and its associated initialization vector (IV)
  /// from the server for a given enrollment.
  ///
  /// The `privateKeyCommand` is constructed using the `enrollmentIdFromServer` and
  /// `AtConstants.defaultEncryptionPrivateKey` with the format:
  /// `'keys:get:keyName:<enrollmentId>.<defaultPrivateKey>.__manage$_atSign'`.
  ///
  /// This method sends a command to the `atLookUp` service to retrieve the private key data
  /// from the server, then parses the JSON result to extract the private key (`value`) and
  /// the IV (`iv`).
  ///
  /// Throws an [AtEnrollmentException] if:
  /// - The private key returned from the server is `null` or empty.
  /// - There is an exception during command execution.
  ///
  /// Returns:
  /// - A tuple containing:
  ///   - `encryptionPrivateKeyFromServer` - The encrypted private key string from the server.
  ///   - `encryptionPrivateKeyIV` - The associated IV string, if present.
  Future<(String, String?)> _getEncryptionPrivateKeyFromServer(
      String enrollmentIdFromServer, AtLookUp atLookUp) async {
    var privateKeyCommand =
        'keys:get:keyName:$enrollmentIdFromServer.${AtConstants.defaultEncryptionPrivateKey}.__manage$_atSign\n';
    String encryptionPrivateKeyFromServer;
    String? encryptionPrivateKeyIV;
    try {
      var getPrivateKeyResult =
          await atLookUp.executeCommand(privateKeyCommand, auth: true);
      getPrivateKeyResult =
          getPrivateKeyResult?.replaceFirst(RegExp(r'^data:'), '');
      var privateKeyResultJson = jsonDecode(getPrivateKeyResult!);
      encryptionPrivateKeyFromServer = privateKeyResultJson['value'];
      encryptionPrivateKeyIV = privateKeyResultJson['iv'];
      if (encryptionPrivateKeyFromServer == null ||
          encryptionPrivateKeyFromServer.isEmpty) {
        throw AtEnrollmentException('$privateKeyCommand returned null/empty');
      }
    } on Exception catch (e) {
      throw AtEnrollmentException(
          'Exception while getting encrypted private key/self key from server: $e');
    }
    return (encryptionPrivateKeyFromServer, encryptionPrivateKeyIV);
  }

  /// Retrieves the self-encryption key and its associated initialization vector (IV)
  /// from the server for a given enrollment.
  ///
  /// The `selfEncryptionKeyCommand` is constructed using the `enrollmentIdFromServer`
  /// and `AtConstants.defaultSelfEncryptionKey` in the format:
  /// `'keys:get:keyName:<enrollmentId>.<defaultSelfEncryptionKey>.__manage$_atSign'`.
  ///
  /// This method sends a command to the `atLookUp` service to retrieve the self-encryption key data
  /// from the server, then parses the JSON result to extract the key (`value`) and
  /// the IV (`iv`).
  ///
  /// Throws an [AtEnrollmentException] if:
  /// - The self-encryption key returned from the server is `null` or empty.
  /// - There is an exception during the command execution.
  ///
  /// Parameters:
  /// - `enrollmentIdFromServer` - The enrollment ID used to request the self-encryption key.
  /// - `atLookUp` - The [AtLookUp] instance to execute the server command.
  ///
  /// Returns:
  /// - A tuple containing:
  ///   - `selfEncryptionKeyFromServer` - The self-encryption key string retrieved from the server.
  ///   - `selfEncryptionKeyIV` - The associated IV string, if present.
  Future<(String, String?)> _getSelfEncryptionKeyFromServer(
      String enrollmentIdFromServer, AtLookUp atLookUp) async {
    var selfEncryptionKeyCommand =
        'keys:get:keyName:$enrollmentIdFromServer.${AtConstants.defaultSelfEncryptionKey}.__manage$_atSign\n';
    String selfEncryptionKeyFromServer;
    String? selfEncryptionKeyIV;
    try {
      var getSelfEncryptionKeyResult =
          await atLookUp.executeCommand(selfEncryptionKeyCommand, auth: true);
      getSelfEncryptionKeyResult =
          getSelfEncryptionKeyResult?.replaceFirst(RegExp(r'^data:'), '');
      var selfEncryptionKeyResultJson = jsonDecode(getSelfEncryptionKeyResult!);
      selfEncryptionKeyFromServer = selfEncryptionKeyResultJson['value'];
      selfEncryptionKeyIV = selfEncryptionKeyResultJson['iv'];
      if (selfEncryptionKeyFromServer == null ||
          selfEncryptionKeyFromServer.isEmpty) {
        throw AtEnrollmentException(
            '$selfEncryptionKeyCommand returned null/empty');
      }
    } on Exception catch (e) {
      throw AtEnrollmentException(
          'Exception while getting encrypted private key/self key from server: $e');
    }
    return (selfEncryptionKeyFromServer, selfEncryptionKeyIV);
  }

  /// Pkam auth will be retried until server approves/denies/expires the enrollment
  Future<void> _waitForPkamAuthSuccess(
    AtLookUp atLookUp,
    String enrollmentIdFromServer,
    Duration retryInterval, {
    bool logProgress = true,
  }) async {
    int retryAttempt = 1;
    while (true) {
      logger.info('Attempting pkam auth');
      if (logProgress) {
        stderr.write('Checking ... ');
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
            'Exception occurred when authenticating the atSign: $_atSign caused by ${e.toString()}';
        if (retryAttempt > _maxActivationRetries) {
          message += ' Activation failed after $_maxActivationRetries attempts';
          logger.severe(message);
          rethrow;
        }
        logger
            .severe('$message. Attempting to retry for $retryAttempt attempt');
        retryAttempt++;
      }
      if (pkamAuthSucceeded) {
        if (logProgress) {
          stderr.writeln(' approved.');
        }
        logger.info('Authentication succeeded - request was approved');
        return;
      } else {
        if (logProgress) {
          stderr.writeln(' not approved. Will retry'
              ' in ${retryInterval.inSeconds} seconds');
        }
        logger.info('Will retry pkam in ${retryInterval.inSeconds} seconds');
        await Future.delayed(retryInterval); // Delay and retry
      }
    }
  }

  ///write newly created encryption keypairs into atKeys file
  Future<File> _generateAtKeysFile(
    at_auth.AtAuthKeys atAuthKeys, {
    String? enrollmentId,
    File? atKeysFile,
    bool allowOverwrite = true,
  }) async {
    if (atKeysFile == null) {
      if (!atOnboardingPreference.atKeysFilePath!.endsWith('.atKeys')) {
        atOnboardingPreference.atKeysFilePath =
            '${atOnboardingPreference.atKeysFilePath}.atKeys';
      }
      atKeysFile = File(atOnboardingPreference.atKeysFilePath!);
    }

    if (atKeysFile.existsSync() && !allowOverwrite) {
      throw StateError('atKeys file ${atKeysFile.path} already exists');
    }

    logger.finer('Generating keys file at ${atKeysFile.path}'
        ' with enrollmentId $enrollmentId');

    final atKeysMap = <String, String>{
      AuthKeyType.pkamPublicKey: EncryptionUtil.encryptValue(
        atAuthKeys.apkamPublicKey!,
        atAuthKeys.defaultSelfEncryptionKey!,
      ),
      AuthKeyType.encryptionPublicKey: EncryptionUtil.encryptValue(
        atAuthKeys.defaultEncryptionPublicKey!,
        atAuthKeys.defaultSelfEncryptionKey!,
      ),
      AuthKeyType.encryptionPrivateKey: EncryptionUtil.encryptValue(
        atAuthKeys.defaultEncryptionPrivateKey!,
        atAuthKeys.defaultSelfEncryptionKey!,
      ),
      AuthKeyType.selfEncryptionKey: atAuthKeys.defaultSelfEncryptionKey!,
      _atSign: atAuthKeys.defaultSelfEncryptionKey!,
      AuthKeyType.apkamSymmetricKey: atAuthKeys.apkamSymmetricKey!
    };

    if (enrollmentId != null) {
      atKeysMap['enrollmentId'] = enrollmentId;
    }

    if (atOnboardingPreference.authMode == PkamAuthMode.keysFile) {
      atKeysMap[AuthKeyType.pkamPrivateKey] = EncryptionUtil.encryptValue(
          atAuthKeys.apkamPrivateKey!, atAuthKeys.defaultSelfEncryptionKey!);
    }

    atKeysFile.createSync(recursive: true);
    IOSink fileWriter = atKeysFile.openWrite();
    String encodedAtKeysString = jsonEncode(atKeysMap);

    if (atOnboardingPreference.passPhrase != null) {
      AtEncrypted atEncrypted = await AtKeysCrypto.fromHashingAlgorithm(
              atOnboardingPreference.hashingAlgoType)
          .encrypt(encodedAtKeysString, atOnboardingPreference.passPhrase!);
      encodedAtKeysString = atEncrypted.toString();
      stdout.writeln(
          '[Information] Encrypted atKeys file with the given pass phrase');
    }
    //generating .atKeys file at path provided in onboardingConfig
    fileWriter.write(encodedAtKeysString);
    await fileWriter.flush();
    await fileWriter.close();
    stdout.writeln(
        '[Success] Your .atKeys file saved at ${atOnboardingPreference.atKeysFilePath}\n');

    return atKeysFile;
  }

  ///back-up encryption keys to local secondary
  /// #TODO remove this method in future when all keys are read from AtChops
  Future<void> _persistKeysLocalSecondary(at_auth.AtAuthKeys atAuthKeys) async {
    //backup keys into local secondary
    bool? response = await atClient
        ?.getLocalSecondary()
        ?.putValue(AtConstants.atPkamPublicKey, atAuthKeys.apkamPublicKey!);
    logger.finer('PkamPublicKey persist to localSecondary: status $response');
    // save pkam private key only when auth mode is keyFile. if auth mode is sim/any other secure element private key cannot be read and hence will not be part of keys file
    if (atOnboardingPreference.authMode == PkamAuthMode.keysFile) {
      response = await atClient
          ?.getLocalSecondary()
          ?.putValue(AtConstants.atPkamPrivateKey, atAuthKeys.apkamPrivateKey!);
      logger
          .finer('PkamPrivateKey persist to localSecondary: status $response');
    }
    response = await atClient?.getLocalSecondary()?.putValue(
        '${AtConstants.atEncryptionPublicKey}$_atSign',
        atAuthKeys.defaultEncryptionPublicKey!);
    logger.finer(
        'EncryptionPublicKey persist to localSecondary: status $response');
    response = await atClient?.getLocalSecondary()?.putValue(
        AtConstants.atEncryptionPrivateKey,
        atAuthKeys.defaultEncryptionPrivateKey!);
    logger.finer(
        'EncryptionPrivateKey persist to localSecondary: status $response');
    response = await atClient?.getLocalSecondary()?.putValue(
        AtConstants.atEncryptionSelfKey, atAuthKeys.defaultSelfEncryptionKey!);
  }

  @override
  Future<bool> authenticate({String? enrollmentId}) async {
    atAuth ??= at_auth.atAuthBase.atAuth();
    var atAuthRequest = at_auth.AtAuthRequest(_atSign)
      ..enrollmentId = enrollmentId
      ..atKeysFilePath = atOnboardingPreference.atKeysFilePath
      ..authMode = atOnboardingPreference.authMode
      ..rootDomain = atOnboardingPreference.rootDomain
      ..rootPort = atOnboardingPreference.rootPort
      ..publicKeyId = atOnboardingPreference.publicKeyId
      ..passPhrase = atOnboardingPreference.passPhrase;
    var atAuthResponse = await atAuth!.authenticate(atAuthRequest);
    logger.finer('Auth response: $atAuthResponse');
    if (atAuthResponse.isSuccessful &&
        atOnboardingPreference.atKeysFilePath != null) {
      logger.finer('Calling persist keys to local secondary');
      await _initAtClient(atAuth!.atChops!,
          enrollmentId: atAuthResponse.enrollmentId);
      await _persistKeysLocalSecondary(atAuthResponse.atAuthKeys!);
    }

    return atAuthResponse.isSuccessful;
  }

  ///method to read and return data from .atKeysFile
  ///returns map containing encryption keys
  @visibleForTesting
  Future<Map<String, String>> readAtKeysFile(String? atKeysFilePath) async {
    if (atKeysFilePath == null || atKeysFilePath.isEmpty) {
      throw AtClientException.message(
          'atKeys filePath is empty. atKeysFile is required to authenticate');
    }
    String atAuthData = await File(atKeysFilePath).readAsString();
    Map<String, String> jsonData = <String, String>{};
    json.decode(atAuthData).forEach((String key, dynamic value) {
      jsonData[key] = value.toString();
    });
    return jsonData;
  }

  ///generates random RSA keypair
  RSAKeypair generateRsaKeypair() {
    return RSAKeypair.fromRandom();
  }

  ///generate random AES key
  String generateAESKey() {
    return AES(Key.fromSecureRandom(32)).key.base64;
  }

  ///returns secondary server status
  Future<AtStatus> getServerStatus() {
    AtServerStatus atServerStatus = AtStatusImpl(
        rootUrl: atOnboardingPreference.rootDomain,
        rootPort: atOnboardingPreference.rootPort);
    return atServerStatus.get(_atSign);
  }

  @override
  Future<bool> isOnboarded() async {
    late AtStatus secondaryStatus;
    try {
      secondaryStatus = await getServerStatus();
    } catch (e) {
      stderr.writeln('[Error] $e');
    }
    if (secondaryStatus.status() == AtSignStatus.activated) {
      _isAtsignOnboarded = true;
      return _isAtsignOnboarded;
    } else if (secondaryStatus.status() == AtSignStatus.teapot) {
      return false;
    }
    stderr.writeln(
        '[Error] atsign($_atSign) status is \'${secondaryStatus.status()!.name}\'');
    throw AtActivateException('Could not determine atsign activation status',
        intent: Intent.fetchData);
  }

  ///extracts cram secret from qrCode
  @Deprecated('qr_code based cram authentication not supported anymore')
  static String? getSecretFromQr(String? path) {
    if (path == null) {
      return null;
    }
    try {
      Image? image = decodePng(File(path).readAsBytesSync());
      LuminanceSource source = RGBLuminanceSource(
          image!.width, image.height, image.getBytes().buffer.asInt32List());
      BinaryBitmap bitmap = BinaryBitmap(HybridBinarizer(source));
      Result result = QRCodeReader().decode(bitmap);
      String secret = result.text.split(':')[1];
      return secret;
    } on Exception catch (e) {
      stdout.writeln('exception while getting secret from QR code: $e');
      return null;
    }
  }

  /// Method to check if secondary belonging to [_atSign] has been created
  /// If not, wait until secondary is created. Makes 50 retry attempts, 2 sec apart
  Future<void> _waitUntilSecondaryCreated(AtLookupImpl atLookupImpl) async {
    final maxRetries = 50;
    int retryCount = 1;
    SecondaryAddress? secondaryAddress;
    SecureSocket? secureSocket;

    while (retryCount <= maxRetries && secondaryAddress == null) {
      if (retryCount > 1) {
        await Future.delayed(Duration(seconds: 2));
      }
      _addProgress(
        'findAtServer',
        'looking up (#[$retryCount/$maxRetries])atDirectory for $_atSign',
        false,
      );
      logger.finer(
          'retrying findAtServer for $_atSign... #[$retryCount/$maxRetries]');
      try {
        secondaryAddress =
            await atLookupImpl.secondaryAddressFinder.findSecondary(_atSign);
      } catch (e, trace) {
        _addProgress('findAtServer', e.toString(), true);
        logger.finer(e);
        logger.finer(trace);
      }
      retryCount++;
    }
    if (secondaryAddress == null) {
      String msg = 'Could not find atServer address for'
          ' $_atSign after $retryCount retries.'
          ' Please rerun your command or contact your support';
      throw SecondaryNotFoundException(msg);
    }
    _addProgress(
      'findAtServer',
      'Found atServer address for $_atSign in atDirectory - $secondaryAddress',
      true,
    );

    retryCount = 1;
    bool connected = false;
    while (!connected && retryCount <= maxRetries) {
      if (retryCount > 1) {
        await Future.delayed(Duration(seconds: 2));
      }
      var msg = 'Connecting to atServer for $_atSign... #[$retryCount/$maxRetries]';
      _addProgress('connect', msg, false);
      try {
        secureSocket = await SecureSocket.connect(
            secondaryAddress.host, secondaryAddress.port,
            timeout: Duration(
                seconds:
                    30)); // 30-second timeout should be enough even for slow networks
        connected = secureSocket.remoteAddress != null &&
            secureSocket.remotePort != null;
      } catch (e, trace) {
        _addProgress('connect', e.toString(), true);
        logger.finer(e);
        logger.finer(trace);
      }
      retryCount++;
    }
    if (!connected) {
      if (secondaryAddress == null) {
        String msg = 'Could not connect to atServer for'
            ' $_atSign at $secondaryAddress after $retryCount attempts.'
            ' Please rerun your command or contact your support';
        throw SecondaryConnectException(msg);
      }
    }
  }

  @override
  Future<void> close() async {
    logger.info('Closing');
    if (_atLookUp != null &&
        (_atLookUp as AtLookupImpl).isConnectionAvailable()) {
      await _atLookUp!.close();
    }
    atClient?.notificationService.stopAllSubscriptions();
    _atLookUp = null;
    atClient = null;
    logger.info('Closed');
  }

  @override
  @Deprecated('Use getter')
  AtLookUp? getAtLookup() {
    return _atLookUp;
  }

  @override
  AtClient? atClient;

  @override
  set atLookUp(AtLookUp? atLookUp) {
    _atLookUp = atLookUp;
  }

  @visibleForTesting
  set enrollmentBase(at_auth.AtEnrollmentBase enrollmentBase) {
    _atEnrollment = enrollmentBase;
  }

  @override
  AtLookUp? get atLookUp => _atLookUp;

  @override
  @Deprecated('AtChops will be created in AtAuth')
  AtChops? atChops;

  @override
  at_auth.AtAuth? atAuth;

  final StreamController<ProgressEvent> _psc = StreamController.broadcast();

  @override
  Stream<ProgressEvent> subscribeProgress() {
    return _psc.stream;
  }

  @override
  addProgress(ProgressEvent pe) {
    _psc.add(pe);
  }

  _addProgress(String type, String msg, bool isError) {
    addProgress(ProgressEvent(DateTime.now(), type, msg, isError));
  }
}

class EnrollmentDetails {
  late Map<String, dynamic> namespace;

  static EnrollmentDetails fromJSON(Map<String, dynamic> json) {
    return EnrollmentDetails()..namespace = json['namespace'];
  }

  Map<String, dynamic> toJson() {
    Map<String, dynamic> map = {};
    map['namespace'] = namespace;
    return map;
  }
}
