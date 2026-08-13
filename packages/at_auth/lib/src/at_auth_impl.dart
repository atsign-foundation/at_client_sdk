import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:at_auth/src/at_auth.dart';
import 'package:at_auth/src/auth/models/at_auth_requests.dart';
import 'package:at_auth/src/auth/models/at_auth_responses.dart';
import 'package:at_auth/src/auth/models/at_auth_session.dart';
import 'package:at_auth/src/auth/cram_authenticator.dart';
import 'package:at_auth/src/auth/onboarding_mint.dart';
import 'package:at_auth/src/auth/pkam_authenticator.dart';
import 'package:at_auth/src/enroll/models/at_enrollment_request.dart';
import 'package:at_auth/src/enroll/at_enrollment.dart';
import 'package:at_auth/src/enroll/models/at_enrollment_response.dart';
import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/io/at_keys_io.dart';
import 'package:at_auth/src/keys/io/file_io.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_server_status/at_server_status.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_utils/at_progress.dart';

class AtAuthImpl implements AtAuth {
  final AtSignLogger _logger = AtSignLogger('AtAuthServiceImpl');
  final StreamController<ProgressEvent> _progressController =
      StreamController<ProgressEvent>.broadcast();

  ///Progress stream to listen to onboarding/authentication progress.
  @override
  Stream<ProgressEvent> get progressStream => _progressController.stream;
  void _addProgress(String group, String message, ProgressEventType type) {
    var progressEvent = ProgressEvent(group: group, msg: message, type: type);
    _progressController.add(progressEvent);
  }

  @override
  AtChops? atChops;

  CramAuthenticator? cramAuthenticator;

  PkamAuthenticator? pkamAuthenticator;

  AtEnrollment atEnrollment;

  @visibleForTesting
  AtServerStatus? atServerStatus;

  @visibleForTesting
  SecondaryAddressFinder? secondaryAddressFinder;

  @visibleForTesting
  Future<void> Function(String host, int port)? probeSocket;

  @override
  AtLookUp? atLookUp;

  AtAuthImpl(
      {this.atLookUp,
      this.atChops,
      this.cramAuthenticator,
      this.pkamAuthenticator,
      this.atServerStatus,
      AtEnrollment? atEnrollment})
      : atEnrollment = atEnrollment ?? AtEnrollment.create();

  @override

  /// Authenticate using PKAM
  /// The AtAuthRequest must contain either:
  /// - 1. atAuthRequest.atKeysIo - An implementation of AtKeysIo to read the keys
  /// - 2. atAuthRequest.atAuthKeys - An instance of AtKeys containing the keys
  ///
  /// If both are provided, atAuthRequest.atAuthKeys will be used.
  ///
  /// The AtAuthRequest may optionally contain:
  /// - atAuthRequest.enrollmentId - The enrollmentId to use for authentication.
  ///   If not provided, the enrollmentId in the AtAuthKeys will be used.
  /// - atAuthRequest.encryptedKeysMap - Provide the contents of atKeys file which
  ///    contains keys in encrypted format (LEGACY)
  ///
  /// returns an `AtAuthResponse` indicating success or failure of authentication
  Future<AtAuthResponse> authenticate(AtAuthRequest atAuthRequest) async {
    AtKeys? atAuthKeys = atAuthRequest.atAuthKeys;
    await validateAtServer(atAuthRequest);
    try {
      atAuthKeys ??= await atAuthRequest.atKeysIo!.read(atAuthRequest.atSign);
    } on AtKeyException catch (e) {
      _addProgress(
        "authentication",
        "Unable to read keys for atSign: ${atAuthRequest.atSign}",
        ProgressEventType.error,
      );
      throw AtAuthenticationException(
        'Unable to read keys for atSign: ${atAuthRequest.atSign} | Cause: ${e.message}',
      );
    }

    atAuthRequest.enrollmentId ??= atAuthKeys.enrollmentId;
    atLookUp ??= AtLookupImpl(
      atAuthRequest.atSign,
      atAuthRequest.rootDomain.rootDomain,
      atAuthRequest.rootDomain.rootPort,
    );
    // A typed-material enrollment (a self-retrofit's) authenticates with its
    // own signing keypair and algorithm, resolved from the keyfile rather
    // than caller-supplied; the flat fields keep carrying the original
    // enrollment's RSA credentials. AtKeys owns that resolution — it is the
    // only reader of either source. ??= to support mocking.
    final algorithm =
        atAuthKeys.authenticationAlgorithmFor(atAuthRequest.enrollmentId);
    if (algorithm != null) {
      atLookUp!.signingAlgoType = algorithm;
    }
    atChops ??= atAuthKeys.authenticationFor(atAuthRequest.enrollmentId).chops;
    atLookUp!.atChops = atChops;

    _logger.finer('Authenticating using PKAM');
    pkamAuthenticator ??= PkamAuthenticator();
    var pkamResponse = AtAuthResponse(atAuthRequest.atSign);
    try {
      pkamResponse
        ..isSuccessful = (await pkamAuthenticator!.authenticate(
            atAuthRequest.atSign, atLookUp!,
            enrollmentId: atAuthRequest.enrollmentId))
        ..atAuthKeys = atAuthKeys
        ..atLookUp = atLookUp
        ..atChops = atChops;

      // Build the explicit hand-off session from the request's confirmed
      // subset — only when the request supplied an AtKeysIo source. The legacy
      // atAuthKeys-only path has no source to hand across, so it gets no
      // session.
      if (pkamResponse.isSuccessful && atAuthRequest.atKeysIo != null) {
        pkamResponse.session = AtAuthSession(
          atSign: atAuthRequest.atSign,
          rootDomain: atAuthRequest.rootDomain,
          namespace: atAuthRequest.namespace,
          atKeysIo: atAuthRequest.atKeysIo!,
          enrollmentId: atAuthRequest.enrollmentId,
          atLookUp: atLookUp,
        );
      }

      if (!pkamResponse.isSuccessful) {
        _addProgress(
          "authentication",
          "PKAM authentication failed for atSign: ${atAuthRequest.atSign}",
          ProgressEventType.error,
        );
      } else {
        _addProgress(
          "authentication",
          "PKAM authentication successful for atSign: ${atAuthRequest.atSign}",
          ProgressEventType.success,
        );
      }
    } catch (e, s) {
      _addProgress(
        "authentication",
        "PKAM authentication failed for atSign: ${atAuthRequest.atSign}",
        ProgressEventType.error,
      );
      throw AtAuthenticationException(
          'Unable to authenticate | Cause: $e \n $s');
    }

    return pkamResponse;
  }

