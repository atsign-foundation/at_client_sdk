import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/src/auth/apkam_signing_scheme.dart';
import 'package:at_auth/src/auth/pkam_authenticator.dart';
import 'package:at_auth/src/enroll/apkam_key_conveyance.dart';
import 'package:at_auth/src/enroll/at_enrollment.dart';
import 'package:at_auth/src/enroll/models/at_enrollment_response.dart';
import 'package:at_auth/src/enroll/models/otp.dart';
import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/io/at_keys_io.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_utils/at_progress.dart';
import 'package:meta/meta.dart';

import '../keys/serialization/key_ids.dart';
import 'models/namespace_permission.dart';

/// A concrete implementation of [AtEnrollment] for managing enrollments.
///
/// This class provides functionality to submit and manage enrollment requests.
class AtEnrollmentImpl implements AtEnrollment {
  final AtSignLogger _logger = AtSignLogger('AtEnrollmentImpl');
  @override
  final AtLookUp atLookUp;

  @override
  final ApkamSigningScheme signing;

  /// Builds the connection [waitForApproval] PKAMs the pending enrollment on.
  /// [atLookUp] cannot serve that: it belongs to whoever submitted the request
  /// and was constructed before the APKAM keypair existed.
  final AtLookUpFactory _lookUpFactory;

  final ApkamKeyConveyance _conveyance;

  AtEnrollmentImpl(
    this.atLookUp, {
    this.signing = ApkamSigningScheme.legacy,
    AtLookUpFactory? atLookUpFactory,
    ApkamKeyConveyance? conveyance,
  })  : _lookUpFactory = atLookUpFactory ?? signing.lookUpFactory,
        _conveyance = conveyance ?? signing.conveyance;

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

  /// Handles the activation enrollment, submitted when an atsign is first
  /// onboarded.
  @internal
  @override
  Future<AtEnrollmentResponse> firstEnrollment(
    String apkamPublicKey, {
    String? appName,
    String? deviceName,
  }) async {
    // these are reserved appName and deviceName for the first onboarding enrollment
    EnrollVerbBuilder enrollVerbBuilder = EnrollVerbBuilder()
      ..appName = appName ?? 'firstApp'
      ..deviceName = deviceName ?? 'firstDevice'
      ..apkamPublicKey = apkamPublicKey
      ..signingAlgo = signing.signingAlgo;

    String? serverResponse =
        await _executeEnrollCommand(enrollVerbBuilder, atLookUp);
    var enrollJson = jsonDecode(serverResponse);
    var enrollmentIdFromServer = enrollJson[AtConstants.enrollmentId];
    var enrollStatus = getEnrollStatusFromString(enrollJson['status']);

    return AtEnrollmentResponse(
      enrollmentIdFromServer,
      enrollStatus,
    );
  }

