// ignore_for_file: unnecessary_null_comparison

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/at_auth_io.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_onboarding_cli/src/factory/service_factories.dart';
import 'package:at_server_status/at_server_status.dart';
import 'package:at_utils/at_progress.dart';
import 'package:at_utils/at_utils.dart';
import 'package:chalkdart/chalk.dart';
import 'package:image/image.dart';
import 'package:meta/meta.dart';
import 'package:zxing2/qrcode.dart';

import '../util/at_file_util.dart';
import '../util/home_directory_util.dart';
import 'helpers/enrollment_checkpoint.dart';

/// Service implementation responsible for onboarding and authenticating atSigns.
///
/// Also has implementation to create, approve, deny and revoke enrollments.
class AtOnboardingServiceImpl implements AtOnboardingService {
  final Atsign _atSign;
  bool _isAtsignOnboarded = false;
  AtSignLogger logger = AtSignLogger('OnboardingCli');
  AtOnboardingPreference atOnboardingPreference;
  AtLookUp? _atLookUp;

  /// The object which controls what types of AtClients, NotificationServices
  /// and SyncServices get created when we call [AtClientManager.setCurrentAtSign].
  ///
  /// If [atServiceFactory] is not set, AtClientManager.setCurrentAtSign will use
  /// a [DefaultAtServiceFactory]
  AtServiceFactory? atServiceFactory;

  AtEnrollment? _atEnrollment;

  @visibleForTesting
  late EnrollmentCheckpoint enrollCheckpoint;

  AtOnboardingServiceImpl(
    String atsign,
    this.atOnboardingPreference, {
    this.atServiceFactory,
    String? enrollmentId,
  }) : _atSign = atsign.toAtsign() {
    _atEnrollment ??= AtEnrollment.create();
    enrollCheckpoint = EnrollmentCheckpoint(_atSign);

    // set default LocalStorage paths for this instance
    atOnboardingPreference.commitLogPath ??=
        HomeDirectoryUtil.getCommitLogPath(_atSign, enrollmentId: enrollmentId);
    atOnboardingPreference.hiveStoragePath ??=
        HomeDirectoryUtil.getHiveStoragePath(_atSign,
            enrollmentId: enrollmentId);
    atOnboardingPreference.atKeysFilePath ??=
        HomeDirectoryUtil.getAtKeysPath(_atSign);
  }

  bool get _isUsingProxy => atOnboardingPreference.isUsingProxy;

  /// Sends from: command if using proxy
  ///
  /// [context] - description of the operation for logging (defaults to 'sendFromCommand')
  ///
  /// [atSign] - the atSign to send the from: command for (defaults to current atSign)
  Future<bool> _sendFromCommandIfUsingProxy(AtLookUp atLookUp,
      {String context = 'sendFromCommand', String? atSign}) async {
    if (!_isUsingProxy) {
      return false;
    }

    String targetAtSign = atSign ?? _atSign;
    try {
      String? fromResponse =
          await atLookUp.executeCommand('from:$targetAtSign\n', auth: false);
      logger.info(
          '$context: from: command successful for $targetAtSign, response: $fromResponse');

      if (fromResponse == null || fromResponse.isEmpty) {
        logger.warning(
            '$context: from: command returned empty response for $targetAtSign');
        return false;
      }
      if (fromResponse.contains('error:')) {
        logger.warning(
            '$context: from: command returned error for $targetAtSign: $fromResponse');
        return false;
      }
      return true;
    } catch (e) {
      logger.warning(
          '$context: from: command failed for $targetAtSign: $e - continuing anyway');
      return false;
    }
  }