  /// Keep some state so callers can call [completeActivation] later
  late AtKeys _atAuthKeys;
  late AtOnboardingRequest _atOnboardingRequest;

  /// Onboard a new atSign using CRAM
  /// Requires an AtOnboardingRequest and a cramSecret
  ///
  /// returns an `AtOnboardingResponse` indicating success or failure of onboarding
  @override
  Future<AtOnboardingResponse> onboard(
    AtOnboardingRequest atOnboardingRequest,
    String cramSecret, {
    bool autoCompleteActivation = true,
    String? publicKeyId,
  }) async {
    var atOnboardingResponse = AtOnboardingResponse(atOnboardingRequest.atSign);
    atLookUp ??= AtLookupImpl(
      atOnboardingRequest.atSign,
      atOnboardingRequest.rootDomain.rootDomain,
      atOnboardingRequest.rootDomain.rootPort,
    );

    //If the user is providing atKeysIo, they might be onboarding again or with a specific key implementation.
    try {
      atOnboardingRequest.atKeys = await atOnboardingRequest.atKeysIo?.read(
        atOnboardingRequest.atSign,
      );
    } catch (e) {
      _logger.info(
        'Failed to read keys for atSign: ${atOnboardingRequest.atSign} | Cause: $e',
      ); //swallow the error, we just want to know if keys exist or not
    }

    if (atOnboardingRequest.atKeys != null) {
      throw AtAuthenticationException(
        'atSign: ${atOnboardingRequest.atSign} is already onboarded. Cannot perform onboarding again.',
      );
    }

    await validateAtServer(atOnboardingRequest);
    //1. cram auth
    cramAuthenticator ??= CramAuthenticator();
    var cramAuthResult = await cramAuthenticator!.authenticate(
      atOnboardingRequest.atSign,
      cramSecret,
      atLookUp!,
    );
    if (!cramAuthResult) {
      _addProgress(
        "onboarding",
        "CRAM authentication failed for atSign: ${atOnboardingRequest.atSign}",
        ProgressEventType.error,
      );
      throw AtAuthenticationException(
        'Cram authentication failed. Please check the cram key'
        ' and try again (or) contact support@atsign.com',
      );
    }
    //2. generate key pairs
    OnboardingMint? mint;
    if (atOnboardingRequest.atKeys != null) {
      _atAuthKeys = atOnboardingRequest.atKeys!;
    } else {
      //2a. if there is no specified implementation we're defaulting to FileAtKeysIo with a default file path
      atOnboardingRequest.atKeysIo ??= FileAtKeysIo();
      if (atOnboardingRequest.atKeysIo is! WrittenAtKeysIo) {
        throw AtAuthenticationException(
            'AtKeysIo implementation does not support key pair generation, please provide AtKeys in AtOnboardingRequest');
      }
      mint = await mintOnboardingKeys(
          signingAlgo: atOnboardingRequest.signingAlgoType,
          // Null resolves to the release default, not to false: legacy
          // material is retained until the ecosystem is PQ, not until this
          // atSign is.
          mintLegacyMaterial: atOnboardingRequest.mintLegacyMaterial ?? true);
      _atAuthKeys = mint.keys;
    }

    // A PQ-native activation authenticates with the keypair just minted, which
    // is not in the flat fields toAtChops() reads — and the enrollment it will
    // be filed under does not exist yet, so toAtChopsForEnrollment() has
    // nothing to resolve either. Build the chops from the minted halves
    // directly, and name the algorithm: at_lookup defaults to rsa2048 and
    // would otherwise sign an ML-DSA key with the RSA routine.
    if (mint != null &&
        atOnboardingRequest.signingAlgoType != SigningAlgoType.rsa2048) {
      atChops ??= AtChopsImpl(AtChopsKeys.create(
          null, AtPkamKeyPair.create(mint.apkamPublicKey, mint.apkamPrivateKey))
        ..selfEncryptionKey = _atAuthKeys.defaultSelfEncryptionKey == null
            ? null
            : AESKey(_atAuthKeys.defaultSelfEncryptionKey!.toString()));
      atLookUp!.signingAlgoType = atOnboardingRequest.signingAlgoType;
    } else {
      atChops ??= _atAuthKeys.toAtChops();
    }
    atLookUp!.atChops = atChops;

    //3. send onboarding enrollment
    String? enrollmentIdFromServer;
    // server will update the apkam public key during enrollment.
    // So don't have to manually update apkam public key in this scenario.
    enrollmentIdFromServer = await _sendOnboardingEnrollment(
      atOnboardingRequest,
      _atAuthKeys,
      atLookUp!,
      mint,
    );
    _atAuthKeys.enrollmentId = enrollmentIdFromServer;

    //4. Close connection to server
    try {
      await (atLookUp as AtLookupImpl).close();
    } on Exception catch (e) {
      _logger.severe('error while closing connection to server: $e');
    }

    //6. Do pkam auth
    pkamAuthenticator ??= PkamAuthenticator();
    try {
      var pkamResponse = await pkamAuthenticator!.authenticate(
          atOnboardingRequest.atSign, atLookUp!,
          enrollmentId: enrollmentIdFromServer);
      if (!pkamResponse) {
        _addProgress(
            "onboarding",
            "PKAM authentication failed for atSign: ${atOnboardingRequest.atSign}",
            ProgressEventType.error);
        throw AtAuthenticationException('Pkam auth returned false');
      }
    } on UnAuthenticatedException catch (e) {
      _addProgress(
          "onboarding",
          "PKAM authentication failed for atSign: ${atOnboardingRequest.atSign}",
          ProgressEventType.error);
      throw AtAuthenticationException('Pkam auth failed - $e ');
    }

    //6b. Store the keys
    if (atOnboardingRequest.atKeysIo is WrittenAtKeysIo) {
      try {
        await (atOnboardingRequest.atKeysIo as WrittenAtKeysIo).write(
          atOnboardingRequest.atSign,
          _atAuthKeys,
        );
        _logger.info(
          'Successfully stored keys for atSign: ${atOnboardingRequest.atSign}',
        );
      } on AtKeyException catch (e) {
        _addProgress(
          "onboarding",
          "Unable to store keys for atSign: ${atOnboardingRequest.atSign}",
          ProgressEventType.error,
        );
        throw AtAuthenticationException(
          'Unable to store keys for atSign: ${atOnboardingRequest.atSign} | Cause: ${e.message}',
        );
      } catch (e) {
        _addProgress(
          "onboarding",
          e.toString(),
          ProgressEventType.error,
        );
        throw AtAuthenticationException(
          'Unable to write keys for atSign: ${atOnboardingRequest.atSign} | Cause: $e',
        );
      }
    }

    //7. If so specified (default behaviour) then
    // - set the public encryption key
    // - delete the cram secret from the keystore
    _atOnboardingRequest = atOnboardingRequest;
    if (autoCompleteActivation) {
      await completeActivation();
    }

    atOnboardingResponse
      ..isSuccessful = true
      ..atAuthKeys = _atAuthKeys
      ..atLookUp = atLookUp
      ..atChops = atChops;

    // Hand back the same explicit session as authenticate(), so a
    // freshly-onboarded atSign flows straight into the client. atKeysIo is
    // guaranteed set here (defaulted to FileAtKeysIo above); the guard mirrors
    // authenticate() for parity.
    if (atOnboardingRequest.atKeysIo != null) {
      atOnboardingResponse.session = AtAuthSession(
        atSign: atOnboardingRequest.atSign,
        rootDomain: atOnboardingRequest.rootDomain,
        namespace: atOnboardingRequest.namespace,
        atKeysIo: atOnboardingRequest.atKeysIo!,
        enrollmentId: enrollmentIdFromServer,
        atLookUp: atLookUp,
      );
    }

    _addProgress(
        "onboarding",
        "Onboarding successful for atSign: ${atOnboardingRequest.atSign}",
        ProgressEventType.success);
    return atOnboardingResponse;
  }

