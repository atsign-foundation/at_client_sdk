import 'dart:async';
import 'dart:convert';

import 'package:at_auth/src/auth/onboarding_mint.dart' show mintApkamKeyPair;
import 'package:at_auth/src/enroll/apsk_advertisement.dart';
import 'package:at_auth/src/enroll/enrollment_approver.dart';
import 'package:at_auth/src/enroll/enrollment_progress.dart';
import 'package:at_auth/src/enroll/models/at_enrollment_request.dart';
import 'package:at_auth/src/enroll/models/at_enrollment_response.dart';
import 'package:at_auth/src/enroll/models/enrollment_request_decision.dart';
import 'package:at_auth/src/enroll/retrofit_serializer.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/io/at_keys_io.dart';
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
        enrollmentRequest.atKeys ?? AtKeys(),
        failOnBuilderError: true);

    EnrollVerbBuilder enrollVerbBuilder = EnrollVerbBuilder()
      ..appName = enrollmentRequest.appName
      ..deviceName = enrollmentRequest.deviceName
      ..signingAlgo = enrollmentRequest.signingAlgo.name
      ..metadata = metadata;
    final advertised = _apskFor(
        apkamPublicKey: enrollmentRequest.apkamPublicKey!,
        signingAlgo: enrollmentRequest.signingAlgo,
        metadata: metadata,
        advertisedSigningKey: enrollmentRequest.advertisedSigningKey);
    enrollVerbBuilder
      ..apsk = advertised.apsk
      ..apskLegacy = advertised.apskLegacy;
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

  /// The `_apsk` this request advertises: the bare RSA string, or the
  /// structured array. Never both — they would disagree about one record.
  ///
  /// A plain-legacy enrollment sends the **bare** form, which is the key
  /// itself. Every deployed `_apsk` consumer base64-decodes the value as an
  /// RSA key, so a JSON one fails their parse — fail-closed, but
  /// service-breaking for anything already running. Sending the bare key here
  /// reproduces exactly what the atServer used to compose for such an
  /// enrollment, so the published record is unchanged from the day this moved
  /// client-side.
  ///
  /// Everything else sends the array: an enrollment whose advertised key's
  /// algorithm is not the rsa2048 a bare value implies, since nothing could
  /// read it otherwise; and an APKAM-key-advertising enrollment carrying a key
  /// package, whose signer's algorithm the bare form cannot state.
  ///
  /// **[advertisedSigningKey] is preferred over [apkamPublicKey] whenever it
  /// is there.** An enrollment that owns a signing key advertises *that*,
  /// because that is what signs; the APKAM key authenticates connections and
  /// signs nothing once a signing key exists.
  ///
  /// ⚠️ **With a signing key present, a key package no longer forces the
  /// array.** It forced it while the package was signed by the APKAM key,
  /// whose algorithm is whatever the enrollment authenticates with — which a
  /// bare value, meaning `rsa2048` by convention, cannot state. A package
  /// signed by an rsa2048 *signing* key is exactly what the bare form does
  /// state, and rollout 1 depends on that: an un-upgraded peer has to
  /// base64-decode this value as an RSA key, and it is also the value that
  /// peer verifies the package against.
  ({Map<String, dynamic>? apsk, String? apskLegacy}) _apskFor({
    required String apkamPublicKey,
    required SigningAlgoType signingAlgo,
    required Map<String, dynamic>? metadata,
    ({
      SigningAlgoType algorithm,
      String publicKey,
      String privateKey
    })? advertisedSigningKey,
  }) {
    final alg = advertisedSigningKey?.algorithm ?? signingAlgo;
    final pub = advertisedSigningKey?.publicKey ?? apkamPublicKey;

    if (alg == SigningAlgoType.rsa2048 &&
        (advertisedSigningKey != null || metadata?['keyPackage'] == null)) {
      return (apsk: null, apskLegacy: pub);
    }
    // One key: at request time the enrollment holds this one and nothing else.
    // A second algorithm's key is added by a later `enroll:update`, once
    // something has minted one — which is why the record is an array from its
    // first byte rather than growing into one.
    return (
      apsk: apskAdvertisement(
          keys: [ApskSigningKey.forPublicKey(alg: alg, pub: pub)]),
      apskLegacy: null
    );
  }

  /// The keyfile's spelling of [algorithm]. The material tokens equal the
  /// [SigningAlgoType] member names — both are the wire spelling — so a second
  /// spelling here would file material the reader skips.
  static CryptographicMaterialAlgorithm _materialAlgorithmOf(
          SigningAlgoType algorithm) =>
      switch (algorithm) {
        SigningAlgoType.mldsa65 => CryptographicMaterialAlgorithm.mlDsa65,
        SigningAlgoType.rsa2048 => CryptographicMaterialAlgorithm.rsa2048,
        _ => throw AtEnrollmentException(
            'an enrollment mints rsa2048 or mldsa65; '
            '${algorithm.name} has no keyfile material spelling here'),
      };

  /// Runs [AtEnrollmentRequest.metadataBuilder], if the caller supplied one,
  /// over an [AtKeysIo] holding this request's freshly generated keys.
  ///
  /// The result is attached to the request unchanged — at_auth ferries the
  /// metadata, it does not interpret it. A builder that returns null, or
  /// throws, must not cost the caller its enrollment: the metadata is opaque
  /// and additive, so a request without it is a valid request, and the
  /// alternative is failing an enrollment over an optional payload.
  ///
  /// [failOnBuilderError] inverts that for the FIRST enrollment, and only
  /// there. The reasoning above depends on there being an enrollment to cost
  /// the caller, and on that path there is not one yet: nothing exists
  /// server-side and the CRAM secret has not been spent, so failing costs a
  /// retry and nothing else. Degrading instead activates the atSign for good
  /// with no encapsulation key advertised, reports success, and leaves the
  /// only evidence in a `severe` log line — and for an `rsa2048` activation
  /// the request that goes out is indistinguishable from a deliberate legacy
  /// onboard rather than a failure.
  Future<Map<String, dynamic>?> _buildMetadata(
      FutureOr<Map<String, dynamic>?> Function(AtKeysIo keysIo)? builder,
      String atSign,
      AtKeys keys,
      {bool failOnBuilderError = false}) async {
    if (builder == null) return null;

    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, keys);
    try {
      return await builder(keysIo);
    } catch (e, st) {
      if (failOnBuilderError) {
        _logger.severe('metadataBuilder threw on a first enrollment, so the '
            'activation is being failed rather than completed without a key '
            'package: $e, $st');
        rethrow;
      }
      _logger.severe('metadataBuilder threw; submitting the enrollment request '
          'without metadata: $e, $st');
      return null;
    }
  }

  /// Handles the subsequent enrollment requests.
  Future<AtEnrollmentResponse> _handleAtEnrollmentRequest(
      AtEnrollmentRequest atEnrollmentRequest, AtLookUp atLookUp) async {
    // Generate required keys, under the algorithm the CALLER named. This used
    // to be `AtChopsUtil.generateAtPkamKeyPair()` — RSA-2048 with no argument
    // — so an app enrolling over OTP could not ask for anything else. On an
    // atSign whose deployment had moved to post-quantum, every install then
    // created an RSA-authenticating enrollment that the client retrofitted
    // away on its first start, leaving a discarded enrollment behind and an
    // RSA credential live for the atServer's grace window.
    final apkam = await mintApkamKeyPair(atEnrollmentRequest.signingAlgo);

    //Fetch required keys from atServer
    String defaultEncryptionPublicKey = await _getDefaultEncryptionPublicKey(
      atLookUp,
      atEnrollmentRequest.atSign,
    );

    // Built before the request rather than after it, so a metadataBuilder can
    // be handed the APKAM keypair it must sign with. Only enrollmentId is
    // missing at this point, and only the atServer can supply it — it assigns
    // one in its response below.
    // The flat fields carry the keypair whatever the algorithm, because the
    // metadata builder signs with it and reads it from there, and there is no
    // enrollment id to file typed material under until the atServer answers.
    // For rsa2048 that is also where it stays. For anything else it is
    // scaffolding, re-filed as typed material and cleared below — leaving it
    // would make the keyfile answer the "which enrollment do I authenticate
    // as" question two different ways.
    AtKeys atAuthKeys = AtKeys()
      ..apkamPrivateKey = AtBytes.fromString(apkam.privateKey)
      ..apkamPublicKey = AtBytes.fromString(apkam.publicKey)
      ..defaultEncryptionPublicKey =
          AtBytes.fromString(defaultEncryptionPublicKey);

    // The builder gets its OWN AtKeys, not the one this method returns.
    // It files what it mints, and at this moment the enrollment does not
    // exist, so there is no id to file under: anything written straight into
    // `atAuthKeys` lands in the atSign's container and stays there, because
    // nothing below re-tags it. `_handleSelfEnrollmentRequest` and
    // `AtAuthImpl.onboard` both hand over construction keys for this reason
    // and adopt afterwards; this path did not, so a key package's private
    // half was filed as the atSign's rather than the enrollment's — not
    // reaped when the enrollment is retired, and absent from
    // `keysForEnrollment`.
    final constructionKeys = AtKeys()
      ..apkamPrivateKey = AtBytes.fromString(apkam.privateKey)
      ..apkamPublicKey = AtBytes.fromString(apkam.publicKey)
      ..defaultEncryptionPublicKey =
          AtBytes.fromString(defaultEncryptionPublicKey);

    final Map<String, dynamic>? metadata = await _buildMetadata(
        atEnrollmentRequest.metadataBuilder,
        atEnrollmentRequest.atSign,
        constructionKeys);

    // A key package is advertised in every mode — it is also how an approver
    // seals this atSign's existing secrets to the new device — so its presence
    // says nothing about how the symmetric key travels. Only the declared mode
    // does.
    final bool isPq =
        atEnrollmentRequest.keyExchangeMode == EnrollmentKeyExchangeMode.pq;

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
      ..apkamPublicKey = apkam.publicKey
      ..signingAlgo = atEnrollmentRequest.signingAlgo.name
      ..otp = atEnrollmentRequest.otp
      ..namespaces = atEnrollmentRequest.namespaces
      ..apkamKeysExpiryDuration = atEnrollmentRequest.apkamKeysExpiryDuration
      ..metadata = metadata;
    // Without an `_apsk` the atServer publishes nothing, and the approver has
    // no key to verify the advertised key package against — so it seals no
    // secrets to an enrollment that is otherwise perfectly good. It advertises
    // the algorithm actually minted; this said `rsa2048` unconditionally,
    // which was true only because nothing else could be minted here.
    final advertised = _apskFor(
        apkamPublicKey: apkam.publicKey,
        signingAlgo: atEnrollmentRequest.signingAlgo,
        metadata: metadata,
        advertisedSigningKey: atEnrollmentRequest.advertisedSigningKey);
    enrollVerbBuilder
      ..apsk = advertised.apsk
      ..apskLegacy = advertised.apskLegacy;

    String? serverResponse =
        await _executeEnrollCommand(enrollVerbBuilder, atLookUp);
    var enrollJson = jsonDecode(serverResponse);
    var enrollmentIdFromServer = enrollJson[AtConstants.enrollmentId];
    var enrollStatus = getEnrollStatusFromString(enrollJson['status']);

    atAuthKeys.enrollmentId = enrollmentIdFromServer;

    // Whatever the metadataBuilder filed — the key package's two halves —
    // re-tagged with the enrollment id it now belongs to, which is the step
    // the other two enrollment paths already take.
    atAuthKeys.adoptMaterials(constructionKeys.keys,
        enrollmentId: enrollmentIdFromServer);

    // Now that the enrollment has a name, a non-rsa2048 APKAM is ALSO filed as
    // typed material under it — which is what tells a later reader the
    // algorithm, since the flat fields carry bytes and no algorithm at all.
    //
    // The flat copy stays, and that is deliberate. Flat and typed naming
    // DIFFERENT enrollments is the state worth avoiding — a retrofitted
    // keyfile, where the flat fields are the enrollment that was left behind —
    // and this is not that: one enrollment, and `enrollmentId` above names it,
    // so every reader resolves to the same keypair whichever way it looks.
    // Clearing them instead breaks the approval handshake, which needs the
    // symmetric key and the keypair from one `toAtChops`.
    if (atEnrollmentRequest.signingAlgo != SigningAlgoType.rsa2048) {
      atAuthKeys.fileApkamMaterial(
          enrollmentId: enrollmentIdFromServer,
          algorithm: CryptographicMaterialAlgorithm.of(
              atEnrollmentRequest.signingAlgo.name),
          publicKey: apkam.publicKey,
          privateKey: apkam.privateKey);
    }

    // Filed, not merely advertised. An enrollment whose `_apsk` names a key
    // its keyfile does not hold signs with something else, and the next
    // start's SigningKeyMinting finds the in-use algorithm missing, mints a
    // SECOND key and republishes — orphaning the key this record already
    // published and unverifying whatever was signed against it.
    //
    // Into `atAuthKeys` rather than `constructionKeys`: this is the
    // enrollment's own signing material, not something the metadataBuilder
    // minted, and it is filed here because only now is there an id to file it
    // under.
    final signing = atEnrollmentRequest.advertisedSigningKey;
    if (signing != null) {
      atAuthKeys.fileSigningMaterial(
          enrollmentId: enrollmentIdFromServer,
          algorithm: _materialAlgorithmOf(signing.algorithm),
          publicKey: signing.publicKey,
          privateKey: signing.privateKey);
    }

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
    final CryptographicMaterialAlgorithm materialAlgo;
    switch (request.signingAlgo) {
      case SigningAlgoType.mldsa65:
        materialAlgo = CryptographicMaterialAlgorithm.mlDsa65;
      case SigningAlgoType.rsa2048:
        materialAlgo = CryptographicMaterialAlgorithm.rsa2048;
      default:
        throw AtEnrollmentException(
            'a self-enrollment mints rsa2048 or mldsa65; '
            '"${request.signingAlgo.name}" is not a retrofit algorithm');
    }

    return await _serializedPerKeyfile(keysIo, request.atSign, () async {
      final existing = await keysIo.read(request.atSign);
      // A keyfile is retrofitted ONCE. Any active authentication material is
      // that retrofit, whatever algorithm it names — two live enrollments in
      // one keyfile leave no unique answer to which one it authenticates as,
      // which the assurance invariants now refuse outright.
      //
      // Two cases, and the difference matters:
      //
      //  - the SAME algorithm is a re-run, and returns the existing
      //    enrollment. `selfRetrofit` documents itself as idempotent and
      //    relies on it: a failed signing-root step is recovered by running
      //    the whole thing again, so throwing here would make that retry
      //    impossible;
      //  - a DIFFERENT algorithm is a second retrofit, and throws. Quietly
      //    handing back an mldsa65 enrollment to a caller that asked for
      //    rsa2048 would have it believe it holds a mode it does not.
      final alreadyRetrofitted = existing.keys
          .where((m) =>
              m.role == CryptographicMaterialRole.privateAuthentication &&
              m.status == CryptographicMaterialStatus.active &&
              m.enrollmentId != null)
          .firstOrNull;
      if (alreadyRetrofitted != null &&
          alreadyRetrofitted.algorithm != materialAlgo) {
        throw AtEnrollmentException('this keyfile already holds enrollment '
            '${alreadyRetrofitted.enrollmentId} '
            '(${alreadyRetrofitted.algorithm}); a keyfile is '
            'retrofitted once, so it cannot also take a $materialAlgo '
            'retrofit');
      }
      if (alreadyRetrofitted != null) {
        _logger.info('keyfile already holds enrollment '
            '${alreadyRetrofitted.enrollmentId} ($materialAlgo); this is a '
            're-run, not a second retrofit — not minting another');
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

      // Whether this connection will have to approve its own request.
      //
      // A PRE-ENROLLMENT atSign authenticates with the flat
      // `at_pkam_publickey`, so the atServer marks the connection
      // `pkamLegacy` and leaves its enrollment id null. The self-enrolment
      // auto-approve is gated on an APKAM-authenticated connection, so such a
      // request lands `pending` — and it is approvable on this same
      // connection, because the atServer grants a connection carrying no
      // enrollment id full access. The client is therefore its own approver.
      //
      // ⚠️ **Read off the SESSION, not off `atLookUp.enrollmentId`, and the
      // difference is not cosmetic.** `pending` has two causes, and only one
      // of them may be approved here: this one, and an APKAM self-enrolment
      // against an atServer too old to auto-approve it. The second keeps the
      // deny-and-throw below, which is a deliberate ruling about old servers
      // — so the discriminator has to be which identity is being retrofitted,
      // which is what the session states, rather than a connection field a
      // caller may not have set.
      final selfApproves = request.session.enrollmentId == null;

      // No otp: the connection's own authentication is the whole authority.
      //
      // An APKAM-authenticated retrofit also sends no
      // `encryptedAPKAMSymmetricKey` — the keyfile already holds every secret
      // an approver would otherwise convey. A self-approving one must send
      // one, because `enroll:approve` requires the encryption private key and
      // the self-encryption key wrapped under a symmetric key, and there has
      // to be a symmetric key for that. It is wrapped to the atSign's own
      // encryption public key, exactly as an ordinary legacy-mode request
      // wraps it, so the record keeps a copy the atSign's own encryption
      // private key can recover — nothing here is stranded by being minted in
      // a process that then forgets it.
      String? encryptedAPKAMSymmetricKey;
      if (selfApproves) {
        final encryptionPublicKey = existing.defaultEncryptionPublicKey;
        if (encryptionPublicKey == null) {
          throw AtEnrollmentException(
              'a self-approving enrollment wraps its symmetric key to the '
              'atSign\'s encryption public key, and this keyfile carries '
              'none');
        }
        final symmetric =
            AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256);
        encryptedAPKAMSymmetricKey = base64Encode((RsaEncryptionAlgo()
              ..atPublicKey =
                  AtPublicKey.fromString(encryptionPublicKey.toString()))
            .encrypt(utf8.encode(symmetric.key)));
      }

      final enrollVerbBuilder = EnrollVerbBuilder()
        ..appName = request.appName
        ..deviceName = request.deviceName
        ..apkamPublicKey = apkamPublic
        ..signingAlgo = request.signingAlgo.name
        ..namespaces = request.namespaces
        ..apkamKeysExpiryDuration = request.apkamKeysExpiryDuration
        ..encryptedAPKAMSymmetricKey = encryptedAPKAMSymmetricKey
        ..metadata = metadata;
      // The retrofitted enrollment publishes the key it just minted, not the
      // one the keyfile arrived with: `_apsk` is per enrollment, and this is a
      // new enrollment id.
      final advertised = _apskFor(
          advertisedSigningKey: request.advertisedSigningKey,
          apkamPublicKey: apkamPublic,
          signingAlgo: request.signingAlgo,
          metadata: metadata);
      enrollVerbBuilder
        ..apsk = advertised.apsk
        ..apskLegacy = advertised.apskLegacy;

      // auth:true so a dropped connection re-authenticates as the parent
      // enrollment rather than reconnecting unauthenticated — the atServer
      // discriminates this path solely by the connection's authType.
      final serverResponse =
          await _executeEnrollCommand(enrollVerbBuilder, atLookUp, auth: true);
      final enrollJson = jsonDecode(serverResponse);
      final String newEnrollmentId = enrollJson[AtConstants.enrollmentId];
      var enrollStatus = getEnrollStatusFromString(enrollJson['status']);

      if (enrollStatus == EnrollmentStatus.pending && selfApproves) {
        // The ordinary approver, on its ordinary path: it unwraps the
        // symmetric key sent above with this connection's encryption private
        // key, then wraps the encryption private key and the self-encryption
        // key under it. Nothing about this approval is special-cased — what
        // is unusual is only that the approver and the enrollee are one
        // process.
        _logger.info('Enrollment $newEnrollmentId is pending on a connection '
            'holding no enrollment id, so this client approves its own '
            'request');
        enrollStatus = (await _approver.approve(
                EnrollmentRequestDecision.approved(
                    enrollmentId: newEnrollmentId,
                    apkamSymmetricKey:
                        AtBytes.fromString(encryptedAPKAMSymmetricKey!),
                    atSign: request.atSign),
                atLookUp))
            .enrollStatus;
      }

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
      // Filed, not merely advertised. An enrollment whose `_apsk` names a key
      // its keyfile does not hold signs with something else, and the next
      // start's SigningKeyMinting finds the in-use algorithm missing, mints a
      // SECOND key and republishes — orphaning the key this record already
      // published and unverifying whatever was signed against it.
      final signing = request.advertisedSigningKey;
      if (signing != null) {
        existing.fileSigningMaterial(
            enrollmentId: newEnrollmentId,
            algorithm: _materialAlgorithmOf(signing.algorithm),
            publicKey: signing.publicKey,
            privateKey: signing.privateKey);
      }
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

  /// Serialises the whole self-enrollment against anything else retrofitting
  /// the same keys. The critical section spans a network round trip *and* the
  /// decision taken from what the read returned, so it is wider than the lock
  /// a store takes around its own flush.
  ///
  /// Whether two of these can race at all depends on where the keys live,
  /// which only the store knows — so the process says how via
  /// [retrofitSerializer]. Left unset the sequence runs directly, which is
  /// right for a store no other process can open.
  Future<T> _serializedPerKeyfile<T>(
      AtKeysIo keysIo, String atSign, Future<T> Function() action) {
    final serialize = retrofitSerializer;
    if (serialize == null) return action();
    return serialize<T>(keysIo, atSign, action);
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