  Future<void> _initAtClient(AtChops atChops, {String? enrollmentId}) async {
    AtClientManager atClientManager = AtClientManager.getInstance();
    if (atOnboardingPreference.skipSync) {
      atServiceFactory = ServiceFactoryWithNoOpSyncService();
    }
    await atClientManager.setCurrentAtSign(
        _atSign, atOnboardingPreference.namespace, atOnboardingPreference,
        atChops: atChops,
        atLookUp: atLookUp,
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
  Future<bool> onboard({
    bool autoCompleteActivation = true,
    Duration retryInterval = AtOnboardingService.defaultActivationCheckInterval,
    int maxRetries = AtOnboardingService.defaultMaxActivationCheckRetries,
  }) async {
    // Fails early if the filePath already exists (or) isn't writable
    AtFileUtil.ensureWritable(File(atOnboardingPreference.atKeysFilePath!));

    // Ensure we have an AtLookUp instance and send from: command if using proxy
    AtLookupImpl atLookUpImpl = AtLookupImpl(
      _atSign,
      atOnboardingPreference.rootDomain,
      atOnboardingPreference.rootPort,
    );

    await _sendFromCommandIfUsingProxy(atLookUpImpl, context: 'onboard');

    // log the atOnboardingPreference.rootDomain and port
    logger.info('Root Server address is ${atOnboardingPreference.rootDomain}:'
        '${atOnboardingPreference.rootPort}');

    // Fetch from the registrar using verification code sent to email
    // if not provided through onboardingPreference
    if (atOnboardingPreference.cramSecret == null) {
      final util = OnboardingUtil();
      await util.requestAuthenticationOtp(
        _atSign,
        authority: atOnboardingPreference.registrarUrl,
      );

      String otp = util.getVerificationCodeFromUser();

      atOnboardingPreference.cramSecret = await util.getCramKey(
        _atSign,
        otp,
        authority: atOnboardingPreference.registrarUrl,
      );
    }

    if (atOnboardingPreference.cramSecret == null) {
      logger.info('Root Server address is ${atOnboardingPreference.rootDomain}:'
          '${atOnboardingPreference.rootPort}');
      logger
          .info('Registrar url is \'${atOnboardingPreference.registrarUrl}\'');
      throw AtKeyNotFoundException(
          'Could not fetch cram secret for \'$_atSign\' from registrar');
    }

    if (await isOnboarded()) {
      throw AtActivateException('atsign $_atSign is already activated');
    }

    atAuth ??= AtAuth.create();
    var atOnboardingRequest = AtOnboardingRequest(_atSign);
    atOnboardingRequest.rootDomain = AtRootDomain(
        atOnboardingPreference.rootDomain, atOnboardingPreference.rootPort);
    atOnboardingRequest.retryOptions =
        RetryOptions(maxRetries: maxRetries, retryDelay: retryInterval);
    atOnboardingRequest.atKeysIo = FileAtKeysIo(
      filePath: atOnboardingPreference.atKeysFilePath != null
          ? (_) => atOnboardingPreference.atKeysFilePath!
          : null,
    );

    AtOnboardingResponse atOnboardingResponse = await atAuth!.onboard(
      atOnboardingRequest,
      atOnboardingPreference.cramSecret!,
      autoCompleteActivation: false, // we want to control this here
    );

    logger.finer('Onboarding Response: $atOnboardingResponse');
    if (atOnboardingResponse.isSuccessful) {
      stdout.writeln('[Success] Your keyfile stored at'
          ' path: ${atOnboardingPreference.atKeysFilePath}');
      await AtFileUtil.setSecureFilePermissions(
          atOnboardingPreference.atKeysFilePath!);

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
  Future<AtEnrollmentResponse> enroll(
    String appName,
    String deviceName,
    String otp,
    Map<String, String> namespaces, {
    Duration retryInterval = AtOnboardingService.defaultApkamRetryInterval,
    int maxRetries = AtOnboardingService.defaultMaxApkamRetries,
    File? atKeysFile,
    Duration? apkamKeysExpiryDuration,
    bool allowOverwrite = false,
    SigningAlgoType signingAlgo = SigningAlgoType.rsa2048,
  }) async {
    // Fails early if the filePath already exists (or) isn't writable
    if (atKeysFile != null) {
      AtFileUtil.ensureWritable(atKeysFile);
    }

    // Resume from checkpoint if a previous enrollment was interrupted,
    // otherwise submit a new enrollment request and save a checkpoint.
    AtEnrollmentResponse? enrollmentResponse =
        enrollCheckpoint.load(appName, deviceName, namespaces);

    if (enrollmentResponse != null) {
      logger.info('Resuming from enrollment checkpoint...');
    } else {
      enrollmentResponse = await sendEnrollRequest(
        appName,
        deviceName,
        otp,
        namespaces,
        apkamKeysExpiryDuration: apkamKeysExpiryDuration,
        signingAlgo: signingAlgo,
      );
      logger.finer('EnrollmentResponse from server: $enrollmentResponse');
      await enrollCheckpoint.save(
          enrollmentResponse, appName, deviceName, namespaces,
          expiry: apkamKeysExpiryDuration);
    }

    stdout.writeln('Enrollment ID: ${enrollmentResponse.enrollmentId}');
    _addProgress('Enroll', 'Enrollment ID: ${enrollmentResponse.enrollmentId}',
        ProgressEventType.info);

    try {
      await awaitApproval(
        enrollmentResponse,
        retryInterval: retryInterval,
        maxRetries: maxRetries,
      );
    } finally {
      // Checkpoint is always removed after approval attempt, whether it
      // succeeds or throws
      enrollCheckpoint.delete(appName, deviceName, namespaces);
    }

    await _initAtClient(
      _atLookUp!.atChops!,
      enrollmentId: enrollmentResponse.enrollmentId,
    );

    // Store enrollment details in local secondary.
    var localEnrollmentKey = AtKey()
      ..isLocal = true
      ..key = enrollmentResponse.enrollmentId
      ..sharedBy = atClient!.getCurrentAtSign();
    EnrollmentDetails enrollmentDetails = EnrollmentDetails()
      ..namespace = namespaces;
    await atClient!.getLocalSecondary()!.putValue(
        localEnrollmentKey.toString(), jsonEncode(enrollmentDetails.toJson()));

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

  Future<void> waitBriefly({int millis = 500}) async {
    await Future.delayed(Duration(milliseconds: millis));
  }

  @override
  Future<AtEnrollmentResponse> sendEnrollRequest(String appName,
      String deviceName, String otp, Map<String, String> namespaces,
      {Duration? apkamKeysExpiryDuration,
      SigningAlgoType signingAlgo = SigningAlgoType.rsa2048}) async {
    if (appName == null || deviceName == null) {
      throw AtEnrollmentException(
          'appName and deviceName are mandatory for enrollment');
    }

    _atLookUp ??= AtLookupImpl(
      _atSign,
      atOnboardingPreference.rootDomain,
      atOnboardingPreference.rootPort,
    );

    AtEnrollmentRequest newClientEnrollmentRequest = AtEnrollmentRequest(
        atSign: _atSign,
        appName: appName,
        deviceName: deviceName,
        namespaces: namespaces,
        otp: otp,
        signingAlgo: signingAlgo);
    newClientEnrollmentRequest.apkamKeysExpiryDuration =
        apkamKeysExpiryDuration;

    AtLookupImpl atLookUpImpl = AtLookupImpl(_atSign,
        atOnboardingPreference.rootDomain, atOnboardingPreference.rootPort);

    if (_isUsingProxy) {
      // When using a proxy, send from: command to ensure correct atSign context
      await _sendFromCommandIfUsingProxy(atLookUpImpl, context: 'enroll');
    }

    logger.finer('sendEnrollRequest: submitting enrollment request');
    _addProgress(
        'Enroll', 'submitting enrollment request', ProgressEventType.info);
    await waitBriefly();

    AtEnrollmentResponse response =
        await _atEnrollment!.submit(newClientEnrollmentRequest, atLookUpImpl);
    logger.finer('sendEnrollRequest: received server response: $response');
    _addProgress('Enroll', 'submitted OK', ProgressEventType.success);

    return response;
  }

  @override
  Future<void> awaitApproval(
    AtEnrollmentResponse enrollmentResponse, {
    Duration retryInterval = AtOnboardingService.defaultApkamRetryInterval,
    bool logProgress = true,
    int maxRetries = AtOnboardingService.defaultMaxApkamRetries,
  }) async {
    _atLookUp ??= AtLookupImpl(
      _atSign,
      atOnboardingPreference.rootDomain,
      atOnboardingPreference.rootPort,
    );

    if (_isUsingProxy) {
      // When using a proxy, send from: command to ensure correct atSign context
      await _sendFromCommandIfUsingProxy(_atLookUp!, context: 'awaitApproval');
    }

    AtChopsKeys atChopsKeys = AtChopsKeys.create(
        AtEncryptionKeyPair.create(
            enrollmentResponse.atAuthKeys!.defaultEncryptionPublicKey!
                .toString(),
            ''),
        AtPkamKeyPair.create(
            enrollmentResponse.atAuthKeys!.apkamPublicKey!.toString(),
            enrollmentResponse.atAuthKeys!.apkamPrivateKey!.toString()));
    atChopsKeys.apkamSymmetricKey =
        AESKey(enrollmentResponse.atAuthKeys!.apkamSymmetricKey!.toString());

    // Create AtChops instance and assign it to the lookup for PKAM authentication
    AtChopsImpl atChops = AtChopsImpl(atChopsKeys);
    _atLookUp!.atChops = atChops;
    _atLookUp!.enrollmentId = enrollmentResponse.enrollmentId;

    // Pkam auth will be attempted asynchronously until enrollment is approved
    // or denied or times out. If denied or timed out, an exception will be
    // thrown
    await _waitForPkamAuthSuccess(
      _atLookUp!,
      enrollmentResponse.enrollmentId,
      retryInterval,
      logProgress: logProgress,
      maxRetries: maxRetries,
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
        enrollmentResponse.atAuthKeys!.apkamSymmetricKey!.toString(),
        ivBase64: encryptedPrivateKey.$2);

    // Fetches encrypted "selfEncryptionKey" from server. The first
    // argument holds the "selfEncryptionKey" and the second argument
    // hold the Initialization Vector(IV) to decrypt the data.
    // Defaults to null to support legacy IV for backward compatibility.
    (String, String?) selfEncryptionKey = await _getSelfEncryptionKeyFromServer(
        enrollmentResponse.enrollmentId, _atLookUp!);
    var decryptedSelfEncryptionKey = EncryptionUtil.decryptValue(
        selfEncryptionKey.$1,
        enrollmentResponse.atAuthKeys!.apkamSymmetricKey!.toString(),
        ivBase64: selfEncryptionKey.$2);

    enrollmentResponse.atAuthKeys!.defaultEncryptionPrivateKey =
        AtBytes.fromString(decryptedEncryptionPrivateKey);
    enrollmentResponse.atAuthKeys!.defaultSelfEncryptionKey =
        AtBytes.fromString(decryptedSelfEncryptionKey);
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

  /// Retries PKAM auth until an enrollment is approved/denied/expired
  Future<void> _waitForPkamAuthSuccess(
    AtLookUp atLookUp,
    String enrollmentIdFromServer,
    Duration retryInterval, {
    bool logProgress = true,
    required int maxRetries,
  }) async {
    int retryAttempt = 0;
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
            'Exception occurred when authenticating the atSign: $_atSign caused by ${e.toString()}';
        if (retryAttempt > maxRetries) {
          message += ' Activation failed after $maxRetries attempts';
          logger.severe(message);
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

  /// Write newly created encryption key-pairs into atKeys file
  Future<File> _generateAtKeysFile(
    AtKeys atAuthKeys, {
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
      AuthKeyType.aesEncryptedPkamPublicKey: EncryptionUtil.encryptValue(
        atAuthKeys.apkamPublicKey!.toString(),
        atAuthKeys.defaultSelfEncryptionKey!.toString(),
      ),
      AuthKeyType.aesEncryptedEncryptionPublicKey: EncryptionUtil.encryptValue(
        atAuthKeys.defaultEncryptionPublicKey!.toString(),
        atAuthKeys.defaultSelfEncryptionKey!.toString(),
      ),
      AuthKeyType.aesEncryptedEncryptionPrivateKey: EncryptionUtil.encryptValue(
        atAuthKeys.defaultEncryptionPrivateKey!.toString(),
        atAuthKeys.defaultSelfEncryptionKey!.toString(),
      ),
      AuthKeyType.selfEncryptionKey:
          atAuthKeys.defaultSelfEncryptionKey!.toString(),
      _atSign: atAuthKeys.defaultSelfEncryptionKey!.toString(),
      AuthKeyType.apkamSymmetricKey: atAuthKeys.apkamSymmetricKey!.toString()
    };

    if (enrollmentId != null) {
      atKeysMap['enrollmentId'] = enrollmentId;
    }

    if (atOnboardingPreference.authMode == PkamAuthMode.keysFile) {
      atKeysMap[AuthKeyType.aesEncryptedPkamPrivateKey] =
          EncryptionUtil.encryptValue(atAuthKeys.apkamPrivateKey!.toString(),
              atAuthKeys.defaultSelfEncryptionKey!.toString());
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
          '${chalk.blue('[Information]')} Encrypted atKeys file with the given pass phrase');
    }
    //generating .atKeys file at path provided in onboardingConfig
    fileWriter.write(encodedAtKeysString);
    await fileWriter.flush();
    await fileWriter.close();
    await AtFileUtil.setSecureFilePermissions(atKeysFile.path);
    stdout.writeln(
        '${chalk.green('[Success]')} Your .atKeys file saved at ${atKeysFile.path}\n');

    return atKeysFile;
  }

  /// Back-up encryption keys to local secondary
  /// #TODO remove this method in future when all keys are read from AtChops
  Future<void> _persistKeysLocalSecondary(AtKeys atAuthKeys) async {
    //backup keys into local secondary
    bool? response = await atClient?.getLocalSecondary()?.putValue(
        AtConstants.atPkamPublicKey, atAuthKeys.apkamPublicKey!.toString());
    logger.finer('PkamPublicKey persist to localSecondary: status $response');
    // Save the PKAM private key only when the auth mode is keyFile.
    // In SIM or other secure element modes, the private key cannot be
    // read and therefore won't be included in the keys file.
    if (atOnboardingPreference.authMode == PkamAuthMode.keysFile) {
      response = await atClient?.getLocalSecondary()?.putValue(
          AtConstants.atPkamPrivateKey, atAuthKeys.apkamPrivateKey!.toString());
      logger
          .finer('PkamPrivateKey persist to localSecondary: status $response');
    }
    response = await atClient?.getLocalSecondary()?.putValue(
        '${AtConstants.atEncryptionPublicKey}$_atSign',
        atAuthKeys.defaultEncryptionPublicKey!.toString());
    logger.finer(
        'EncryptionPublicKey persist to localSecondary: status $response');
    response = await atClient?.getLocalSecondary()?.putValue(
        AtConstants.atEncryptionPrivateKey,
        atAuthKeys.defaultEncryptionPrivateKey!.toString());
    logger.finer(
        'EncryptionPrivateKey persist to localSecondary: status $response');
    response = await atClient?.getLocalSecondary()?.putValue(
        AtConstants.atEncryptionSelfKey,
        atAuthKeys.defaultSelfEncryptionKey!.toString());
  }

  @override
  Future<bool> authenticate({String? enrollmentId}) async {
    atAuth ??= AtAuth.create();
    var atAuthRequest = AtAuthRequest(_atSign,
        atKeysIo: FileAtKeysIo(
            filePath: !atOnboardingPreference.atKeysFilePath.isNull
                ? (_) => atOnboardingPreference.atKeysFilePath!
                : null,
            passPhrase: atOnboardingPreference.passPhrase))
      ..enrollmentId = enrollmentId
      ..rootDomain = AtRootDomain(
          atOnboardingPreference.rootDomain, atOnboardingPreference.rootPort);
    var atAuthResponse = await atAuth!.authenticate(atAuthRequest);
    logger.finer('Auth response: $atAuthResponse');
    if (atAuthResponse.isSuccessful &&
        atOnboardingPreference.atKeysFilePath != null) {
      logger.finer('Calling persist keys to local secondary');
      await _initAtClient(atAuth!.atChops!,
          enrollmentId: atAuthResponse.atAuthKeys!.enrollmentId);
      await _persistKeysLocalSecondary(atAuthResponse.atAuthKeys!);
    }

    return atAuthResponse.isSuccessful;
  }

  /// Method to read and return data from .atKeysFile
  ///
  /// Returns map containing encryption keys
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

  /// Generates a random RSA encryption keypair (RSA-2048) via at_chops.
  AtEncryptionKeyPair generateRsaKeypair() {
    return AtChopsUtil.generateAtEncryptionKeyPair();
  }

  /// Generate a random AES key
  String generateAESKey() {
    return AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256).key;
  }

  /// Returns secondary server status
  Future<AtStatus> getServerStatus() async {
    AtServerStatus atServerStatus = AtStatusImpl(
        rootUrl: atOnboardingPreference.rootDomain,
        rootPort: atOnboardingPreference.rootPort);
    return atServerStatus.get(_atSign);
  }

  @override
  Future<bool> isOnboarded() async {
    if (_isUsingProxy) {
      // When using a proxy, try a simple lookup command that doesn't require auth
      AtLookUp atLookUp = AtLookupImpl(_atSign,
          atOnboardingPreference.rootDomain, atOnboardingPreference.rootPort);
      await _sendFromCommandIfUsingProxy(atLookUp, context: 'isOnboarded');

      try {
        String? pkeyResponse = await _atLookUp!
            .executeCommand('lookup:publickey$_atSign\n', auth: false);
        if (pkeyResponse != null &&
            !pkeyResponse.contains('error:') &&
            !pkeyResponse.contains('null') &&
            pkeyResponse.trim().isNotEmpty) {
          _isAtsignOnboarded = true;
          return true;
        }
        return false;
      } catch (e) {
        logger.info(
            'isOnboarded: lookup failed, trying alternative approach: $e');
        return false;
      }
    } else {
      // When not using a proxy, use the standard AtServerStatus method
      try {
        AtStatus secondaryStatus = await getServerStatus();
        if (secondaryStatus.status() == AtSignStatus.activated) {
          _isAtsignOnboarded = true;
          return true;
        }
        return false;
      } catch (e) {
        stderr.writeln('${chalk.brightRed('[Error]')} $e');
        throw AtActivateException(
            'Could not determine atsign activation status: $e',
            intent: Intent.fetchData);
      }
    }
  }

  // Extracts cram secret from qrCode
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

  @override
  Future<void> close() async {
    logger.info('Closing');
    if (_atLookUp != null &&
        (_atLookUp as AtLookupImpl).isConnectionAvailable()) {
      await _atLookUp!.close();
    }
    if (atClient != null) {
      await atClient!.stop();
    }
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
  set enrollmentBase(AtEnrollment enrollmentBase) {
    _atEnrollment = enrollmentBase;
  }

  @override
  AtLookUp? get atLookUp => _atLookUp;

  @override
  @Deprecated('AtChops will be created in AtAuth')
  AtChops? atChops;

  AtAuth? _atAuth;

  @override
  AtAuth? get atAuth => _atAuth;

  @override
  set atAuth(AtAuth? atAuth) {
    _atAuth = atAuth;
    _atAuth?.progressStream.listen((pe) {
      _psc.add(pe);
    });
  }

  final StreamController<ProgressEvent> _psc = StreamController.broadcast();

  @override
  Stream<ProgressEvent> subscribeProgress() {
    return _psc.stream;
  }

  void _addProgress(String group, String msg, ProgressEventType type) {
    _psc.add(ProgressEvent(group: group, msg: msg, type: type));
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
