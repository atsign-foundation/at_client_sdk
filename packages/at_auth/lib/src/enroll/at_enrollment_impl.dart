import 'dart:async';
import 'dart:convert';

import 'package:at_auth/src/enroll/at_enrollment.dart';
import 'package:at_auth/src/enroll/models/at_enrollment_response.dart';
import 'package:at_auth/src/enroll/models/at_enrollment_request.dart';
import 'package:at_auth/src/enroll/models/enrollment_request_decision.dart';
import 'package:at_auth/src/enroll/models/otp.dart';
import 'package:at_auth/src/auth/models/at_auth_session.dart';
import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/io/at_keys_io.dart';
import 'package:at_auth/src/keys/io/file_io.dart';
import 'package:at_auth/src/keys/io/file_lock.dart';
import 'package:at_auth/src/keys/io/memory_io.dart';
import 'package:at_auth/src/keys/serialization/atkey_material.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_utils/at_progress.dart';

/// A concrete implementation of [AtEnrollment] for managing enrollments.
///
/// This class provides functionality to submit and manage enrollment requests.
class AtEnrollmentImpl implements AtEnrollment {
  final AtSignLogger _logger = AtSignLogger('AtEnrollmentImpl');

  AtEnrollmentImpl();

  final StreamController<ProgressEvent> _progressStreamController =
      StreamController<ProgressEvent>.broadcast();

  @override
  Stream<ProgressEvent> get progressStream => _progressStreamController.stream;
  void _addProgress(
      String group, String message, ProgressEventType progressEventType) {
    var progressEvent =
        ProgressEvent(group: group, msg: message, type: progressEventType);
    _progressStreamController.add(progressEvent);
  }

  @override
  Future<AtEnrollmentResponse> submit(
      EnrollmentRequest enrollmentRequest, AtLookUp atLookUp) async {
    AtEnrollmentResponse atEnrollmentResponse;
    switch (enrollmentRequest) {
      case FirstEnrollmentRequest _:
        atEnrollmentResponse =
            await _handleFirstEnrollmentRequest(enrollmentRequest, atLookUp);
        break;
      case AtEnrollmentRequest _:
        atEnrollmentResponse =
            await _handleAtEnrollmentRequest(enrollmentRequest, atLookUp);
      case AtSelfEnrollmentRequest _:
        atEnrollmentResponse =
            await _handleSelfEnrollmentRequest(enrollmentRequest, atLookUp);
      default:
        _addProgress('enrollment', 'Invalid Enrollment request received',
            ProgressEventType.error);
        throw InvalidRequestException('Invalid Enrollment request received');
    }
    _addProgress('enrollment', 'Enrollment request submitted',
        ProgressEventType.success);
    return atEnrollmentResponse;
  }

  /// Handles the FirstEnrollmentRequest, which is submitted when an atSign is first onboarded.
  ///
  /// The metadata is built here rather than by the caller for the same reason
  /// the other two paths build it here: a builder has to be handed the APKAM
  /// keypair it signs with, and this is the last moment before the atServer
  /// creates the record that `metadata.keyPackage` can be written to at all.
  Future<AtEnrollmentResponse> _handleFirstEnrollmentRequest(
      FirstEnrollmentRequest enrollmentRequest, AtLookUp atLookUp) async {
    if (enrollmentRequest.metadataBuilder != null &&
        enrollmentRequest.atKeys == null) {
      throw AtEnrollmentException(
          'a FirstEnrollmentRequest with a metadataBuilder must carry the '
          'atKeys being enrolled: the builder writes the material it minted '
          'back into them, and a request without them would advertise a key '
          'package whose private half nobody kept');
    }

    final Map<String, dynamic>? metadata = await _buildMetadata(
        enrollmentRequest.metadataBuilder,
        enrollmentRequest.atSign,
        enrollmentRequest.atKeys ?? AtKeys());

    EnrollVerbBuilder enrollVerbBuilder = EnrollVerbBuilder()
      ..appName = enrollmentRequest.appName
      ..deviceName = enrollmentRequest.deviceName
      ..signingAlgo = enrollmentRequest.signingAlgo.name
      ..metadata = metadata;
    enrollVerbBuilder.apkamPublicKey = enrollmentRequest.apkamPublicKey;

    String? serverResponse =
        await _executeEnrollCommand(enrollVerbBuilder, atLookUp);
    var enrollJson = jsonDecode(serverResponse);
    var enrollmentIdFromServer = enrollJson[AtConstants.enrollmentId];
    var enrollStatus = getEnrollStatusFromString(enrollJson['status']);

    return AtEnrollmentResponse(
      enrollmentIdFromServer,
      enrollStatus,
      atSign: enrollmentRequest.atSign,
      rootDomain: enrollmentRequest.rootDomain,
    );
  }