  /// Handles the subsequent enrollment requests.
  ///
  /// Legacy Path:
  ///   - mint Apkam key pair
  ///   - fetch defaultEncryptionPublicKey
  ///   - mint APKAM symmetricKey
  ///   - encrypt with defaultEncryptionPublicKey
  ///   - send payload to @alice
  /// PQ:
  ///   - mint apkam key pair (xwing)
  ///   - fetch pqpublickey
  ///   - encaps to pqpublickey
  ///   - sharedSecret is apkam symmetricKey
  ///   - send payload to @alice
  ///
  /// This method is fully functional regardless of `ApkamSigningScheme`,
  /// so if we end up defaulting to `ApkamSigningScheme.legacy` or `pq`,
  /// no functionality will need to change
  @override
  Future<AtEnrollmentResponse> enroll({
    required Atsign atsign,
    required AtRootDomain rootDomain,
    required String appName,
    required String deviceName,
    required Otp otp,
    required List<NamespacePermission> namespaces,
    Duration? apkamKeysExpiryDuration,
  }) async {
    AtKeys pendingKeys = AtKeys(atsign: atsign);
    // mint fresh apkamKeyPair
    await signing.mintKeys(pendingKeys);

    // The atsign's *own* published key — the recipient the symmetric key is
    // conveyed to. Not to be confused with the APKAM public key this enrollment
    // just minted for itself, which is what goes on the verb below.
    String publishedPublicKey = await _getPublicKey(
      atLookUp,
      atsign,
    );

    // rsa wrap an aes key
    // xwing encaps with the fetched publicKey
    // encrypted = cipher, apkamSymmetricKey = sharedSecret
    ConveyedKey conveyedKey =
        await _conveyance.wrap(AtBytes.fromString(publishedPublicKey));
    String encryptedSymmetricKey = base64Encode(conveyedKey.cipher);

    EnrollVerbBuilder enrollVerbBuilder = EnrollVerbBuilder()
      ..appName = appName
      ..deviceName = deviceName
      ..encryptedAPKAMSymmetricKey = encryptedSymmetricKey // null on pq
      ..apkamPublicKey = signing.requireApkamPublicKey(pendingKeys).toString()
      ..signingAlgo = signing.signingAlgo
      ..otp = otp.value
      ..namespaces = Map.fromEntries(
          namespaces.map((p) => MapEntry(p.namespace, p.toString())))
      ..apkamKeysExpiryDuration = apkamKeysExpiryDuration;

    String? serverResponse =
        await _executeEnrollCommand(enrollVerbBuilder, atLookUp);
    var enrollJson = jsonDecode(serverResponse);
    var enrollmentIdFromServer = enrollJson[AtConstants.enrollmentId];
    var enrollStatus = getEnrollStatusFromString(enrollJson['status']);

    // populate legacy for persistence
    // enrollment id is needed
    pendingKeys
      ..enrollmentId = enrollJson[AtConstants.enrollmentId]
      ..apkamSymmetricKey = AtBytes(conveyedKey.sharedSecret);
    if (signing == ApkamSigningScheme.legacy) {
      // Under legacy the published key *is* the atsign's default encryption
      // public key, so the keyset can keep it. Under postQuantum it is an
      // X-Wing keypackage, which has no business in a legacy RSA field.
      pendingKeys.defaultEncryptionPublicKey =
          AtBytes.fromString(publishedPublicKey);
    }

    // The keys minted here are not yet persistable (no selfEncryptionKey until
    // the server hands one over at approval), so they travel on the response
    // for waitForApproval to complete and persist.
    // For post-quantum: is waiting for approval to unwrap their keys to add here.
    return PendingEnrollment(
      enrollmentIdFromServer,
      enrollStatus,
      atKeys: pendingKeys,
    );
  }

