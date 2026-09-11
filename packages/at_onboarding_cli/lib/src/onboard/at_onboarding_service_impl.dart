// ignore_for_file: unnecessary_null_comparison

// The PQ activation surface is @experimental, and this CLI ships from the
// same workspace.
// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/at_auth_io.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart'
    show
        enrollmentApkamSymmetricKeyResolver,
        enrollmentKeyPackageBuilder,
        makeActivationPqNative,
        mintAdvertisedSigningKey,
        mintSigningRootAfterActivation;
import 'package:at_lookup/at_lookup_io.dart';
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
  // NOTE: narrowing this to AtLookupMuxable breaks the assignment from
  // `RemoteSecondary.atLookUp`, which is typed AtLookUp, and narrows the
  // public `set atLookUp(AtLookUp?)` this class overrides, which is breaking.
  AtLookUp? _atLookUp;

  /// A lookup with no authenticator: [_installAuthenticator] supplies one
  /// afterwards from whichever credential the CLI holds.
  AtLookupMuxable _newLookUp() => AtLookUp.withSecureSocket(
        atSign: _atSign,
        rootDomain: AtRootDomain(
          atOnboardingPreference.rootDomain,
          atOnboardingPreference.rootPort,
        ),
        transport: secureSocketTransport(SecureSocketConfig()),
        authenticator: null,
      );

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
    atOnboardingPreference.storagePath ??=
        // ignore: deprecated_member_use
        atOnboardingPreference.hiveStoragePath ??
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

  /// The bundle this client opens: the caller's if it supplied one, otherwise
  /// a fresh Hive bundle the client closes when it stops.
  ///
  /// Fresh each time, because every call here stops the previous client first —
  /// which closes the bundle it was given — and a closed bundle cannot reopen.
  AtClientStorage _storageForClient() =>
      atOnboardingPreference.storage ??
      HiveAtClientStorage(
          atSign: _atSign,
          storagePath: atOnboardingPreference.storagePath!,
          closedByClient: true);

  /// Builds the client for this atSign from [atKeysIo], the keyfile it
  /// authenticates with. The client's own connection installs its
  /// authenticator from that source, and stamps what a lookup from before the
  /// authenticator seam reads; nothing is set on the lookup here.
  ///
  /// [atChops] is a signer that is not a keyfile — a secure element's — for a
  /// keyfile holding no APKAM private half. at_auth signs with the keyfile's
  /// keypair when it holds one and with this signer otherwise, so passing it
  /// beside a complete keyfile changes nothing.
  Future<void> _initAtClient(
      {required AtKeysIo atKeysIo,
      String? enrollmentId,
      AtChops? atChops}) async {
    AtClientManager atClientManager = AtClientManager.getInstance();
    if (atOnboardingPreference.skipSync) {
      atServiceFactory = ServiceFactoryWithNoOpSyncService();
    }
    // NOTE: atLookUp and enrollmentId are passed even when null, because a
    // caller-supplied override is what stops setCurrentAtSign short-circuiting
    // on an atSign that is already current; the client is rebuilt, and with it
    // the connection and the authenticator on it.
    await atClientManager.setCurrentAtSign(
        _atSign, atOnboardingPreference.namespace, atOnboardingPreference,
        atChops: atChops,
        atKeysIo: atKeysIo,
        atLookUp: atLookUp,
        serviceFactory: atServiceFactory,
        enrollmentId: enrollmentId,
        storage: _storageForClient());

    // ??= to support mocking
    _atLookUp ??= atClientManager.atClient.getRemoteSecondary()?.atLookUp;
    _adoptBuiltClient(atClientManager.atClient);
  }

  /// Points [atClient] at [built] when this service holds none, or holds one
  /// the manager has since stopped; a client somebody injected stays.
  void _adoptBuiltClient(AtClient built) {
    final held = atClient;
    if (held == null || (held is AtClientImpl && held.isStopped)) {
      atClient = built;
    }
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
    final atLookUpImpl = _newLookUp();

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
    // NOTE: the preference is what `authenticate()` stamps on the connection,
    // so minting under anything else hands at_chops a key of one algorithm and
    // a declaration of another.
    var atOnboardingRequest = AtOnboardingRequest(_atSign,
        signingAlgoType: atOnboardingPreference.authenticationKeyAlgorithm);
    atOnboardingRequest.rootDomain = AtRootDomain(
        atOnboardingPreference.rootDomain, atOnboardingPreference.rootPort);
    atOnboardingRequest.retryOptions =
        RetryOptions(maxRetries: maxRetries, retryDelay: retryInterval);
    final atKeysIo = FileAtKeysIo(
      filePath: atOnboardingPreference.atKeysFilePath != null
          ? (_) => atOnboardingPreference.atKeysFilePath!
          : null,
      passPhrase: atOnboardingPreference.passPhrase,
    );
    atOnboardingRequest.atKeysIo = atKeysIo;

    // NOTE: matched on mldsa65 exactly, not on "anything but rsa2048" —
    // ecc_secp256r1 is a third, classical option this package supports, and
    // treating it as post-quantum would silently mint an ML-DSA APKAM for a
    // caller who asked for an elliptic-curve one. The activation itself is
    // all-or-nothing: an ML-DSA APKAM without a key package produces an atSign
    // no sender can address until that enrollment sends an `enroll:update` for
    // itself.
    final bool pqNative = atOnboardingPreference.authenticationKeyAlgorithm ==
        SigningAlgoType.mldsa65;
    if (pqNative) {
      await makeActivationPqNative(atOnboardingRequest,
          atSign: _atSign.toString(),
          dataSigningKeyAlgorithms:
              atOnboardingPreference.dataSigningKeyAlgorithms,
          keyEstablishmentAlgo:
              atOnboardingPreference.keyEstablishmentAlgorithms.first);
    }

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
      if (pqNative) {
        await _mintSigningRoot(atOnboardingResponse, atKeysIo);
      }
    }
    _isAtsignOnboarded = atOnboardingResponse.isSuccessful;
    return _isAtsignOnboarded;
  }

  /// Creates the atSign-level signing root, which needs a client and so cannot
  /// happen until the activation is done.
  ///
  /// Done while this process still holds the first enrollment, the one the
  /// atServer grants `__manage`, which is what entitles it to create the root.
  Future<void> _mintSigningRoot(
      AtOnboardingResponse response, AtKeysIo atKeysIo) async {
    final session = response.session;
    if (session == null) {
      logger.warning(
          '$_atSign activated post-quantum but the activation returned no '
          'session, so its signing root was not created here; the next start '
          'retries it');
      return;
    }
    final manager = await AtClientManager.getInstance().fromAuthSession(
        session, atOnboardingPreference,
        storage: _storageForClient());
    _adoptBuiltClient(manager.atClient);
    await mintSigningRootAfterActivation(manager.atClient, atKeysIo: atKeysIo);
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
    SigningAlgoType? signingAlgo,
    EnrollmentKeyExchangeMode? keyExchangeMode,
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
        keyExchangeMode: keyExchangeMode,
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

    // The keyfile first, holding the keys the handshake completed, and the
    // client from it: the same source it will authenticate with from now on.
    final keyfile = await createAtKeysFile(
      enrollmentResponse,
      atKeysFile: atKeysFile,
      allowOverwrite: allowOverwrite,
    );
    await _initAtClient(
      atKeysIo: FileAtKeysIo(
          filePath: (_) => keyfile.path,
          passPhrase: atOnboardingPreference.passPhrase),
      enrollmentId: enrollmentResponse.enrollmentId,
      atChops: atChops,
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
  Future<AtEnrollmentResponse> sendEnrollRequest(String appName,
      String deviceName, String otp, Map<String, String> namespaces,
      {Duration? apkamKeysExpiryDuration,
      SigningAlgoType? signingAlgo,
      EnrollmentKeyExchangeMode? keyExchangeMode}) async {
    // NOTE: the preference is what `authenticate()` stamps on the connection,
    // so minting under anything else hands at_chops a key of one algorithm and
    // a declaration of another.
    final algo =
        signingAlgo ?? atOnboardingPreference.authenticationKeyAlgorithm;
    if (appName == null || deviceName == null) {
      throw AtEnrollmentException(
          'appName and deviceName are mandatory for enrollment');
    }

    _atLookUp ??= _newLookUp();

    final mode =
        keyExchangeMode ?? atOnboardingPreference.posture.keyExchangeMode;

    // NOTE: `_apsk` must advertise a data signing key this enrollment owns
    // rather than its APKAM authentication key. Otherwise the first start
    // mints one and drops the advertised value: the key package stops
    // verifying, and any link an approver conveyed against it stops matching.
    final advertisedSigningKey = await mintAdvertisedSigningKey(
        atOnboardingPreference.dataSigningKeyAlgorithms);

    // NOTE: a pq request needs both callbacks and carries no wrapped key; a
    // legacy request carries the wrapped key and needs neither. The mode is
    // therefore the constructor rather than a field, so that no request can be
    // built in a shape at_auth has to refuse at runtime.
    final AtEnrollmentRequest newClientEnrollmentRequest;
    if (mode == EnrollmentKeyExchangeMode.pq) {
      newClientEnrollmentRequest = AtEnrollmentRequest.pq(
          atSign: _atSign,
          appName: appName,
          deviceName: deviceName,
          namespaces: namespaces,
          otp: otp,
          signingAlgo: algo,
          advertisedSigningKey: advertisedSigningKey,
          // NOTE: the builder signs the key package with the keypair this
          // request advertises, so it must be told the same `algo` and the
          // same advertised key. A package signed by anything else verifies
          // against a record that does not name its signer, so a peer that
          // resolves `_apsk` before sealing a secret seals nothing.
          metadataBuilder: enrollmentKeyPackageBuilder(_atSign,
              signingAlgo: algo,
              advertisedSigningKey: advertisedSigningKey,
              // An enrollment is created holding one encapsulation key; the
              // rest of the list is minted at the client's first startup.
              keyEstablishmentAlgo:
                  atOnboardingPreference.keyEstablishmentAlgorithms.first),
          apkamSymmetricKeyResolver:
              enrollmentApkamSymmetricKeyResolver(_atSign));
    } else {
      newClientEnrollmentRequest = AtEnrollmentRequest(
          atSign: _atSign,
          appName: appName,
          deviceName: deviceName,
          namespaces: namespaces,
          otp: otp,
          signingAlgo: algo,
          // Advertised whatever the mode, and without a key package: the mode
          // decides only whether a package exists, while `_apsk` is what every
          // peer verifies signatures against.
          advertisedSigningKey: advertisedSigningKey);
    }
    newClientEnrollmentRequest.apkamKeysExpiryDuration =
        apkamKeysExpiryDuration;

    final atLookUpImpl = _newLookUp();

    if (_isUsingProxy) {
      // When using a proxy, send from: command to ensure correct atSign context
      await _sendFromCommandIfUsingProxy(atLookUpImpl, context: 'enroll');
    }

    logger.finer('sendEnrollRequest: submitting enrollment request');
    _addProgress(
        'Enroll', 'submitting enrollment request', ProgressEventType.info);

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
    _atLookUp ??= _newLookUp();

    if (_isUsingProxy) {
      // When using a proxy, send from: command to ensure correct atSign context
      await _sendFromCommandIfUsingProxy(_atLookUp!, context: 'awaitApproval');
    }

    // NOTE: later steps re-authenticate on this connection, so the lookup must
    // know which enrollment it authenticates as; the delegate passes the id
    // per call and never stamps it.
    _atLookUp!.enrollmentId = enrollmentResponse.enrollmentId;

    // The delegate validates and addresses by both fields, so a response
    // resumed from a checkpoint gets them restored from what this service
    // already knows.
    // ignore: deprecated_member_use
    enrollmentResponse.atSign ??= _atSign;
    // ignore: deprecated_member_use
    enrollmentResponse.rootDomain ??= AtRootDomain(
        atOnboardingPreference.rootDomain, atOnboardingPreference.rootPort);

    _atEnrollment ??= AtEnrollment.create();
    final forward = _atEnrollment!.progressStream.listen(_psc.add);
    try {
      await _atEnrollment!.waitForApproval(
        enrollmentResponse,
        atLookup: _atLookUp,
        retryInterval: retryInterval,
        logProgress: logProgress,
        maxRetries: maxRetries,
      );
    } finally {
      await forward.cancel();
    }
  }

  /// Write newly created encryption key-pairs into atKeys file
  ///
  /// The keyfile is written by [FileAtKeysIo], the same store [authenticate]
  /// reads it back through.
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

    if (atKeysFile.existsSync()) {
      if (!allowOverwrite) {
        throw StateError('atKeys file ${atKeysFile.path} already exists');
      }
      // NOTE: `write` is create-only by contract and `flush` never loses, so
      // neither of them means "replace"; the old file goes first, at the
      // caller's request.
      await atKeysFile.delete();
    }

    logger.finer('Generating keys file at ${atKeysFile.path}'
        ' with enrollmentId $enrollmentId');

    if (enrollmentId != null) {
      atAuthKeys.enrollmentId = enrollmentId;
    }
    // NOTE: every .atKeys file carries the self-encryption key a second time
    // under the atSign itself. Nothing in this repo reads it back, but a
    // reader that expects it must keep finding it.
    final selfEncryptionKey = atAuthKeys.defaultSelfEncryptionKey;
    if (selfEncryptionKey != null) {
      atAuthKeys.metadata[_atSign] = selfEncryptionKey.toString();
    }
    if (atOnboardingPreference.authMode != PkamAuthMode.keysFile) {
      // In a SIM or another secure element the private half cannot be read,
      // and this file does not carry it.
      atAuthKeys.apkamPrivateKey = null;
    }

    await FileAtKeysIo(
      filePath: (_) => atKeysFile!.path,
      passPhrase: atOnboardingPreference.passPhrase,
    ).write(_atSign, atAuthKeys);

    if (atOnboardingPreference.passPhrase != null) {
      stdout.writeln(
          '${chalk.blue('[Information]')} Encrypted atKeys file with the given pass phrase');
    }
    await AtFileUtil.setSecureFilePermissions(atKeysFile.path);
    stdout.writeln(
        '${chalk.green('[Success]')} Your .atKeys file saved at ${atKeysFile.path}\n');

    return atKeysFile;
  }

  /// Back-up encryption keys to local secondary
  /// #TODO remove this method in future when all keys are read from AtChops
  ///
  /// Every field here is optional, and each absence is a legitimate shape: a
  /// PQ-native enrollment files its APKAM as typed material under the
  /// enrollment id and leaves the flat `apkamPublicKey`/`apkamPrivateKey`
  /// empty, and an atSign activated with `mintLegacyMaterial: false` has no
  /// RSA encryption keypair and no self-encryption key at all.
  Future<void> _persistKeysLocalSecondary(AtKeys atAuthKeys) async {
    Future<void> persist(String name, String key, AtBytes? value) async {
      if (value == null) {
        logger.finer('$name absent from the keyfile; nothing to persist to '
            'localSecondary');
        return;
      }
      final response =
          await atClient?.getLocalSecondary()?.putValue(key, value.toString());
      logger.finer('$name persist to localSecondary: status $response');
    }

    await persist('PkamPublicKey', AtConstants.atPkamPublicKey,
        atAuthKeys.apkamPublicKey);
    // Save the PKAM private key only when the auth mode is keyFile.
    // In SIM or other secure element modes, the private key cannot be
    // read and therefore won't be included in the keys file.
    if (atOnboardingPreference.authMode == PkamAuthMode.keysFile) {
      await persist('PkamPrivateKey', AtConstants.atPkamPrivateKey,
          atAuthKeys.apkamPrivateKey);
    }
    await persist(
        'EncryptionPublicKey',
        '${AtConstants.atEncryptionPublicKey}$_atSign',
        atAuthKeys.defaultEncryptionPublicKey);
    await persist('EncryptionPrivateKey', AtConstants.atEncryptionPrivateKey,
        atAuthKeys.defaultEncryptionPrivateKey);
    await persist('SelfEncryptionKey', AtConstants.atEncryptionSelfKey,
        atAuthKeys.defaultSelfEncryptionKey);
  }

  @override
  Future<bool> authenticate(
      {@Deprecated('the keyfile names the enrollment; a disagreeing value is '
          'logged at shout level and ignored')
      String? enrollmentId}) async {
    atAuth ??= AtAuth.create();
    // Held in a local so the client gets the same source auth read from,
    // rather than a second store built over the same path.
    final atKeysIo = FileAtKeysIo(
        filePath: !atOnboardingPreference.atKeysFilePath.isNull
            ? (_) => atOnboardingPreference.atKeysFilePath!
            : null,
        passPhrase: atOnboardingPreference.passPhrase);
    var atAuthRequest = AtAuthRequest(_atSign, atKeysIo: atKeysIo)
      ..rootDomain = AtRootDomain(
          atOnboardingPreference.rootDomain, atOnboardingPreference.rootPort);
    var atAuthResponse = await atAuth!.authenticate(atAuthRequest);
    logger.finer('Auth response: $atAuthResponse');
    if (atAuthResponse.isSuccessful &&
        atOnboardingPreference.atKeysFilePath != null) {
      // The session reports the enrollment the keyfile authenticated as,
      // which is the keys' own answer rather than anything a caller asked
      // for.
      final authenticatedAs = atAuthResponse.session!.enrollmentId;
      if (enrollmentId != null && enrollmentId != authenticatedAs) {
        logger.shout('$_atSign was asked to authenticate as enrollment '
            '$enrollmentId, but its keyfile authenticates as '
            '$authenticatedAs; using $authenticatedAs');
      }
      logger.finer('Calling persist keys to local secondary');
      await _initAtClient(
          atKeysIo: atKeysIo, enrollmentId: authenticatedAs, atChops: atChops);
      // Through the session's own source rather than re-deriving one: what
      // authentication handed back is what it authenticated with.
      await _persistKeysLocalSecondary(
          await atAuthResponse.session!.atKeysIo.read(_atSign));
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
      final atLookUp = _newLookUp();
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
        _atLookUp is AtLookupMuxable &&
        (_atLookUp as AtLookupMuxable).isConnectionAvailable()) {
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
