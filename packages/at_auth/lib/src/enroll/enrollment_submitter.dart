import 'dart:async';
import 'dart:convert';

import 'package:at_auth/src/enroll/enrollment_approver.dart';
import 'package:at_auth/src/enroll/enrollment_progress.dart';
import 'package:at_auth/src/enroll/models/at_enrollment_request.dart';
import 'package:at_auth/src/enroll/models/at_enrollment_response.dart';
import 'package:at_auth/src/enroll/models/enrollment_request_decision.dart';
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

/// The requesting side of an enrollment: mint this device's keys, tell the
/// atServer what access is being asked for, and hand back the response the
/// handshake then waits on.
///
/// Every path here ends at one `enroll:` command, and the three that reach it
/// differ only in what authority they carry — a CRAM connection for the first
/// enrollment, an OTP for a new device, and an already-enrolled APKAM
/// connection for the retrofit. What none of them carry is the authority to
/// decide their own request; that belongs to [EnrollmentApprover], which this
/// class holds only to clean up after a self-enrollment the atServer parked
/// instead of approving.
class EnrollmentSubmitter {
  final AtSignLogger _logger = AtSignLogger('EnrollmentSubmitter');

  final EnrollmentProgress _progress;
  final EnrollmentApprover _approver;

  EnrollmentSubmitter(this._progress, this._approver);

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
        _progress.add('enrollment', 'Invalid Enrollment request received',
            ProgressEventType.error);
        throw InvalidRequestException('Invalid Enrollment request received');
    }
    _progress.add('enrollment', 'Enrollment request submitted',
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

    // AtEnrollmentRequest.pq requires the builder and the resolver, so the
    // only pq mistake still reachable here is a builder that returned no key
    // package — a property of its output, which no constructor can promise.
    if (isPq && metadata?['keyPackage'] == null) {
      throw AtEnrollmentException(
          'A pq enrollment request must advertise a key package, because '
          'that is the public half the approver encapsulates the symmetric '
          'key to. Supply a metadataBuilder that returns one, or use the '
          'default (legacy) constructor.');
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
        // legacy one already holds its own, and its resolver is null by
        // construction.
        apkamSymmetricKeyResolver:
            atEnrollmentRequest.apkamSymmetricKeyResolver);
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
          await _approver.deny(
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
      existing.fileApkamMaterial(
          enrollmentId: newEnrollmentId,
          algorithm: materialAlgo,
          publicKey: apkamPublic,
          privateKey: apkamPrivate);
      // Whatever the metadataBuilder filed (the X-Wing key package's two
      // halves), re-tagged with the enrollment id it now belongs to.
      existing.adoptMaterials(constructionKeys.keys,
          enrollmentId: newEnrollmentId);
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
}