  @override
  Future<void> completeActivation() async {
    final encryptionPublicKey = _atAuthKeys.defaultEncryptionPublicKey;
    // Absent only when the caller opted out of legacy material. Publishing
    // "null" would be worse than publishing nothing: a legacy peer would find
    // a key, encrypt to it, and produce ciphertext nobody can ever read —
    // whereas an absent publickey tells them plainly that this atSign has no
    // legacy path.
    if (encryptionPublicKey != null) {
      UpdateVerbBuilder updateBuilder = UpdateVerbBuilder()
        ..atKey = (AtKey()
          ..key = 'publickey'
          ..sharedBy = _atOnboardingRequest.atSign
          ..metadata = (Metadata()
            ..isPublic = true
            ..ttr = -1))
        ..value = encryptionPublicKey;
      String? encryptKeyUpdateResult =
          await atLookUp!.executeVerb(updateBuilder);
      _logger
          .info('Encryption public key update result $encryptKeyUpdateResult');
    } else {
      _logger.info(
          'No encryption keypair was minted for ${_atOnboardingRequest.atSign}, '
          'so public:publickey is not published: a legacy peer cannot send to '
          'this atSign, which is what mintLegacyMaterial:false asks for');
    }

    // Unconditional: the CRAM secret is a one-shot activation credential and
    // leaving it in the keystore is a live path back into the atSign,
    // whichever material was minted.
    DeleteVerbBuilder deleteBuilder = DeleteVerbBuilder()
      ..atKey = (AtKey()..key = AtConstants.atCramSecret);
    String? deleteResponse = await atLookUp!.executeVerb(deleteBuilder);
    _logger.info('Cram secret delete response : $deleteResponse');
  }

