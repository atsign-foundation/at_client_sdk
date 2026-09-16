import 'dart:async';

import 'package:at_auth/src/at_auth.dart';
import 'package:at_auth/src/auth/models/at_auth_requests.dart';
import 'package:at_auth/src/auth/models/at_auth_responses.dart';
import 'package:at_auth/src/auth/models/at_auth_session.dart';
import 'package:at_auth/src/auth/at_authenticator.dart';
import 'package:at_auth/src/auth/cram_authenticator.dart';
import 'package:at_auth/src/auth/onboarding_mint.dart';
import 'package:at_auth/src/auth/pkam_authenticator.dart';
import 'package:at_auth/src/enroll/models/at_enrollment_request.dart';
import 'package:at_auth/src/enroll/at_enrollment.dart';
import 'package:at_auth/src/enroll/models/at_enrollment_response.dart';
import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/serialization/atkey_material.dart';
import 'package:at_auth/src/keys/io/at_keys_io.dart';
import 'package:at_auth/src/keys/io/memory_io.dart';
import 'package:at_chops/at_chops.dart';
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

  /// The signer a caller injected through [AtAuth.create], else the one
  /// [authenticate] and [onboard] build from the keys they resolved.
  // ignore: deprecated_member_use
  AtChops? _chops;

  CramAuthenticator? cramAuthenticator;

  PkamAuthenticator? pkamAuthenticator;

  AtEnrollment atEnrollment;

  @override
  final AtLookupMuxable atLookUp;

  AtAuthImpl(
      {required this.atLookUp,
      // ignore: deprecated_member_use
      AtChops? atChops,
      this.cramAuthenticator,
      this.pkamAuthenticator,
      AtEnrollment? atEnrollment})
      : _chops = atChops,
        atEnrollment = atEnrollment ?? AtEnrollment.create();

  /// The keystore the authenticator should read, matching the precedence
  /// [authenticate] itself uses.
  ///
  /// An explicitly supplied `atAuthKeys` wins over an `atKeysIo` - that is what
  /// this class does two lines into [authenticate], and the authenticator must
  /// read the same thing the rest of the method used rather than re-resolve
  /// and possibly differ. A fixed key set is wrapped in an in-memory store: a
  /// keystore that never changes, which is exactly right for a caller that
  /// handed over frozen keys. Only when the request supplied a source and no
  /// keys does the authenticator get the source itself, and with it the
  /// re-reading that lets one closure answer CRAM then PKAM.
  Future<AtKeysIo> _keysSourceFor(String atSign, AtKeys resolved,
      {AtKeysIo? reReadable}) async {
    if (reReadable != null) {
      return reReadable;
    }
    final memory = InMemoryAtKeysIo();
    await memory.write(atSign, resolved);
    return memory;
  }

  @override

  /// Authenticate using PKAM
  /// The AtAuthRequest must contain either:
  /// - 1. atAuthRequest.atKeysIo - An implementation of AtKeysIo to read the keys
  /// - 2. atAuthRequest.atAuthKeys - An instance of AtKeys containing the keys
  ///
  /// If both are provided, atAuthRequest.atAuthKeys will be used.
  ///
  /// The enrollment authenticated as is the keys' own answer,
  /// [AtKeys.enrollmentToAuthenticateAs], never a caller-supplied id.
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

    final enrollmentId = atAuthKeys.enrollmentToAuthenticateAs();
    // A typed-material enrollment (a self-retrofit's) authenticates with its
    // own signing keypair and algorithm, resolved from the keyfile rather
    // than caller-supplied; the flat fields keep carrying the original
    // enrollment's RSA credentials. AtKeys owns that resolution — it is the
    // only reader of either source. ??= to support mocking.
    final algorithm = atAuthKeys.authenticationAlgorithmFor(enrollmentId);
    if (algorithm != null) {
      atLookUp.signingAlgoType = algorithm;
    }
    atChops ??= atAuthKeys.authenticationFor(enrollmentId).chops;
    atLookUp.atChops = atChops;
    // Installed alongside atChops, not instead of it. at_lookup prefers the
    // authenticator, so this is the route that runs - but the field is still
    // read for work that is not authentication at all (enrollment_approver
    // takes the encryption private key out of it), so it cannot go yet.
    atLookUp.authenticator = authenticatorFor(
      await _keysSourceFor(atAuthRequest.atSign, atAuthKeys,
          // Only when the request supplied a source and no keys of its
          // own. An explicit AtKeys wins here exactly as it wins above,
          // so the authenticator reads what this method read.
          reReadable: atAuthRequest.atAuthKeys == null
              ? atAuthRequest.atKeysIo
              : null),
      atAuthRequest.atSign,
      enrollmentId: enrollmentId,
      chops: atChops,
    );

    _logger.finer('Authenticating using PKAM');
    pkamAuthenticator ??= PkamAuthenticator();
    var pkamResponse = AtAuthResponse(atAuthRequest.atSign);
    try {
      pkamResponse
        ..isSuccessful = (await pkamAuthenticator!.authenticate(
            atAuthRequest.atSign, atLookUp,
            enrollmentId: enrollmentId))
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
          enrollmentId: enrollmentId,
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

    //If the user is providing atKeysIo, they might be onboarding again or with a specific key implementation.
    AtKeys? existingKeys;
    try {
      existingKeys = await atOnboardingRequest.atKeysIo?.read(
        atOnboardingRequest.atSign,
      );
    } catch (e) {
      _logger.info(
        'Failed to read keys for atSign: ${atOnboardingRequest.atSign} | Cause: $e',
      ); //swallow the error, we just want to know if keys exist or not
    }

    if (existingKeys != null) {
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
      atLookUp,
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
    //2. generate key pairs. Onboarding mints key material and must persist
    // it, so a writable store is required. There is no default: the core
    // cannot assume a filesystem.
    if (atOnboardingRequest.atKeysIo == null) {
      throw AtAuthenticationException(
          'onboarding needs somewhere to persist the key material it mints: '
          'set AtOnboardingRequest.atKeysIo. On a platform with a '
          'filesystem that is usually FileAtKeysIo() from '
          'package:at_auth/at_auth_io.dart');
    }
    if (atOnboardingRequest.atKeysIo is! WrittenAtKeysIo) {
      throw AtAuthenticationException(
          'onboarding mints key material and must write it, but the AtKeysIo '
          'supplied for ${atOnboardingRequest.atSign} is read-only: set '
          'AtOnboardingRequest.atKeysIo to a WrittenAtKeysIo');
    }
    final OnboardingMint mint = await mintOnboardingKeys(
        signingAlgo: atOnboardingRequest.signingAlgoType,
        // Null resolves to the release default, not to false: legacy
        // material is retained until the ecosystem is PQ, not until this
        // atSign is.
        mintLegacyMaterial: atOnboardingRequest.mintLegacyMaterial ?? true);
    _atAuthKeys = mint.keys;

    // A PQ-native activation authenticates with the keypair just minted, which
    // is not in the flat fields `authenticationFor` reads for an enrollment
    // naming no algorithm — and the enrollment it will be filed under does
    // not exist yet, so there is nothing to resolve. Build the chops from the
    // minted halves
    // directly, and name the algorithm: at_lookup defaults to rsa2048 and
    // would otherwise sign an ML-DSA key with the RSA routine.
    if (atOnboardingRequest.signingAlgoType != SigningAlgoType.rsa2048) {
      // ignore: deprecated_member_use
      _chops ??= AtChopsImpl(AtChopsKeys.create(
          null,
          // ignore: deprecated_member_use
          AtPkamKeyPair.create(mint.apkamPublicKey, mint.apkamPrivateKey))
        ..selfEncryptionKey = _atAuthKeys.defaultSelfEncryptionKey == null
            ? null
            : AESKey(_atAuthKeys.defaultSelfEncryptionKey!.toString()));
    } else {
      _chops ??= _atAuthKeys.authenticationFor(null).chops;
    }
    // The algorithm is named rather than derived here. A PQ-native activation
    // signs with the keypair minted a few lines above, which is in no keyfile,
    // under an enrollment the atServer has not created yet - so there is
    // nothing for the keystore to resolve, and the rsa2048 default would sign
    // an ML-DSA key with the RSA routine.
    atLookUp.authenticator = authenticatorFor(
      await _keysSourceFor(atOnboardingRequest.atSign, _atAuthKeys),
      atOnboardingRequest.atSign,
      chops: _chops,
      signingAlgo: atOnboardingRequest.signingAlgoType,
    );

    //3. send onboarding enrollment
    String? enrollmentIdFromServer;
    // server will update the apkam public key during enrollment.
    // So don't have to manually update apkam public key in this scenario.
    enrollmentIdFromServer = await _sendOnboardingEnrollment(
      atOnboardingRequest,
      _atAuthKeys,
      atLookUp,
      mint,
    );
    _atAuthKeys.enrollmentId = enrollmentIdFromServer;

    // Reinstall, now that the atServer has named the enrollment. The
    // authenticator installed above closed over a null id because none
    // existed yet, and `enrollmentId` is captured at install time rather than
    // read per call - so without this the activation PKAM below goes out with
    // no `enrollmentId:` segment however the id is passed to
    // `pkamAuthenticate`. The atServer then authenticates that connection as
    // `pkamLegacy` against the default PKAM public key, while at_lookup
    // records it as authenticated for this enrollment: the two ends disagree
    // about who is on the connection, and the enrollment-record-authoritative
    // signing-algorithm check never runs.
    atLookUp.authenticator = authenticatorFor(
      await _keysSourceFor(atOnboardingRequest.atSign, _atAuthKeys),
      atOnboardingRequest.atSign,
      enrollmentId: enrollmentIdFromServer,
      chops: _chops,
      signingAlgo: atOnboardingRequest.signingAlgoType,
    );

    //4. Close connection to server
    try {
      await atLookUp.close();
    } on Exception catch (e) {
      _logger.severe('error while closing connection to server: $e');
    }

    //6. Do pkam auth
    pkamAuthenticator ??= PkamAuthenticator();
    try {
      var pkamResponse = await pkamAuthenticator!.authenticate(
          atOnboardingRequest.atSign, atLookUp,
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

    atOnboardingResponse.isSuccessful = true;

    // The session a freshly activated atSign's client opens from. atKeysIo
    // is non-null here: onboarding refuses without one above.
    if (atOnboardingRequest.atKeysIo != null) {
      atOnboardingResponse.session = AtAuthSession(
        atSign: atOnboardingRequest.atSign,
        rootDomain: atOnboardingRequest.rootDomain,
        namespace: atOnboardingRequest.namespace,
        atKeysIo: atOnboardingRequest.atKeysIo!,
        enrollmentId: enrollmentIdFromServer,
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
          await atLookUp.executeVerb(updateBuilder);
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
    String? deleteResponse = await atLookUp.executeVerb(deleteBuilder);
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
        advertisedSigningKey: atOnboardingRequest.advertisedSigningKey,
        metadataBuilder: atOnboardingRequest.metadataBuilder,
        atKeys: constructionKeys);

    AtEnrollmentResponse? atEnrollmentResponse;
    try {
      atEnrollmentResponse =
          await atEnrollment.submit(firstEnrollmentRequest, atLookUp);
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
    // Filed whether or not there were construction keys: the signing key is
    // the caller's, not something the builder minted, and an enrollment whose
    // `_apsk` names a key its keyfile does not hold signs with something else
    // entirely.
    final advertisedSigningKey = atOnboardingRequest.advertisedSigningKey;
    if (advertisedSigningKey != null) {
      atAuthKeys.fileSigningMaterial(
          enrollmentId: enrollmentIdFromServer,
          algorithm: CryptographicMaterialAlgorithm.of(
              advertisedSigningKey.algorithm.name),
          publicKey: advertisedSigningKey.publicKey,
          privateKey: advertisedSigningKey.privateKey);
    }
    return enrollmentIdFromServer;
  }

  /// Files the first enrollment's key material under the id the atServer just
  /// assigned.
  ///
  /// A PQ-native activation's APKAM goes in as typed material — the flat
  /// fields stay empty, so `AtAuthImpl.authenticate` resolves this enrollment
  /// through `signingAlgorithmForEnrollment` / `authenticationFor` and
  /// signs ML-DSA with no caller-supplied algorithm anywhere. An `rsa2048`
  /// activation already wrote its APKAM to the flat fields and adds nothing
  /// here, which is what keeps a legacy keyfile byte-identical.
  ///
  /// Whatever the metadataBuilder minted — the key package's two halves —
  /// is re-tagged with the enrollment id either way. It is the only copy of
  /// that private half in existence.
  void _fileFirstEnrollmentMaterial(AtKeys atAuthKeys, AtKeys constructionKeys,
      OnboardingMint mint, SigningAlgoType signingAlgo, String enrollmentId) {
    if (signingAlgo != SigningAlgoType.rsa2048) {
      atAuthKeys.fileApkamMaterial(
          enrollmentId: enrollmentId,
          algorithm: CryptographicMaterialAlgorithm.of(signingAlgo.name),
          publicKey: mint.apkamPublicKey,
          privateKey: mint.apkamPrivateKey);
    }
    atAuthKeys.adoptMaterials(constructionKeys.keys,
        enrollmentId: enrollmentId);
  }

  /// Waits, over [atLookUp], until the atDirectory knows the atSign and its
  /// atServer answers.
  ///
  /// Retried until the request's overall deadline, then throws an
  /// [AtTimeoutException] carrying the last failure.
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

    while (DateTime.now().isBefore(deadline)) {
      attempt++;
      try {
        _addProgress(
            'Find',
            '#[$attempt] : looking up ${atRequest.atSign} in atDirectory',
            ProgressEventType.info);

        final check = await checkAtSignServer(atLookUp, atRequest.atSign,
            timeout: AtNetworkTimeouts.cap(deadline.difference(DateTime.now())));
        switch (check.state) {
          case AtSignServerState.notInDirectory:
            throw AtException('atSign: ${atRequest.atSign} is not in the '
                'atDirectory at ${atRequest.rootDomain.rootDomain}');
          case AtSignServerState.directoryUnreachable:
            throw AtException('Could not reach the atDirectory at '
                '${atRequest.rootDomain.rootDomain}: ${check.cause}');
          case AtSignServerState.atServerUnreachable:
            throw _AtServerNotAnswering(check.cause);
          // NOTE: a public key does not prove the CRAM secret is spent, so an
          // atSign that looks activated is not refused onboarding here; the
          // CRAM exchange refuses one that really is.
          case AtSignServerState.activated:
          case AtSignServerState.notActivated:
        }

        _addProgress(
            'Connect',
            '#[$attempt] : Connected to ${atRequest.atSign} atServer',
            ProgressEventType.success);

        validated = true;
        break; // Exit loop if no exception occurs
      } catch (e) {
        lastError = e is _AtServerNotAnswering ? e.cause : e;
        if (e is _AtServerNotAnswering) {
          // Expected while an atServer is still starting, so it is not an
          // error until the retries run out.
          _logger.warning(
              'Attempt #[$attempt] atServer not answering: ${e.cause}');
        } else {
          _logger.severe('Attempt #[$attempt] failed: $lastError');
        }
        _addProgress(
            'Connect', '#[$attempt] : $lastError', ProgressEventType.error);
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

/// An atServer that did not answer, so the retry loop can tell one that is
/// not up yet - expected while one starts - from any other failure.
class _AtServerNotAnswering implements Exception {
  _AtServerNotAnswering(this.cause);
  final Object? cause;
  @override
  String toString() => '$cause';
}