  @override
  Future<AtEnrollmentResponse> approve(
    Atsign atsign,
    AtKeysIo atKeysIo,
    String enrollmentId,
    AtBytes encryptedApkamSymmetricKey,
  ) async {
    // The approver's own encryption private key and self-encryption key, read
    // from its key source — the same way every other consumer gets keys across
    // a boundary.
    final atKeys = await atKeysIo.read(atsign);
    // ignore: deprecated_member_use_from_same_package
    final encryptionPrivateKey = atKeys.defaultEncryptionPrivateKey;
    // ignore: deprecated_member_use_from_same_package
    final selfEncryptionKey = atKeys.defaultSelfEncryptionKey;
    if (encryptionPrivateKey == null || selfEncryptionKey == null) {
      throw AtAuthenticationException(
          'The authentication keys are not initialized');
    }

    // Decrypt the encrypted APKAM symmetric key with the encryption private key
    // (RSA; wraps crypton's RSAPrivateKey.decrypt).
    AtBytes apkamSymmetricKey = AtBytes(await _conveyance.unwrap(
      encryptedApkamSymmetricKey,
      encryptionPrivateKey,
    ));

    String? encryptedDefaultEncryptionPrivateKey;
    //removable later, when doing migration we can do a soft left down
    // stop filling in the value for the server and eventually phase-out
    String? encryptedDefaultSelfEncryptionKey;
    InitialisationVector privateKeyIv = InitialisationVector.random(16);
    //legacy for aes
    InitialisationVector? selfKeyIv;

    switch (signing) {
      case ApkamSigningScheme.legacy:
        selfKeyIv = InitialisationVector.random(16);
        encryptedDefaultEncryptionPrivateKey = await _aesEncrypt(
            encryptionPrivateKey, apkamSymmetricKey.bytes, privateKeyIv);
        encryptedDefaultSelfEncryptionKey = await _aesEncrypt(
            selfEncryptionKey, apkamSymmetricKey.bytes, selfKeyIv);
      case ApkamSigningScheme.postQuantum:
        throw UnimplementedError(
            'not implemented yet, requires enroll:approve to hold the xwing public key on the at_server');
      // final bytes = await AesGcm256EncryptionAlgo().encrypt(
      //   encryptionPrivateKey.bytes,
      //   apkamSymmetricKey.bytes,
      //   iv: privateKeyIv,
      // );
      // encryptedDefaultEncryptionPrivateKey = base64Encode(bytes.toList());
    }

    EnrollVerbBuilder builder = EnrollVerbBuilder()
      ..operation = EnrollOperationEnum.approve
      ..enrollmentId = enrollmentId
      ..encryptedDefaultEncryptionPrivateKey =
          encryptedDefaultEncryptionPrivateKey
      ..encPrivateKeyIV = privateKeyIv.toString()
      ..encryptedDefaultSelfEncryptionKey = encryptedDefaultSelfEncryptionKey
      ..selfEncKeyIV = selfKeyIv.toString();

    String? enrollResponse = await atLookUp.executeVerb(builder);
    enrollResponse = enrollResponse?.replaceFirst(RegExp(r'^data:'), '');
    var enrollmentJsonMap = jsonDecode(enrollResponse!);
    AtEnrollmentResponse enrollmentResponse = AtEnrollmentResponse(
      enrollmentJsonMap['enrollmentId'],
      getEnrollStatusFromString(enrollmentJsonMap['status']),
    );
    return enrollmentResponse;
  }

  @override
  Future<AtEnrollmentResponse> deny(
    String enrollmentId,
  ) async {
    EnrollVerbBuilder denyEnrollmentBuilder = EnrollVerbBuilder()
      ..enrollmentId = enrollmentId
      ..operation = EnrollOperationEnum.deny;

    String? enrollResponse = await atLookUp
        .executeCommand(denyEnrollmentBuilder.buildCommand(), auth: true);

    enrollResponse = enrollResponse?.replaceFirst(RegExp(r'^data:'), '');
    var enrollmentJsonMap = jsonDecode(enrollResponse!);
    AtEnrollmentResponse enrollmentResponse = AtEnrollmentResponse(
      enrollmentJsonMap['enrollmentId'],
      getEnrollStatusFromString(enrollmentJsonMap['status']),
    );
    return enrollmentResponse;
  }

  @override
  Future<AtEnrollmentResponse> revoke(
    String enrollmentId, {
    bool force = false,
  }) async {
    EnrollVerbBuilder revokeEnrollVerbBuilder = EnrollVerbBuilder()
      ..enrollmentId = enrollmentId
      ..operation = EnrollOperationEnum.revoke
      ..force = force;

    String? enrollmentResponseStr = await atLookUp
        .executeCommand(revokeEnrollVerbBuilder.buildCommand(), auth: true);

    enrollmentResponseStr =
        enrollmentResponseStr?.replaceFirst(RegExp(r'^data:'), '');
    var enrollmentJsonMap = jsonDecode(enrollmentResponseStr!);
    AtEnrollmentResponse enrollmentResponse = AtEnrollmentResponse(
      enrollmentJsonMap['enrollmentId'],
      getEnrollStatusFromString(enrollmentJsonMap['status']),
    );
    return enrollmentResponse;
  }