  Future<String> _sendOnboardingEnrollment(
      AtOnboardingRequest atOnboardingRequest,
      AtKeys atAuthKeys,
      AtLookUp atLookup,
      OnboardingMint? mint) async {
    final signingAlgo = atOnboardingRequest.signingAlgoType;
    final apkamPublicKey =
        mint?.apkamPublicKey ?? atAuthKeys.apkamPublicKey!.toString();
    _logger.finer('apkamPublicKey: $apkamPublicKey');

    // The builder signs with the APKAM keypair and files what it mints back
    // into the keys it is handed. Those are construction keys, not
    // _atAuthKeys: the flat APKAM fields have to be populated for the builder
    // to read, and on a PQ-native activation they must NOT survive into the
    // keyfile. What the builder adds is re-tagged onto _atAuthKeys below,
    // once the enrollment id it belongs to exists.
    final constructionKeys = mint == null
        ? null
        : (AtKeys()
          ..apkamPublicKey = AtBytes.fromString(mint.apkamPublicKey)
          ..apkamPrivateKey = AtBytes.fromString(mint.apkamPrivateKey)
          ..defaultEncryptionPublicKey = atAuthKeys.defaultEncryptionPublicKey);

    FirstEnrollmentRequest firstEnrollmentRequest = FirstEnrollmentRequest(
        atSign: atOnboardingRequest.atSign,
        appName: atOnboardingRequest.appName,
        deviceName: atOnboardingRequest.deviceName,
        apkamPublicKey: apkamPublicKey,
        signingAlgo: signingAlgo,
        metadataBuilder: atOnboardingRequest.metadataBuilder,
        atKeys: constructionKeys);

    AtEnrollmentResponse? atEnrollmentResponse;
    try {
      atEnrollmentResponse =
          await atEnrollment.submit(firstEnrollmentRequest, atLookUp!);
    } on AtEnrollmentException catch (e) {
      throw AtAuthenticationException('Enrollment error: $e');
    }
    _logger.finer('enrollment response: ${atEnrollmentResponse.toString()}');
    var enrollmentIdFromServer = atEnrollmentResponse.enrollmentId;
    var enrollmentStatus = atEnrollmentResponse.enrollStatus;
    if (enrollmentStatus != EnrollmentStatus.approved) {
      throw AtAuthenticationException(
          'initial enrollment is not approved. Status from server: $enrollmentStatus \n with $atEnrollmentResponse');
    }

    if (constructionKeys != null) {
      _fileFirstEnrollmentMaterial(atAuthKeys, constructionKeys, mint!,
          signingAlgo, enrollmentIdFromServer);
    }
    return enrollmentIdFromServer;
  }