  /// Runs [AtEnrollmentRequest.metadataBuilder], if the caller supplied one,
  /// over an [AtKeysIo] holding this request's freshly generated keys.
  ///
  /// The result is attached to the request unchanged — at_auth ferries the
  /// metadata, it does not interpret it. A builder that returns null, or
  /// throws, must not cost the caller its enrollment: the metadata is opaque
  /// and additive, so a request without it is a valid request, and the
  /// alternative is failing an enrollment over an optional payload.
  Future<Map<String, dynamic>?> _buildMetadata(
      FutureOr<Map<String, dynamic>?> Function(AtKeysIo keysIo)? builder,
      String atSign,
      AtKeys keys) async {
    if (builder == null) return null;

    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, keys);
    try {
      return await builder(keysIo);
    } catch (e, st) {
      _logger.severe('metadataBuilder threw; submitting the enrollment request '
          'without metadata: $e, $st');
      return null;
    }
  }

  /// Handles the subsequent enrollment requests.
  Future<AtEnrollmentResponse> _handleAtEnrollmentRequest(
      AtEnrollmentRequest atEnrollmentRequest, AtLookUp atLookUp) async {
    // Generate required keys
    AtPkamKeyPair apkamKeyPair = AtChopsUtil.generateAtPkamKeyPair();

    //Fetch required keys from atServer
    String defaultEncryptionPublicKey = await _getDefaultEncryptionPublicKey(
      atLookUp,
      atEnrollmentRequest.atSign,
    );

    // Built before the request rather than after it, so a metadataBuilder can
    // be handed the APKAM keypair it must sign with. Only enrollmentId is
    // missing at this point, and only the atServer can supply it — it assigns
    // one in its response below.
    AtKeys atAuthKeys = AtKeys()
      ..apkamPrivateKey =
          AtBytes.fromString(apkamKeyPair.atPrivateKey.privateKey)
      ..apkamPublicKey = AtBytes.fromString(apkamKeyPair.atPublicKey.publicKey)
      ..defaultEncryptionPublicKey =
          AtBytes.fromString(defaultEncryptionPublicKey);

    final Map<String, dynamic>? metadata = await _buildMetadata(
        atEnrollmentRequest.metadataBuilder,
        atEnrollmentRequest.atSign,
        atAuthKeys);

    // A key package is advertised in every mode — it is also how an approver
    // seals this atSign's existing secrets to the new device — so its presence
    // says nothing about how the symmetric key travels. Only the declared mode
    // does.
    final bool isPq = atEnrollmentRequest.keyExchangeMode ==
        EnrollmentKeyExchangeMode.pq;

    if (isPq) {
      if (metadata?['keyPackage'] == null) {
        throw AtEnrollmentException(
            'A pq enrollment request must advertise a key package, because '
            'that is the public half the approver encapsulates the symmetric '
            'key to. Supply a metadataBuilder that returns one, or use '
            'EnrollmentKeyExchangeMode.legacy.');
      }
      if (atEnrollmentRequest.apkamSymmetricKeyResolver == null) {
        throw AtEnrollmentException(
            'A pq enrollment request must supply an '
            'apkamSymmetricKeyResolver, or nothing would ever collect the '
            'symmetric key the approver encapsulates to it. The enrollment '
            'would authenticate and then be unable to decrypt anything.');
      }
    }

    // A pq request generates no symmetric key and wraps nothing: the approver
    // mints the key and encapsulates it to the advertised public half, which
    // waitForApproval collects. A legacy request keeps the RSA wrap — it is
    // what every published approver knows how to unwrap.
    String? encryptedAPKAMSymmetricKey;
    if (!isPq) {
      final SymmetricKey apkamSymmetricKey =
          AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256);
      atAuthKeys.apkamSymmetricKey = AtBytes.fromString(apkamSymmetricKey.key);
      // encrypting the following APKAM keys:
      // apkamSymmetricKey for the enroll verb
      // RSA encrypt via at_chops (wraps crypton's RSAPublicKey.encrypt:
      // base64(encryptData(utf8(msg)))).
      encryptedAPKAMSymmetricKey = base64Encode((RsaEncryptionAlgo()
            ..atPublicKey = AtPublicKey.fromString(defaultEncryptionPublicKey))
          .encrypt(utf8.encode(apkamSymmetricKey.key)));
    }

    EnrollVerbBuilder enrollVerbBuilder = EnrollVerbBuilder()
      ..appName = atEnrollmentRequest.appName
      ..deviceName = atEnrollmentRequest.deviceName
      ..encryptedAPKAMSymmetricKey = encryptedAPKAMSymmetricKey
      ..apkamPublicKey = apkamKeyPair.atPublicKey.publicKey
      ..otp = atEnrollmentRequest.otp
      ..namespaces = atEnrollmentRequest.namespaces
      ..apkamKeysExpiryDuration = atEnrollmentRequest.apkamKeysExpiryDuration
      ..metadata = metadata;

    String? serverResponse =
        await _executeEnrollCommand(enrollVerbBuilder, atLookUp);
    var enrollJson = jsonDecode(serverResponse);
    var enrollmentIdFromServer = enrollJson[AtConstants.enrollmentId];
    var enrollStatus = getEnrollStatusFromString(enrollJson['status']);

    atAuthKeys.enrollmentId = enrollmentIdFromServer;

    return AtEnrollmentResponse(enrollmentIdFromServer, enrollStatus,
        atSign: atEnrollmentRequest.atSign,
        rootDomain: atEnrollmentRequest.rootDomain,
        atAuthKeys: atAuthKeys,
        // Carry the requesting app's session forward so waitForApproval can
        // persist the completed keys into its atKeysIo and hand it back. The
        // session is only fully valid (keys persisted) after waitForApproval.
        session: atEnrollmentRequest.session,
        // Only a pq request has a symmetric key waiting to be collected; a
        // legacy one already holds its own.
        apkamSymmetricKeyResolver:
            isPq ? atEnrollmentRequest.apkamSymmetricKeyResolver : null);
  }

  /// Handles an APKAM-authenticated self-enrollment (the PQ retrofit).
  ///
  /// Serialised per keyfile by [_serializedPerKeyfile], whose critical
  /// section spans the whole check → mint → submit → persist sequence, so
  /// two processes sharing one keyfile cannot both mint.
  ///
  /// Idempotent per keyfile: when the keyfile already holds an active
  /// ML-DSA-65 signing material under some enrollment id, that enrollment is
  /// returned and nothing is minted or submitted. A crash after the request
  /// lands but before the keyfile is written leaves an orphan approved
  /// enrollment server-side whose private nobody holds — unusable and
  /// revocable, and a rerun spawns a fresh enrollment.
  Future<AtEnrollmentResponse> _handleSelfEnrollmentRequest(
      AtSelfEnrollmentRequest request, AtLookUp atLookUp) async {
    if (request.namespaces.isEmpty) {
      throw AtEnrollmentException(
          'a self-enrollment must request at least one namespace: the child '
          'holds exactly what it names, and the atServer refuses an empty '
          'set');
    }
    final keysIo = request.session.atKeysIo;
    if (keysIo is! WrittenAtKeysIo) {
      throw AtEnrollmentException(
          'a self-enrollment persists the new enrollment into the keyfile; '
          'the session must carry a writable AtKeysIo');
    }

    // The material tokens equal the SigningAlgoType member names (both are
    // the wire spelling), so the request's algo maps by name.
    final String materialAlgo;
    switch (request.signingAlgo) {
      case SigningAlgoType.mldsa65:
        materialAlgo = KeyAlgorithmType.mlDsa65;
      case SigningAlgoType.rsa2048:
        materialAlgo = KeyAlgorithmType.rsa2048;
      default:
        throw AtEnrollmentException(
            'a self-enrollment mints rsa2048 or mldsa65; '
            '"${request.signingAlgo.name}" is not a retrofit algorithm');
    }

    return await _serializedPerKeyfile(keysIo, request.atSign, () async {
      final existing = await keysIo.read(request.atSign);
      // Per requested algorithm, so re-running is idempotent for THIS mode
      // while a keyfile that holds a different algorithm's enrollment can
      // still retrofit into this one.
      final alreadyRetrofitted = existing.keys
          .where((m) =>
              m.keyAlgorithmType == materialAlgo &&
              m.keyPartType == CryptographicKeyType.privateSigning &&
              m.status == KeyPartStatus.active &&
              m.enrollmentId != null)
          .firstOrNull;
      if (alreadyRetrofitted != null) {
        _logger.info('keyfile already holds a $materialAlgo enrollment '
            '(${alreadyRetrofitted.enrollmentId}); not minting another');
        return AtEnrollmentResponse(
            alreadyRetrofitted.enrollmentId!, EnrollmentStatus.approved,
            atSign: request.atSign,
            rootDomain: request.rootDomain,
            atAuthKeys: existing,
            session: request.session);
      }

      // Fresh either way: a new enrollment never reuses the legacy key
      // object, which is what keeps one-enrollment-one-keypair and the PKAM
      // binding unambiguous.
      final String apkamPublic;
      final String apkamPrivate;
      if (request.signingAlgo == SigningAlgoType.mldsa65) {
        final pair = await MlDsa65KeyPair.generate();
        apkamPublic = pair.atPublicKey.publicKey;
        apkamPrivate = pair.atPrivateKey.privateKey;
      } else {
        final pair = AtChopsUtil.generateAtPkamKeyPair();
        apkamPublic = pair.atPublicKey.publicKey;
        apkamPrivate = pair.atPrivateKey.privateKey;
      }

      // Built before the request so a metadataBuilder can be handed the
      // APKAM keypair it must sign with; only enrollmentId is missing, and
      // only the atServer can supply it.
      final constructionKeys = AtKeys()
        ..apkamPublicKey = AtBytes.fromString(apkamPublic)
        ..apkamPrivateKey = AtBytes.fromString(apkamPrivate)
        ..defaultEncryptionPublicKey = existing.defaultEncryptionPublicKey;

      final metadata = await _buildMetadata(
          request.metadataBuilder, request.atSign, constructionKeys);

      // No otp and no encryptedAPKAMSymmetricKey: the connection's APKAM
      // authentication is the whole authority, and the keyfile already holds
      // every secret an approver would otherwise convey.
      final enrollVerbBuilder = EnrollVerbBuilder()
        ..appName = request.appName
        ..deviceName = request.deviceName
        ..apkamPublicKey = apkamPublic
        ..signingAlgo = request.signingAlgo.name
        ..namespaces = request.namespaces
        ..apkamKeysExpiryDuration = request.apkamKeysExpiryDuration
        ..metadata = metadata;

      // auth:true so a dropped connection re-authenticates as the parent
      // enrollment rather than reconnecting unauthenticated — the atServer
      // discriminates this path solely by the connection's authType.
      final serverResponse =
          await _executeEnrollCommand(enrollVerbBuilder, atLookUp, auth: true);
      final enrollJson = jsonDecode(serverResponse);
      final String newEnrollmentId = enrollJson[AtConstants.enrollmentId];
      final enrollStatus = getEnrollStatusFromString(enrollJson['status']);
      if (enrollStatus != EnrollmentStatus.approved) {
        // Deny the record this call just created, before giving up on it.
        //
        // An atServer without the self-retrofit auto-approve accepts the
        // request and parks it as `pending`, so aborting without cleaning up
        // leaves a request nobody will ever act on — and a client that retries
        // leaves one per attempt, which is how a roster fills with litter that
        // only expiry clears.
        //
        // Best effort, and why it can only be best effort is worth stating:
        // denying needs `__manage`, which the parent enrollment this
        // connection authenticated as may not hold. A scoped parent cannot
        // tidy up after itself, so the thrown message reports which happened
        // rather than implying the server was left clean.
        var cleanup = 'The pending enrollment $newEnrollmentId it created was '
            'denied.';
        try {
          await deny(
              EnrollmentRequestDecision.denied(newEnrollmentId, request.atSign),
              atLookUp);
        } catch (e) {
          cleanup = 'The pending enrollment $newEnrollmentId it created could '
              'NOT be denied ($e); it stays on the roster until it expires, '
              'and a retry will add another.';
        }
        throw AtEnrollmentException(
            'expected the self-enrollment to be auto-approved; the atServer '
            'returned status "${enrollJson['status']}". $cleanup');
      }

      // Persist into the SAME keyfile: the new credentials land as typed
      // materials tagged with the new enrollment id, while the legacy flat
      // fields — frozen by the keyfile's never-lose contract — keep carrying
      // the original enrollment's.
      final now = DateTime.now().toUtc();
      existing.addKey(AtKeysMaterial(
          keyId: 'apkam:$newEnrollmentId',
          enrollmentId: newEnrollmentId,
          keyPartType: CryptographicKeyType.privateSigning,
          keyAlgorithmType: materialAlgo,
          bytes: AtBytes.fromString(apkamPrivate),
          createdAt: now));
      existing.addKey(AtKeysMaterial(
          keyId: 'apkam:$newEnrollmentId',
          enrollmentId: newEnrollmentId,
          keyPartType: CryptographicKeyType.publicVerification,
          keyAlgorithmType: materialAlgo,
          bytes: AtBytes.fromString(apkamPublic),
          createdAt: now));
      // Whatever the metadataBuilder filed (the X-Wing key package's two
      // halves), re-tagged with the enrollment id it now belongs to.
      for (final material in constructionKeys.keys) {
        existing.addKey(AtKeysMaterial(
            keyId: material.keyId,
            enrollmentId: newEnrollmentId,
            keyPartType: material.keyPartType,
            keyAlgorithmType: material.keyAlgorithmType,
            bytes: material.bytes,
            operations: material.operations,
            createdAt: material.createdAt,
            status: material.status));
      }
      await keysIo.flush(request.atSign.toAtsign(), existing);

      return AtEnrollmentResponse(newEnrollmentId, enrollStatus,
          atSign: request.atSign,
          rootDomain: request.rootDomain,
          atAuthKeys: existing,
          session: request.session);
    });
  }

  /// Serialises the whole self-enrollment per keyfile. The critical section
  /// spans a network round trip, so it gets its own lock file and a
  /// staleness threshold sized for one — not the keyfile lock's
  /// milliseconds-scale settings (that lock still guards the flush inside).
  /// A non-file [AtKeysIo] (tests, custom stores) runs unserialised: it is
  /// process-local by construction.
  Future<T> _serializedPerKeyfile<T>(
      AtKeysIo keysIo, String atSign, Future<T> Function() action) {
    if (keysIo is FileAtKeysIo) {
      return AtKeysFileLock('${keysIo.filePath!(atSign)}.retrofit',
              timeout: const Duration(seconds: 30),
              staleAfter: const Duration(minutes: 2))
          .synchronized(action);
    }
    return action();
  }

  @override
  Future<AtEnrollmentResponse> approve(
      EnrollmentRequestDecision enrollmentRequestDecision,
      AtLookUp atLookUp) async {
    if (atLookUp.atChops == null) {
      throw AtAuthenticationException(
          'The authentication keys are not initialized');
    }
    // An enrollment that advertised a key package sent no wrapped key, because
    // this approver minted it — there is nothing to unwrap, and the RSA step is
    // skipped entirely rather than being fed an empty string. Every other
    // enrollment still arrives RSA-wrapped to the atSign's encryption public
    // key, and is decrypted here with the private half from the atChops
    // instance, via at_chops (wraps crypton's RSAPrivateKey.decrypt:
    // utf8.decode(decryptData(base64(msg)))).
    String apkamSymmetricKey = enrollmentRequestDecision
            .mintedApkamSymmetricKey ??
        utf8.decode((RsaEncryptionAlgo()
              ..atPrivateKey = AtPrivateKey.fromString(atLookUp.atChops!
                  .atChopsKeys.atEncryptionKeyPair!.atPrivateKey.privateKey))
            .decrypt(base64Decode(
                enrollmentRequestDecision.encryptedAPKAMSymmetricKey)));

    // Set the APKAM Symmetric key to the AtChops Instance.
    atLookUp.atChops?.atChopsKeys.apkamSymmetricKey = AESKey(apkamSymmetricKey);

    InitialisationVector encryptionPrivateKeyIV =
        AtChopsUtil.generateRandomIV(16);
    // Fetch the encryptionPrivateKey from the atChops and encrypt with APKAM Symmetric key.
    String encryptedDefaultEncryptionPrivateKey = (await atLookUp.atChops
            ?.encryptString(
                atLookUp.atChops!.atChopsKeys.atEncryptionKeyPair!.atPrivateKey
                    .privateKey,
                EncryptionKeyType.aes256,
                keyName: 'apkamSymmetricKey',
                iv: encryptionPrivateKeyIV))
        ?.result;

    InitialisationVector selfEncryptionKeyIV = AtChopsUtil.generateRandomIV(16);
    // Fetch the selfEncryptionKey from the atChops and encrypt with APKAM Symmetric key.
    String encryptedDefaultSelfEncryptionKey = (await atLookUp.atChops
            ?.encryptString(
                atLookUp.atChops!.atChopsKeys.selfEncryptionKey!.key,
                EncryptionKeyType.aes256,
                keyName: 'apkamSymmetricKey',
                iv: selfEncryptionKeyIV))
        ?.result;

    String command = 'enroll:approve:${jsonEncode({
          'enrollmentId': enrollmentRequestDecision.enrollmentId,
          'encryptedDefaultEncryptionPrivateKey':
              encryptedDefaultEncryptionPrivateKey,
          AtConstants.apkamEncryptionPrivateKeyIV:
              base64Encode(encryptionPrivateKeyIV.ivBytes),
          AtConstants.apkamEncryptedDefaultSelfEncryptionKey:
              encryptedDefaultSelfEncryptionKey,
          AtConstants.apkamSelfEncryptionKeyIV:
              base64Encode(selfEncryptionKeyIV.ivBytes)
        })}';

    String? enrollResponse =
        await atLookUp.executeCommand('$command\n', auth: true);
    enrollResponse = enrollResponse?.replaceFirst(RegExp(r'^data:'), '');
    var enrollmentJsonMap = jsonDecode(enrollResponse!);
    AtEnrollmentResponse enrollmentResponse = AtEnrollmentResponse(
        enrollmentJsonMap['enrollmentId'],
        getEnrollStatusFromString(enrollmentJsonMap['status']));
    return enrollmentResponse;
  }

  @override
  Future<AtEnrollmentResponse> deny(
      EnrollmentRequestDecision enrollmentRequestDecision,
      AtLookUp atLookUp) async {
    EnrollVerbBuilder denyEnrollmentBuilder = EnrollVerbBuilder()
      ..enrollmentId = enrollmentRequestDecision.enrollmentId
      ..operation = enrollmentRequestDecision.enrollOperationEnum;

    String? enrollResponse = await atLookUp
        .executeCommand(denyEnrollmentBuilder.buildCommand(), auth: true);

    enrollResponse = enrollResponse?.replaceFirst(RegExp(r'^data:'), '');
    var enrollmentJsonMap = jsonDecode(enrollResponse!);
    AtEnrollmentResponse enrollmentResponse = AtEnrollmentResponse(
        enrollmentJsonMap['enrollmentId'],
        getEnrollStatusFromString(enrollmentJsonMap['status']));
    return enrollmentResponse;
  }

  @override
  Future<AtEnrollmentResponse> revoke(
      EnrollmentRequestDecision enrollmentRequestDecision,
      AtLookUp atLookUp) async {
    EnrollVerbBuilder revokeEnrollVerbBuilder = EnrollVerbBuilder()
      ..enrollmentId = enrollmentRequestDecision.enrollmentId
      ..operation = EnrollOperationEnum.revoke
      ..force = enrollmentRequestDecision.force;

    String? enrollmentResponseStr = await atLookUp
        .executeCommand(revokeEnrollVerbBuilder.buildCommand(), auth: true);

    enrollmentResponseStr =
        enrollmentResponseStr?.replaceFirst(RegExp(r'^data:'), '');
    var enrollmentJsonMap = jsonDecode(enrollmentResponseStr!);
    AtEnrollmentResponse enrollmentResponse = AtEnrollmentResponse(
        enrollmentJsonMap['enrollmentId'],
        getEnrollStatusFromString(enrollmentJsonMap['status']));
    return enrollmentResponse;
  }

  /// waits for Approval of the enrollmentId related to [enrollmentResponse]
  /// completes the end of the handshake for the APKAM flow
  ///
  /// returns [AtEnrollmentResponse] to intake additional keys provided after submission
  @override
  Future<void> waitForApproval(
    AtEnrollmentResponse enrollmentResponse, {
    Duration retryInterval = const Duration(seconds: 2),
    bool logProgress = true,
    int maxRetries = 15,
    AtLookUp? atLookup,
  }) async {
    if (enrollmentResponse.atSign == null ||
        enrollmentResponse.atSign!.isEmpty) {
      throw InvalidResponseException(
          'atSign is not available in the enrollment response');
    }
    if (enrollmentResponse.rootDomain == null) {
      throw InvalidResponseException(
          'rootDomain is not available in the enrollment response');
    }
    if (enrollmentResponse.atAuthKeys == null) {
      throw InvalidResponseException(
          'AtAuthKeys are not avaialbe in the enrollemnt response');
    }

    atLookup ??= AtLookupImpl(
      enrollmentResponse.atSign!,
      enrollmentResponse.rootDomain!.rootDomain,
      enrollmentResponse.rootDomain!.rootPort,
    );

    // An enrollment that advertised a key package holds no symmetric key yet,
    // and `toAtChops` reads its absence as "these are PKAM keys" — which then
    // demands the encryption private key this enrollment is here to fetch. Its
    // APKAM keypair is all PKAM authentication needs, so build the chops from
    // that directly and fill the symmetric key in once it arrives.
    AtChops atChops =
        enrollmentResponse.atAuthKeys!.apkamSymmetricKey != null
            ? enrollmentResponse.atAuthKeys!.toAtChops()
            : _apkamChopsAwaitingSymmetricKey(enrollmentResponse.atAuthKeys!);
    atLookup.atChops = atChops;

    await _waitForPkamAuthSuccess(
      atLookup,
      enrollmentResponse.enrollmentId,
      retryInterval,
      logProgress: logProgress,
      maxRetries: maxRetries,
    );

    // post approval:
    // after pkam authentication is accepted

    // Collect the symmetric key the approver encapsulated to this enrollment's
    // key package. PKAM has just succeeded, which is the earliest point the
    // enrollment can read anything, and the key package's private half — the
    // only thing that opens that envelope — was minted before the request was
    // sent and has never left this device.
    final resolver = enrollmentResponse.apkamSymmetricKeyResolver;
    if (resolver != null) {
      final String apkamSymmetricKey =
          await resolver(enrollmentResponse.atAuthKeys!, atLookup);
      enrollmentResponse.atAuthKeys!.apkamSymmetricKey =
          AtBytes.fromString(apkamSymmetricKey);
      atChops.atChopsKeys.apkamSymmetricKey = AESKey(apkamSymmetricKey);
    }

    // fetch the following keys from the atServer
    Map<String, dynamic> encPrivKeyResponse =
        await _getDefaultEncryptionPrivateKey(
      atLookup,
      enrollmentResponse.atSign!,
      enrollmentResponse.enrollmentId,
    );

    Map<String, dynamic> selfEncKeyResponse = await _getSelfEncryptionKey(
      atLookup,
      enrollmentResponse.atSign!,
      enrollmentResponse.enrollmentId,
    );

    // decrypting the following after fetching
    // selfEncryptionKey (encrypted via apkamSymmetricKey from the enrollment)
    // defaultEncryptionPrivateKey (encrypted via apkamSymmetricKey from the enrollment)

    final aesEncryption = StringAESEncryptor(
        AESKey(enrollmentResponse.atAuthKeys!.apkamSymmetricKey!.toString()));

    // A record written by a legacy approver carries no `iv` field — those
    // values were encrypted under the zero IV — so its absence selects the
    // legacy IV rather than crashing. The record's vintage is the writing
    // approver's, not this client's.
    InitialisationVector ivOf(Map<String, dynamic> keyResponse) =>
        keyResponse['iv'] == null
            ? AtChopsUtil.generateIVLegacy()
            : AtChopsUtil.generateIVFromBase64String(keyResponse['iv']);

    String decryptedSelfEncryptionKey = aesEncryption.decrypt(
      selfEncKeyResponse['value'],
      iv: ivOf(selfEncKeyResponse),
    );

    String decryptedDefaultEncryptionPrivateKey = aesEncryption.decrypt(
      encPrivKeyResponse['value'],
      iv: ivOf(encPrivKeyResponse),
    );

    // set the fetched & decrypted keys in the reference
    enrollmentResponse.atAuthKeys!.defaultSelfEncryptionKey =
        AtBytes.fromString(decryptedSelfEncryptionKey);
    enrollmentResponse.atAuthKeys!.defaultEncryptionPrivateKey =
        AtBytes.fromString(decryptedDefaultEncryptionPrivateKey);

    // If the requesting app supplied a session with a writable key destination,
    // persist the completed keyset there and hand back a ready-to-use session.
    // Otherwise this is the legacy path: leave atAuthKeys populated for the
    // caller to persist and hand back no session.
    final keysIo = enrollmentResponse.session?.atKeysIo;
    if (keysIo is WrittenAtKeysIo) {
      await keysIo.flush(enrollmentResponse.atSign!.toAtsign(),
          enrollmentResponse.atAuthKeys!);
      enrollmentResponse.session = AtAuthSession(
        atSign: enrollmentResponse.atSign!,
        rootDomain: enrollmentResponse.rootDomain!,
        atKeysIo: keysIo,
        enrollmentId: enrollmentResponse.enrollmentId,
        atLookUp: atLookup,
      );
    } else {
      enrollmentResponse.session = null;
    }
  }

  @override
  Future<List<EnrollmentServerResponse>> list(
    List<EnrollmentStatus>? filters,
    AtLookUp atLookup, {
    String? arx,
    String? drx,
  }) async {
    String command = 'enroll:list';
    //Handle EnrollmentStatus enum to string
    String statusFilter = '';
    if (filters != null) {
      for (EnrollmentStatus filter in filters) {
        statusFilter += '${filter.name},';
      }

      //remove additional ','
      statusFilter = statusFilter.substring(0, statusFilter.length - 1);
      if (statusFilter.isNotEmpty) {
        command += ':{"enrollmentStatusFilter":["$statusFilter"]}';
      }
    }
    String rawResponse = (await atLookup.executeCommand(
      '$command\n',
      auth: true,
    ))!;

    RegExp? ar;
    RegExp? dr;
    if (arx != null) {
      ar = RegExp(arx);
    }
    if (drx != null) {
      dr = RegExp(drx);
    }
    if (rawResponse.startsWith('data:')) {
      rawResponse = rawResponse.substring(rawResponse.indexOf('data:') + 5);
      Map unfiltered = jsonDecode(rawResponse);
      List<EnrollmentServerResponse> filtered = [];
      for (final String ek in unfiltered.keys) {
        final e = unfiltered[ek];
        String appName = e['appName'] as String;
        if (ar != null) {
          if (!ar.hasMatch(appName)) {
            continue;
          }
        }
        String deviceName = e['deviceName'] as String;
        if (dr != null) {
          if (!dr.hasMatch(deviceName)) {
            continue;
          }
        }
        filtered.add(EnrollmentServerResponse.fromServer(MapEntry(ek, e)));
      }
      return filtered;
    } else {
      throw Exception('Unexpected server response: $rawResponse');
    }
  }

  Future<String> _getDefaultEncryptionPublicKey(
      AtLookUp atLookupImpl, String atSign) async {
    LookupVerbBuilder builder = LookupVerbBuilder()
      ..atKey = (AtKey()
        ..key = 'publicKey'
        ..sharedBy = atSign);
    String? lookupResult = await atLookupImpl.executeVerb(builder);
    if (lookupResult == null || lookupResult.isEmpty) {
      throw AtEnrollmentException(
          'Unable to lookup encryption public key. Server response is null/empty');
    }
    var defaultEncryptionPublicKey =
        lookupResult.replaceFirst(RegExp(r'^data:'), '');

    return defaultEncryptionPublicKey;
  }

  Future<Map<String, dynamic>> _getDefaultEncryptionPrivateKey(
      AtLookUp atLookUp, String atSign, String enrollmentId) async {
    String cmd =
        "keys:get:keyName:$enrollmentId.default_enc_private_key.__manage$atSign\n";
    _logger.shout('cmd: $cmd');
    String? lookupResult = await atLookUp.executeCommand(cmd);
    if (lookupResult == null || lookupResult.isEmpty) {
      throw AtEnrollmentException(
          'Unable to lookup encryption privateKey key. Server response is null/empty');
    }
    var jsonString = lookupResult.replaceFirst(RegExp(r'^data:'), '');
    Map<String, dynamic> map = jsonDecode(jsonString);
    return map;
  }

  Future<Map<String, dynamic>> _getSelfEncryptionKey(
      AtLookUp atLookUp, String atSign, String enrollmentId) async {
    String cmd =
        "keys:get:keyName:$enrollmentId.default_self_enc_key.__manage$atSign\n";
    _logger.shout('cmd: $cmd');
    String? lookupResult = await atLookUp.executeCommand(cmd);
    if (lookupResult == null || lookupResult.isEmpty) {
      throw AtEnrollmentException(
          'Unable to lookup encryption privateKey key. Server response is null/empty');
    }
    var jsonString = lookupResult.replaceFirst(RegExp(r'^data:'), '');

    var map = jsonDecode(jsonString);
    return map;
  }

  Future<String> _executeEnrollCommand(
      EnrollVerbBuilder enrollVerbBuilder, AtLookUp atLookUp,
      {bool auth = false}) async {
    var enrollResult = await atLookUp
        .executeCommand(enrollVerbBuilder.buildCommand(), auth: auth);
    if (enrollResult == null ||
        enrollResult.isEmpty ||
        enrollResult.startsWith('error:')) {
      throw AtEnrollmentException(
          'Enrollment response from server: $enrollResult');
    }
    return enrollResult.replaceFirst(RegExp(r'^data:'), '');
  }

  /// Pkam auth will be retried until server approves/denies/expires the enrollment
  /// APKAM chops for an enrollment that has not yet been handed its symmetric
  /// key: enough to PKAM-authenticate, and nothing more.
  ///
  /// Deliberately not `AtKeys.toAtChops`, which branches on the symmetric key's
  /// presence to tell APKAM keys from PKAM keys and so mis-reads this state.
  AtChops _apkamChopsAwaitingSymmetricKey(AtKeys atKeys) {
    return AtChopsImpl(AtChopsKeys.create(
      AtEncryptionKeyPair.create(
        atKeys.defaultEncryptionPublicKey!.toString(),
        '',
      ),
      AtPkamKeyPair.create(
        atKeys.apkamPublicKey!.toString(),
        atKeys.apkamPrivateKey!.toString(),
      ),
    ));
  }

  Future<void> _waitForPkamAuthSuccess(
    AtLookUp atLookUp,
    String enrollmentIdFromServer,
    Duration retryInterval, {
    bool logProgress = true,
    required int maxRetries,
  }) async {
    int retryAttempt = 0;
    AtSignLogger logger = AtSignLogger('AtEnrollmentImpl');
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
            'Exception occurred when authenticating the atSign caused by ${e.toString()}';
        if (retryAttempt > maxRetries) {
          message += ' Activation failed after $maxRetries attempts';
          logger.severe(message);
          _addProgress('PKAM', message, ProgressEventType.error);
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

  static const _kSppRegex = r'[A-Za-z0-9]{6}';
  static const _defaultOtpExpiry = Duration(minutes: 5);

  @override
  Future<Otp> generateOtp(AtLookUp atLookUp,
      {Duration expiry = _defaultOtpExpiry}) async {
    final command = 'otp:get:ttl:${expiry.inMilliseconds}\n';
    final response = await atLookUp.executeCommand(command, auth: true);
    if (response != null && response.startsWith('data:')) {
      final otp = response.substring(response.indexOf('data:') + 5).trim();
      return Otp.fromDuration(value: otp, duration: expiry);
    }
    throw AtEnrollmentException('Failed to generate OTP. Response: $response');
  }

  @override
  Future<Otp> setSpp(String spp, AtLookUp atLookUp,
      {Duration expiry = _defaultOtpExpiry}) async {
    if (!RegExp('^$_kSppRegex\$').hasMatch(spp)) {
      throw AtEnrollmentException(
          'SPP must be alphanumeric and exactly 6 characters');
    }
    final command = 'otp:put:$spp:ttl:${expiry.inMilliseconds}\n';
    final response = await atLookUp.executeCommand(command, auth: true);
    if (response == null || !response.contains('ok')) {
      throw AtEnrollmentException('Failed to set SPP. Response: $response');
    }
    return Otp.fromDuration(value: spp, duration: expiry);
  }

  Future<void> waitBriefly({int millis = 500}) async {
    await Future.delayed(Duration(milliseconds: millis));
  }
}