  /// Waits for the atServer to approve `pending.enrollmentId`, then completes
  /// the APKAM handshake: the keys minted at submit time gain the material the
  /// server was holding, and the finished keyset is persisted through
  /// [atKeysIo].
  ///
  /// On return, `pending.atKeys` is complete and has been written to
  /// [atKeysIo], ready for client creation.
  @override
  Future<void> waitForApproval(
    Atsign atsign,
    AtRootDomain rootDomain,
    AtKeysIo atKeysIo,
    PendingEnrollment pending, {
    Duration retryInterval = AtEnrollment.defaultRetryInterval,
    bool logProgress = true,
    int maxRetries = AtEnrollment.defaultMaxRetries,
  }) async {
    // PKAM as the pending enrollment, not as whoever owns [atLookUp]: this is
    // the first connection that can sign with the APKAM key minted at submit.
    final enrollmentLookUp = _lookUpFactory(
      atsign,
      rootDomain,
      pending.atKeys,
      enrollmentId: pending.enrollmentId,
    );

    await _waitForPkamAuthSuccess(
      atsign,
      pending,
      enrollmentLookUp,
      retryInterval,
      logProgress: logProgress,
      maxRetries: maxRetries,
    );

    // post approval:
    // after pkam authentication is accepted

    // fetch the following keys from the atServer
    Map<String, dynamic> encPrivKeyResponse =
        await _getDefaultEncryptionPrivateKey(
      atsign,
      pending.enrollmentId,
    );

    Map<String, dynamic> selfEncKeyResponse = await _getSelfEncryptionKey(
      atsign,
      pending.enrollmentId,
    );

    // decrypting the following after fetching
    // selfEncryptionKey (encrypted via apkamSymmetricKey from the enrollment)
    // defaultEncryptionPrivateKey (encrypted via apkamSymmetricKey from the enrollment)

    // ignore: deprecated_member_use_from_same_package
    final apkamSymmetricKey = pending.atKeys.apkamSymmetricKey;
    if (apkamSymmetricKey == null) {
      throw AtAuthenticationException(
          'No apkam symmetric key available to decrypt the enrolled keys');
    }
    final apkamAes = AesCtrEncryptionAlgo(apkamSymmetricKey.bytes.length);
    Future<String> decryptUnderApkam(Map<String, dynamic> response) async =>
        utf8.decode(await apkamAes.decrypt(
            base64Decode(response['value']), apkamSymmetricKey.bytes,
            iv: InitialisationVector.fromBase64(response['iv'])));

    String decryptedSelfEncryptionKey =
        await decryptUnderApkam(selfEncKeyResponse);

    String decryptedDefaultEncryptionPrivateKey =
        await decryptUnderApkam(encPrivKeyResponse);

    // The keyset is only now complete: with a selfEncryptionKey it can finally
    // be persisted (FileAtKeysIo needs it to self-encrypt the APKAM fields).
    // ignore: deprecated_member_use_from_same_package
    pending.atKeys.defaultSelfEncryptionKey =
        AtBytes.fromString(decryptedSelfEncryptionKey);
    // ignore: deprecated_member_use_from_same_package
    pending.atKeys.defaultEncryptionPrivateKey =
        AtBytes.fromString(decryptedDefaultEncryptionPrivateKey);

    // Persist the completed keyset. `flush` for a durable store (it may be
    // upgrading an existing keyfile); `write` for anything else, which is a
    // create/replace.
    if (atKeysIo is WrittenAtKeysIo) {
      await atKeysIo.flush(atsign, pending.atKeys);
    } else {
      await atKeysIo.write(atsign, pending.atKeys);
    }
  }