  /// Files the first enrollment's key material under the id the atServer just
  /// assigned.
  ///
  /// A PQ-native activation's APKAM goes in as typed material — the flat
  /// fields stay empty, so `AtAuthImpl.authenticate` resolves this enrollment
  /// through `signingAlgorithmForEnrollment` / `toAtChopsForEnrollment` and
  /// signs ML-DSA with no caller-supplied algorithm anywhere. An `rsa2048`
  /// activation already wrote its APKAM to the flat fields and adds nothing
  /// here, which is what keeps a legacy keyfile byte-identical.
  ///
  /// Whatever the metadataBuilder minted — the key package's two halves —
  /// is re-tagged with the enrollment id either way. It is the only copy of
  /// that private half in existence.
  void _fileFirstEnrollmentMaterial(
      AtKeys atAuthKeys,
      AtKeys constructionKeys,
      OnboardingMint mint,
      SigningAlgoType signingAlgo,
      String enrollmentId) {
    if (signingAlgo != SigningAlgoType.rsa2048) {
      atAuthKeys.fileApkamMaterial(
          enrollmentId: enrollmentId,
          algorithm: signingAlgo.name,
          publicKey: mint.apkamPublicKey,
          privateKey: mint.apkamPrivateKey);
    }
    atAuthKeys.adoptMaterials(constructionKeys.keys,
        enrollmentId: enrollmentId);
  }

  Future<void> _defaultProbeSocket(String host, int port) async {
    final socket =
        await SecureSocket.connect(host, port, timeout: Duration(seconds: 5));
    socket.destroy();
  }

