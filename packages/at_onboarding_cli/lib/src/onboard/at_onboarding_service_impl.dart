// ignore_for_file: unnecessary_null_comparison

// The PQ activation surface is deliberately @experimental while it matures;
// this CLI ships from the same workspace and moves in step with it.
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
  // Stays `AtLookUp?`, deliberately. Narrowing it to AtLookupMuxable breaks
  // two assignments that are not this class's to change: it is assigned from
  // `RemoteSecondary.atLookUp`, which is typed AtLookUp, and from the public
  // `set atLookUp(AtLookUp?)` this class overrides - narrowing a public
  // setter's parameter is a breaking change.
  AtLookUp? _atLookUp;

  /// The five lookups this class builds, which differed only in formatting.
  ///
  /// `authenticator: null` at construction is right for all of them:
  /// [_installAuthenticator] supplies one afterwards from whichever credential
  /// the CLI actually holds, and two of these sites only ever send an
  /// unauthenticated `from:` through a proxy.
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

  /// [atKeysIo] is the key *source* the client keeps for everything the
  /// injected [atChops] cannot answer — resolving its PKAM algorithm from the
  /// key material, filing conveyed privates, sourcing per-algorithm signing
  /// keys. It does not change which AtChops authenticates: `AtClientImpl`
  /// honours the injected one and never builds its own when it has it.
  ///
  /// Null where there is no source to hand across. The enrollment path is one:
  /// it authenticates with the APKAM keypair it just had approved, and the
  /// keyfile that will hold it is written afterwards.
  Future<void> _initAtClient(AtChops atChops,
      {String? enrollmentId, AtKeysIo? atKeysIo}) async {
    AtClientManager atClientManager = AtClientManager.getInstance();
    if (atOnboardingPreference.skipSync) {
      atServiceFactory = ServiceFactoryWithNoOpSyncService();
    }
    await atClientManager.setCurrentAtSign(
        _atSign, atOnboardingPreference.namespace, atOnboardingPreference,
        atChops: atChops,
        atKeysIo: atKeysIo,
        atLookUp: atLookUp,
        serviceFactory: atServiceFactory,
        enrollmentId: enrollmentId);

    // Read before the `??=` below erases the distinction, because which of the
    // two flows this is decides whether the preference gets to say how the
    // connection authenticates.
    final serviceBuiltTheLookup = _atLookUp != null;

    // ??= to support mocking
    _atLookUp ??= atClientManager.atClient.getRemoteSecondary()?.atLookUp;

    /// The keypair the connection signs its PKAM challenge with.
    ///
    /// Resolved beside the enrollment id and the algorithm, and from the same
    /// source as whichever of them this flow trusts, because the three are one
    /// fact: an enrollment, the key it holds, and the routine that key is
    /// signed with. Taking two of them from the client and the third from the
    /// caller is what left `at_activate list` unable to run a verb on a
    /// retrofitted keyfile.
    final AtChops authenticationSigner;

    if (serviceBuiltTheLookup) {
      // Enrolment. The APKAM keypair was minted moments ago under the
      // posture's axis and the keyfile that will hold it is written later, so
      // there is no key material to resolve from and the preference is the
      // only source there is.
      _atLookUp!.enrollmentId = enrollmentId;
      _atLookUp!.signingAlgoType =
          atOnboardingPreference.authenticationKeyAlgorithm;
      authenticationSigner = atChops;
    } else {
      // Authentication. The lookup just adopted is the client's own, and the
      // client has already read the keyfile — which outranks any preference,
      // because you cannot sign ML-DSA with an RSA key. Writing the
      // preference over the top is how `at_activate otp`/`list` came to fail
      // on a PQ-native atSign: they build their client through
      // `createAtClient`, which names no posture, so the posture is `legacy`,
      // so the overwrite claimed rsa2048 for an ML-DSA enrollment and the
      // first reconnect signed the challenge with the wrong routine.
      //
      // Asserted rather than left alone: a cached client short-circuits
      // `AtClientImpl.create` without rebuilding its RemoteSecondary, so its
      // lookup carries whatever the previous caller left on it. And the id is
      // the client's rather than the argument's, because a client that
      // retrofitted during its own init came up on a different enrollment
      // from the one the keyfile named when this call started.
      //
      // ⛔ **And the signer comes from the client for the same reason**, which
      // it did not until a retrofitted keyfile made the two disagree. `atChops`
      // here is at_auth's, built for the enrollment the keyfile's flat fields
      // name; a client that retrofitted during its own init rebuilt its own to
      // the new enrollment's ML-DSA keypair. Declaring the client's algorithm
      // over the caller's keypair is a pairing at_chops refuses outright —
      // `this PKAM key is 1218 bytes, and an ML-DSA-65 secret key is 4032` —
      // and it refuses it on the first PKAM the adopted lookup performs, which
      // is the one before the verb. So authentication reports success and the
      // command fails, on every run: the retrofit is due again each time,
      // because it deliberately leaves the keyfile's own `enrollmentId` at the
      // capped legacy enrollment.
      final client = atClientManager.atClient;
      _atLookUp!.enrollmentId = client.enrollmentId ?? enrollmentId;
      _atLookUp!.signingAlgoType = AtClientImpl.signingAlgoOf(client);
      authenticationSigner = client.atChops ?? atChops;
    }
    // Neither key material nor a posture says how a challenge is *hashed*, so
    // this axis is the preference's on both paths — and asserting it is what
    // resets a cached client's lookup after a caller that ran with another
    // value, which the `list` after a passphrase-protected authentication
    // depends on.
    _atLookUp!.hashingAlgoType = atOnboardingPreference.hashingAlgoType;

    atClient ??= atClientManager.atClient;
    // The caller's, on both flows, and deliberately not [authenticationSigner]:
    // this field is what at_auth's EnrollmentApprover reads for enrollment
    // crypto, where the material that matters is the encryption keypair and the
    // APKAM symmetric key rather than the APKAM signing keypair. A retrofitted
    // client's AtChops is built from its own enrollment's authentication
    // material and carries no APKAM symmetric key, so putting it here would
    // move a second, unrelated behaviour under cover of fixing authentication.
    _atLookUp!.atChops = atChops;
    // Beside atChops, not instead of it: at_auth's EnrollmentApprover reads
    // that field for enrollment crypto, which is not authentication.
    final lookUp = _atLookUp;
    if (lookUp is AtLookupMuxable) {
      lookUp.authenticator = authenticatorFor(
        _keysIo(),
        _atSign,
        enrollmentId: lookUp.enrollmentId,
        chops: authenticationSigner,
      );
    }
  }

  /// Where this CLI's keys live, for READING them during authentication.
  ///
  /// The passphrase is not optional here. A password-protected keyfile cannot
  /// be read without it, and this source is handed to an authenticator that
  /// reads on every authentication - so omitting it fails `list`, and every
  /// other authenticated command, with "Pass Phrase is required". That is a
  /// long way from where the mistake was made, and no unit test sees it.
  AtKeysIo _keysIo() => FileAtKeysIo(
        filePath: atOnboardingPreference.atKeysFilePath != null
            ? (_) => atOnboardingPreference.atKeysFilePath!
            : null,
        passPhrase: atOnboardingPreference.passPhrase,
      );

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
    var atOnboardingRequest = AtOnboardingRequest(_atSign);
    atOnboardingRequest.rootDomain = AtRootDomain(
        atOnboardingPreference.rootDomain, atOnboardingPreference.rootPort);
    atOnboardingRequest.retryOptions =
        RetryOptions(maxRetries: maxRetries, retryDelay: retryInterval);
    // Deliberately not _keysIo(): this one omits the passphrase where the read
    // path requires it. Whether that omission is right is a separate question,
    // and not one to answer as a side effect of sharing a helper.
    final atKeysIo = FileAtKeysIo(
      filePath: atOnboardingPreference.atKeysFilePath != null
          ? (_) => atOnboardingPreference.atKeysFilePath!
          : null,
      passPhrase: atOnboardingPreference.passPhrase,
    );
    atOnboardingRequest.atKeysIo = atKeysIo;

    // A post-quantum activation is all-or-nothing, which is why it goes
    // through one call rather than a few assignments here: an ML-DSA APKAM
    // without a key package produces an atSign no sender can address until
    // that enrollment sends an `enroll:update` for itself, since
    // `metadata.keyPackage` is otherwise written only by the `enroll:request`
    // that creates the enrollment record.
    // Matched on mldsa65 exactly, not on "anything but rsa2048": ecc_secp256r1
    // is a third, classical option this package already supports, and treating
    // it as post-quantum would silently mint an ML-DSA APKAM for a caller who
    // asked for an elliptic-curve one.
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
  /// It is created while this process still holds the **first** enrollment —
  /// the one the atServer grants `__manage` — because that is what entitles it
  /// to create the root at all. It does not fail the onboard: activation has
  /// already succeeded by here, the CRAM secret is spent, and a start-time pull
  /// or a re-run mints the root later. Reporting a live atSign as unactivated
  /// would be much the worse outcome.
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
    final manager = await AtClientManager.getInstance()
        .fromAuthSession(session, atOnboardingPreference);
    atClient ??= manager.atClient;
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
      SigningAlgoType? signingAlgo,
      EnrollmentKeyExchangeMode? keyExchangeMode}) async {
    // One source for the algorithm this enrollment authenticates with. The
    // preference is what `authenticate()` stamps on the connection
    // (`_atLookUp!.signingAlgoType = atOnboardingPreference
    // .authenticationKeyAlgorithm` on the enrolment branch), so minting under
    // anything else hands at_chops a key of one algorithm and a declaration of
    // another. A caller with a position of its own still passes it.
    final algo =
        signingAlgo ?? atOnboardingPreference.authenticationKeyAlgorithm;
    if (appName == null || deviceName == null) {
      throw AtEnrollmentException(
          'appName and deviceName are mandatory for enrollment');
    }

    _atLookUp ??= _newLookUp();

    // One source for how the symmetric key travels, resolved the same way the
    // algorithm above is: the caller's word if it has one, else this service's
    // posture. `PqPosture.keyExchangeMode` is one of the axes a posture is
    // *made of*, so a request built without consulting it makes the posture a
    // partial instruction — which is what `enroll --posture pqActive` was
    // until now. It reached the preference and the authentication key and
    // stopped there, so the request went out hard-coded to legacy and the
    // enrolment got no key package, silently.
    final mode =
        keyExchangeMode ?? atOnboardingPreference.posture.keyExchangeMode;

    // The enrollment owns a data signing key from birth, under the algorithm
    // the in-use set names — so `_apsk` advertises a key this enrollment holds
    // rather than its APKAM authentication key, and the first start's
    // reconciliation finds nothing missing and republishes nothing. Without
    // it the record names the authentication key, the key package is signed
    // by that key, and the first mint drops it: the package stops verifying
    // and any link an approver conveyed against that value stops matching.
    final advertisedSigningKey = await mintAdvertisedSigningKey(
        atOnboardingPreference.dataSigningKeyAlgorithms);

    // The constructor IS the decision, which is why this is a branch and not a
    // parameter. A pq request needs both callbacks and carries no wrapped key;
    // a legacy request carries the wrapped key and needs neither. Making the
    // mode settable independently of the callbacks would create requests
    // at_auth has to refuse at runtime, so `AtEnrollmentRequest` does not
    // expose it and this chooses between the two shapes instead.
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
          // `algo`, not a constant: the builder signs the key package with the
          // APKAM keypair this request is about to mint, so it has to be told
          // which algorithm that is. Passing anything else signs the package
          // with a key the record does not name, and every peer that resolves
          // `_apsk` to verify it before sealing a secret verifies against
          // nothing — the enrollment is created and then receives no conveyed
          // material at all.
          metadataBuilder: enrollmentKeyPackageBuilder(_atSign,
              signingAlgo: algo,
              // The same keypair the request advertises. A package signed by
              // anything else is verified against a record that does not name
              // its signer, so a peer resolves `_apsk`, fails, and seals
              // nothing to the enrollment.
              advertisedSigningKey: advertisedSigningKey,
              // The primary of the configured list. An enrollment is created
              // holding one encapsulation key; the rest of the list is minted
              // at the client's first startup.
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
          // Advertised here too, and deliberately without a key package: the
          // key-exchange mode decides whether a package exists at all, while
          // `_apsk` is what every peer verifies signatures against whatever
          // the mode. A legacy-mode enrolment under a posture that names a
          // signing algorithm still owns its signing key.
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
    _atLookUp ??= _newLookUp();

    if (_isUsingProxy) {
      // When using a proxy, send from: command to ensure correct atSign context
      await _sendFromCommandIfUsingProxy(_atLookUp!, context: 'awaitApproval');
    }

    // Later steps re-authenticate on this connection (a reconnect PKAMs
    // again), so the lookup must know which enrollment it authenticates as;
    // the delegate passes the id per call and never stamps it.
    _atLookUp!.enrollmentId = enrollmentResponse.enrollmentId;

    // The enrollment checkpoint deliberately strips the atSign from the
    // persisted response (the file must not reveal whose it is), and the
    // delegate validates and addresses by both fields — so a resumed
    // response gets them restored from what this service already knows.
    // ignore: deprecated_member_use
    enrollmentResponse.atSign ??= _atSign;
    // ignore: deprecated_member_use
    enrollmentResponse.rootDomain ??= AtRootDomain(
        atOnboardingPreference.rootDomain, atOnboardingPreference.rootPort);

    _atEnrollment ??= AtEnrollment.create();
    // The whole approval handshake — PKAM-until-approved, then fetching and
    // decrypting the encryption private key and self-encryption key — is
    // at_auth's canonical implementation; this class used to carry a copy of
    // it. Its progress events are forwarded for the duration so this
    // service's subscribers see the same stream the copy used to emit.
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
  /// The keyfile is written by [FileAtKeysIo] — the same store [authenticate]
  /// reads it back through. This class used to assemble the document itself,
  /// which made it a second writer of a format at_auth owns: it self-encrypted
  /// the four legacy fields by hand (byte-identically, as it happens), rolled
  /// its own passphrase envelope, and could file no typed key material at all.
  /// It also dereferenced the flat APKAM and self-encryption fields
  /// unconditionally, which holds only while every enrollment mints an RSA
  /// APKAM and every atSign has legacy material — the same assumption that
  /// broke `_persistKeysLocalSecondary` on a PQ-native keyfile.
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
      // `write` is create-only by contract and `flush` is never-lose, so
      // neither of them means "replace" — which is exactly what allowOverwrite
      // asks for. The old file goes first, at the caller's request, rather
      // than by weakening a store verb.
      await atKeysFile.delete();
    }

    logger.finer('Generating keys file at ${atKeysFile.path}'
        ' with enrollmentId $enrollmentId');

    if (enrollmentId != null) {
      atAuthKeys.enrollmentId = enrollmentId;
    }
    // Every .atKeys file in existence carries the self-encryption key a second
    // time under the atSign itself. Nothing in this repo reads it, and a
    // freshly built AtKeys has no metadata to emit it from, so it is put there
    // deliberately — a reader that has always found it must keep finding it.
    final selfEncryptionKey = atAuthKeys.defaultSelfEncryptionKey;
    if (selfEncryptionKey != null) {
      atAuthKeys.metadata[_atSign] = selfEncryptionKey.toString();
    }
    if (atOnboardingPreference.authMode != PkamAuthMode.keysFile) {
      // In a SIM or another secure element the private half cannot be read
      // and has never been in this file.
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
  /// Every field here is **optional**, and each absence is a legitimate shape
  /// rather than a fault:
  ///
  /// - a PQ-native enrollment files its APKAM as typed material under the
  ///   enrollment id and leaves the flat `apkamPublicKey`/`apkamPrivateKey`
  ///   empty, by design — authentication resolves the algorithm and the key
  ///   from the keyfile, so nothing reads these back for such an enrollment;
  /// - an atSign activated with `mintLegacyMaterial: false` has no RSA
  ///   encryption keypair and no self-encryption key at all.
  ///
  /// Dereferencing them unconditionally is what made a PQ-native keyfile fail
  /// here with `Null check operator used on a null value` — after a successful
  /// authentication, from a back-up step, which is about as far from the cause
  /// as an error can land.
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
  Future<bool> authenticate({String? enrollmentId}) async {
    atAuth ??= AtAuth.create();
    // Held in a local so the client gets the same source auth read from,
    // rather than a second store built over the same path.
    final atKeysIo = FileAtKeysIo(
        filePath: !atOnboardingPreference.atKeysFilePath.isNull
            ? (_) => atOnboardingPreference.atKeysFilePath!
            : null,
        passPhrase: atOnboardingPreference.passPhrase);
    var atAuthRequest = AtAuthRequest(_atSign, atKeysIo: atKeysIo)
      ..enrollmentId = enrollmentId
      ..rootDomain = AtRootDomain(
          atOnboardingPreference.rootDomain, atOnboardingPreference.rootPort);
    var atAuthResponse = await atAuth!.authenticate(atAuthRequest);
    logger.finer('Auth response: $atAuthResponse');
    if (atAuthResponse.isSuccessful &&
        atOnboardingPreference.atKeysFilePath != null) {
      logger.finer('Calling persist keys to local secondary');
      await _initAtClient(atAuth!.atChops!,
          enrollmentId: atAuthResponse.atAuthKeys!.enrollmentId,
          atKeysIo: atKeysIo);
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