  @override
  Future<List<ServerEnrollmentRequest>> list(
    List<EnrollmentStatus>? filters, {
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
    String rawResponse = (await atLookUp.executeCommand(
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
      List<ServerEnrollmentRequest> filtered = [];
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
        filtered.add(ServerEnrollmentRequest.fromServer(MapEntry(ek, e)));
      }
      return filtered;
    } else {
      throw Exception('Unexpected server response: $rawResponse');
    }
  }

  Future<String> _getPublicKey(
    AtLookUp lookup,
    String atsign,
  ) async {
    String name = switch (signing) {
      ApkamSigningScheme.legacy => KeyIds.publishedLegacyPublicKey,
      ApkamSigningScheme.postQuantum => KeyIds.publishedPqPublicKey,
    };
    LookupVerbBuilder builder = LookupVerbBuilder()
      ..atKey = (AtKey()
        ..key = name
        ..sharedBy = atsign);
    String? lookupResult = await lookup.executeVerb(builder);
    if (lookupResult == null || lookupResult.isEmpty) {
      throw AtEnrollmentException(
          'Unable to lookup encryption public key. Server response is null/empty');
    }
    var defaultEncryptionPublicKey =
        lookupResult.replaceFirst(RegExp(r'^data:'), '');

    return defaultEncryptionPublicKey;
  }

  Future<String> _aesEncrypt(
      AtBytes secret, Uint8List apkamAesKey, InitialisationVector iv) async {
    final aes = AesCtrEncryptionAlgo(apkamAesKey.length);
    return base64Encode(await aes.encrypt(
      secret.bytes,
      apkamAesKey,
      iv: iv,
    ));
  }

  Future<Map<String, dynamic>> _getDefaultEncryptionPrivateKey(
    String atsign,
    String enrollmentId,
  ) async {
    String cmd =
        "keys:get:keyName:$enrollmentId.default_enc_private_key.__manage$atsign\n";
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
    String atsign,
    String enrollmentId,
  ) async {
    String cmd =
        "keys:get:keyName:$enrollmentId.default_self_enc_key.__manage$atsign\n";
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
      EnrollVerbBuilder enrollVerbBuilder, AtLookUp atLookUp) async {
    var enrollResult =
        await atLookUp.executeCommand(enrollVerbBuilder.buildCommand());
    if (enrollResult == null ||
        enrollResult.isEmpty ||
        enrollResult.startsWith('error:')) {
      throw AtEnrollmentException(
          'Enrollment response from server: $enrollResult');
    }
    return enrollResult.replaceFirst(RegExp(r'^data:'), '');
  }

  /// Pkam auth will be retried until server approves/denies/expires the enrollment
  Future<void> _waitForPkamAuthSuccess(
    Atsign atsign,
    PendingEnrollment pending,
    AtLookUp enrollmentLookUp,
    Duration retryInterval, {
    bool logProgress = true,
    required int maxRetries,
  }) async {
    int retryAttempt = 0;
    PkamAuthenticator pkamAuthenticator = PkamAuthenticator();
    AtSignLogger logger = AtSignLogger('AtEnrollmentImpl');
    while (true) {
      retryAttempt++;
      logger.info('Attempting pkam auth');
      if (logProgress) {
        _addProgress('PKAM', 'attempting PKAM auth', ProgressEventType.info);
        await waitBriefly();
      }
      try {
        await pkamAuthenticator.authenticate(atsign, enrollmentLookUp,
            enrollmentId: pending.enrollmentId);
        if (logProgress) {
          _addProgress(
              'PKAM',
              'Enrollment has been approved'
                  ' (PKAM auth success)',
              ProgressEventType.success);
        }
        logger.info('Authentication succeeded - request was approved');
        return;
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
              'The enrollment: ${pending.enrollmentId} is denied');
        }
      } catch (e) {
        String message =
            'Exception occurred when authenticating the atsign caused by ${e.toString()}';
        if (retryAttempt > maxRetries) {
          message += ' Activation failed after $maxRetries attempts';
          logger.severe(message);
          _addProgress('PKAM', message, ProgressEventType.error);
          rethrow;
        }
        logger.severe(message);
      }
      logger.info('Will retry pkam in ${retryInterval.inSeconds} seconds');
      await Future.delayed(retryInterval); // Delay and retry
    }
  }

  static const _kSppRegex = r'[A-Za-z0-9]{6}';
  static const _defaultOtpExpiry = Duration(minutes: 5);

  @override
  Future<Otp> generateOtp({Duration expiry = _defaultOtpExpiry}) async {
    final command = 'otp:get:ttl:${expiry.inMilliseconds}\n';
    final response = await atLookUp.executeCommand(command, auth: true);
    if (response != null && response.startsWith('data:')) {
      final otp = response.substring(response.indexOf('data:') + 5).trim();
      return Otp.fromDuration(value: otp, duration: expiry);
    }
    throw AtEnrollmentException('Failed to generate OTP. Response: $response');
  }

  @override
  Future<Otp> setSpp(String spp, {Duration expiry = _defaultOtpExpiry}) async {
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