  /// Validates the atSign server status depending on whether it's onboarding or authentication.
  ///
  /// For onboarding, it checks that the root server is found, the secondary server is running,
  /// and the atSign is not already activated.
  ///
  /// For authentication, it checks that the root server is found, the secondary server is running,
  /// and the atSign is already activated.
  ///
  /// Throws an [AtException] if any of the checks fail.
  /// Uses retry logic based on the [RetryOptions] provided in the [AuthRequest].
  /// This method is used internally before onboarding or authentication operations.
  @override
  Future<void> validateAtServer(AuthRequest atRequest) async {
    // Floor the poll interval so a zero/tiny retryDelay can't hammer the network
    // for the whole (possibly minutes-long) onboarding budget.
    final retryDelay =
        atRequest.retryOptions.retryDelay < const Duration(milliseconds: 100)
            ? const Duration(milliseconds: 100)
            : atRequest.retryOptions.retryDelay;
    // Bound the TOTAL wall-clock of this poll with a single overall deadline.
    // The two paths need opposite budgets: authentication of an EXISTING atSign
    // must fail fast on a dead network (#1923), but ONBOARDING polls for a
    // newly-registered atSign to be provisioned, which can take minutes. So the
    // default depends on the request type. This budget bounds the whole poll and
    // is deliberately NOT clamped to AtNetworkTimeouts.maxAllowed (that cap is
    // for individual network operations); the retry COUNT no longer bounds the
    // loop — the deadline does.
    final overallTimeout = atRequest.retryOptions.overallTimeout ??
        (atRequest is AtOnboardingRequest
            ? AtNetworkTimeouts.defaultOnboardingTimeout
            : AtNetworkTimeouts.effectiveDefault);
    final deadline = DateTime.now().add(overallTimeout);
    int attempt = 0;
    bool validated = false;
    Object? lastError;

    //support mocking
    atServerStatus ??= AtStatusImpl(
      rootUrl: atRequest.rootDomain.rootDomain,
      rootPort: atRequest.rootDomain.rootPort,
    );

    while (DateTime.now().isBefore(deadline)) {
      attempt++;
      try {
        _addProgress(
            'Find',
            '#[$attempt] : looking up ${atRequest.atSign} in atDirectory',
            ProgressEventType.info);

        // Bound each network call by the budget remaining before the deadline,
        // so no single call can overshoot the overall timeout.
        Duration remaining =
            AtNetworkTimeouts.cap(deadline.difference(DateTime.now()));
        var atStatus =
            await atServerStatus!.get(atRequest.atSign).timeout(remaining);

        // 3 Checks for onboarding:
        //   1. Root server should be found
        //   2. Secondary server should be running
        //   3. atSign should not be activated already
        if (atRequest is AtOnboardingRequest) {
          if (atStatus.rootStatus != RootStatus.found) {
            throw AtException(
                'Could not find root server: ${atRequest.rootDomain.rootDomain}');
          }
          if (atStatus.serverStatus == ServerStatus.error ||
              atStatus.atSignStatus == AtSignStatus.notFound) {
            throw AtException(
                'atSign: ${atRequest.atSign} secondary server is not running. '
                'Cannot perform onboarding. ${atStatus.serverStatus} ${atStatus.atSignStatus}');
          }
          if (atStatus.atSignStatus == AtSignStatus.activated) {
            throw AtException(
                'atSign: ${atRequest.atSign} is already onboarded. Cannot perform onboarding again.');
          }
        }

        // 3 Checks for authentication:
        //   1. Root server should be found
        //   2. Secondary server should be running
        //   3. atSign should be activated already
        else if (atRequest is AtAuthRequest) {
          if (atStatus.rootStatus == RootStatus.notFound ||
              atStatus.rootStatus == RootStatus.error) {
            throw AtException(
                'Could not find root server: ${atRequest.rootDomain.rootDomain}');
          }
          if (atStatus.serverStatus == ServerStatus.stopped ||
              atStatus.serverStatus == ServerStatus.error ||
              atStatus.serverStatus == ServerStatus.unavailable) {
            throw AtException(
                'atSign: ${atRequest.atSign} secondary server is not running. Cannot perform Authentication.');
          }
          if (atStatus.atSignStatus == AtSignStatus.teapot ||
              atStatus.serverStatus == ServerStatus.teapot) {
            throw AtException(
                'atSign: ${atRequest.atSign} has not been onboarded. Cannot perform Authentication.');
          }
        }

        // AtServer availability probing
        _addProgress(
            'Connect',
            '#[$attempt] : Connecting to ${atRequest.atSign} atServer',
            ProgressEventType.info);

        secondaryAddressFinder ??= CacheableSecondaryAddressFinder(
          atRequest.rootDomain.rootDomain,
          atRequest.rootDomain.rootPort,
        );
        remaining = AtNetworkTimeouts.cap(deadline.difference(DateTime.now()));
        SecondaryAddress secondaryAddress = await secondaryAddressFinder!
            .findSecondary(atRequest.atSign, timeout: remaining);

        remaining = AtNetworkTimeouts.cap(deadline.difference(DateTime.now()));
        await (probeSocket ?? _defaultProbeSocket)(
                secondaryAddress.host, secondaryAddress.port)
            .timeout(remaining);

        _addProgress(
            'Connect',
            '#[$attempt] : Connected to ${atRequest.atSign} atServer',
            ProgressEventType.success);

        validated = true;
        break; // Exit loop if no exception occurs
      } catch (e) {
        lastError = e;
        if (e is SocketException) {
          _logger.warning('Attempt #[$attempt] Probe socket failed: $e');
        } else {
          _logger.severe('Attempt #[$attempt] failed: $e');
        }
        _addProgress('Connect', '#[$attempt] : $e', ProgressEventType.error);
        // Don't sleep past the overall deadline before the next attempt.
        if (!DateTime.now().add(retryDelay).isBefore(deadline)) {
          break;
        }
        await Future.delayed(retryDelay); // Wait before retrying
      }
    }
    if (!validated) {
      // We left the loop because the overall deadline passed (success breaks out
      // above). Surface a timeout with the last error seen.
      throw AtTimeoutException(
          'Timed out after ${overallTimeout.inSeconds}s while reaching '
          '${atRequest.atSign} atServer'
          '${lastError == null ? '' : ' : $lastError'}');
    }
  }
}
