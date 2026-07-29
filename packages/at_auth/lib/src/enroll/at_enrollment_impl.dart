import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/src/auth/pkam_signers.dart';
import 'package:at_auth/src/enroll/at_enrollment.dart';
import 'package:at_auth/src/enroll/models/at_enrollment_response.dart';
import 'package:at_auth/src/enroll/models/at_enrollment_request.dart';
import 'package:at_auth/src/enroll/models/enrollment_request_decision.dart';
import 'package:at_auth/src/enroll/models/otp.dart';
import 'package:at_auth/src/auth/models/at_auth_session.dart';
import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/io/at_keys_io.dart';
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
      default:
        _addProgress('enrollment', 'Invalid Enrollment request received',
            ProgressEventType.error);
        throw InvalidRequestException('Invalid Enrollment request received');
    }
    _addProgress('enrollment', 'Enrollment request submitted',
        ProgressEventType.success);
    return atEnrollmentResponse;
  }

  /// Handles the FirstEnrollmentRequest, which is submitted when an atsign is first onboarded.
  Future<AtEnrollmentResponse> _handleFirstEnrollmentRequest(
      FirstEnrollmentRequest enrollmentRequest, AtLookUp atLookUp) async {
    EnrollVerbBuilder enrollVerbBuilder = EnrollVerbBuilder()
      ..appName = enrollmentRequest.appName
      ..deviceName = enrollmentRequest.deviceName;
    enrollVerbBuilder.apkamPublicKey = enrollmentRequest.apkamPublicKey;

    String? serverResponse =
        await _executeEnrollCommand(enrollVerbBuilder, atLookUp);
    var enrollJson = jsonDecode(serverResponse);
    var enrollmentIdFromServer = enrollJson[AtConstants.enrollmentId];
    var enrollStatus = getEnrollStatusFromString(enrollJson['status']);

    return AtEnrollmentResponse(
      enrollmentIdFromServer,
      enrollStatus,
      session: enrollmentRequest.session,
    );
  }

  /// Handles the subsequent enrollment requests.
  Future<AtEnrollmentResponse> _handleAtEnrollmentRequest(
      AtEnrollmentRequest atEnrollmentRequest, AtLookUp atLookUp) async {
    // Generate required keys
    RsaKeyPair apkamKeyPair = RsaKeyPair.generate();
    // AESKey.generate takes a length in BYTES: AES-256 is 32, not 256.
    SymmetricKey apkamSymmetricKey = AESKey.generate(32);

    //Fetch required keys from atServer
    String defaultEncryptionPublicKey = await _getDefaultEncryptionPublicKey(
      atLookUp,
      atEnrollmentRequest.atsign,
    );

    // encrypting the following APKAM keys:
    // apkamSymmetricKey for the enroll verb
    // RSA encrypt via at_chops (wraps crypton's RSAPublicKey.encrypt:
    // base64(encryptData(utf8(msg)))).
    String encryptedAPKAMSymmetricKey = base64Encode((RsaEncryptionAlgo()
          ..atPublicKey = AtPublicKey.fromString(defaultEncryptionPublicKey))
        .encrypt(utf8.encode(apkamSymmetricKey.key)));

    EnrollVerbBuilder enrollVerbBuilder = EnrollVerbBuilder()
      ..appName = atEnrollmentRequest.appName
      ..deviceName = atEnrollmentRequest.deviceName
      ..encryptedAPKAMSymmetricKey = encryptedAPKAMSymmetricKey
      ..apkamPublicKey = apkamKeyPair.atPublicKey.publicKey
      ..otp = atEnrollmentRequest.otp
      ..namespaces = atEnrollmentRequest.namespaces
      ..apkamKeysExpiryDuration = atEnrollmentRequest.apkamKeysExpiryDuration;

    String? serverResponse =
        await _executeEnrollCommand(enrollVerbBuilder, atLookUp);
    var enrollJson = jsonDecode(serverResponse);
    var enrollmentIdFromServer = enrollJson[AtConstants.enrollmentId];
    var enrollStatus = getEnrollStatusFromString(enrollJson['status']);

    AtKeys pendingKeys = AtKeys(atsign: atEnrollmentRequest.atsign)
      ..apkamPrivateKey =
          AtBytes.fromString(apkamKeyPair.atPrivateKey.privateKey)
      ..apkamPublicKey = AtBytes.fromString(apkamKeyPair.atPublicKey.publicKey)
      ..apkamSymmetricKey = AtBytes.fromString(apkamSymmetricKey.key)
      ..enrollmentId = enrollJson[AtConstants.enrollmentId]
      ..defaultEncryptionPublicKey =
          AtBytes.fromString(defaultEncryptionPublicKey);

    // Carry the requesting app's session forward so waitForApproval can persist
    // the completed keys into its atKeysIo and hand it back, along with the
    // keys minted here — they are not yet persistable (no selfEncryptionKey
    // until the server hands one over at approval), so they travel with the
    // response. The session is only fully valid after waitForApproval.
    return PendingEnrollment(
      enrollmentIdFromServer,
      enrollStatus,
      session: atEnrollmentRequest.session,
      keys: pendingKeys,
    );
  }

  @override
  Future<AtEnrollmentResponse> approve(
      EnrollmentRequestDecision enrollmentRequestDecision,
      AtLookUp atLookUp,
      AtAuthSession session) async {
    // The approver's own encryption private key and self-encryption key, read
    // from its session's key source — the same way every other consumer gets
    // keys across a boundary.
    final atKeys = await session.atKeysIo.read(session.atsign);
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
    String apkamSymmetricKey = utf8.decode((RsaEncryptionAlgo()
          ..atPrivateKey =
              AtPrivateKey.fromString(encryptionPrivateKey.toString()))
        .decrypt(base64Decode(
            enrollmentRequestDecision.encryptedAPKAMSymmetricKey)));
    final apkamAesKey = AESKey(apkamSymmetricKey);

    // Re-encrypt the encryption private key and self-encryption key under the
    // APKAM symmetric key (AES-256; byte-identical to the former
    // AtChops.encryptString(aes256) path: base64(AES.encrypt(utf8(data), iv))).
    InitialisationVector encryptionPrivateKeyIV =
        InitialisationVector.random(16);
    String encryptedDefaultEncryptionPrivateKey = base64Encode(
        await AESEncryptionAlgo(apkamAesKey).encrypt(
            Uint8List.fromList(utf8.encode(encryptionPrivateKey.toString())),
            iv: encryptionPrivateKeyIV));

    InitialisationVector selfEncryptionKeyIV = InitialisationVector.random(16);
    String encryptedDefaultSelfEncryptionKey = base64Encode(
        await AESEncryptionAlgo(apkamAesKey).encrypt(
            Uint8List.fromList(utf8.encode(selfEncryptionKey.toString())),
            iv: selfEncryptionKeyIV));

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
        getEnrollStatusFromString(enrollmentJsonMap['status']),
        session: session);
    return enrollmentResponse;
  }

  @override
  Future<AtEnrollmentResponse> deny(
      EnrollmentRequestDecision enrollmentRequestDecision,
      AtLookUp atLookUp,
      AtAuthSession session) async {
    EnrollVerbBuilder denyEnrollmentBuilder = EnrollVerbBuilder()
      ..enrollmentId = enrollmentRequestDecision.enrollmentId
      ..operation = enrollmentRequestDecision.enrollOperationEnum;

    String? enrollResponse = await atLookUp
        .executeCommand(denyEnrollmentBuilder.buildCommand(), auth: true);

    enrollResponse = enrollResponse?.replaceFirst(RegExp(r'^data:'), '');
    var enrollmentJsonMap = jsonDecode(enrollResponse!);
    AtEnrollmentResponse enrollmentResponse = AtEnrollmentResponse(
        enrollmentJsonMap['enrollmentId'],
        getEnrollStatusFromString(enrollmentJsonMap['status']),
        session: session);
    return enrollmentResponse;
  }

  @override
  Future<AtEnrollmentResponse> revoke(
      EnrollmentRequestDecision enrollmentRequestDecision,
      AtLookUp atLookUp,
      AtAuthSession session) async {
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
        getEnrollStatusFromString(enrollmentJsonMap['status']),
        session: session);
    return enrollmentResponse;
  }

  /// Waits for the atServer to approve `pending.enrollmentId`, then completes
  /// the APKAM handshake: the keys minted at submit time gain the material the
  /// server was holding, and the finished keyset is persisted through
  /// `pending.session`'s key destination.
  ///
  /// On return, `pending.keys` is complete and `pending.session` is a session
  /// carrying the approved enrollmentId and the authenticated connection —
  /// ready for `AtClientManager.fromAuthSession(...)`.
  @override
  Future<void> waitForApproval(
    PendingEnrollment pending, {
    Duration retryInterval = const Duration(seconds: 2),
    bool logProgress = true,
    int maxRetries = 15,
    AtLookupImpl? atLookup,
  }) async {
    final atsign = pending.session.atsign;
    final rootDomain = pending.session.rootDomain;

    atLookup ??= AtLookupImpl(
      atsign,
      rootDomain.rootDomain,
      rootDomain.rootPort,
    );

    // PKAM-authenticate the newly enrolled keys. at_lookup signs with the
    // strategy; RSA is the wired path.
    // ignore: deprecated_member_use_from_same_package
    final apkamPrivateKey = pending.keys.apkamPrivateKey;
    if (apkamPrivateKey == null) {
      throw AtAuthenticationException(
          'No apkam private key available to sign PKAM for the enrollment');
    }
    atLookup
      ..pkamSigner = RsaPkamSigner(apkamPrivateKey.toString())
      ..enrollmentId = pending.enrollmentId;

    await _waitForPkamAuthSuccess(
      atLookup,
      pending.enrollmentId,
      retryInterval,
      logProgress: logProgress,
      maxRetries: maxRetries,
    );

    // post approval:
    // after pkam authentication is accepted

    // fetch the following keys from the atServer
    Map<String, dynamic> encPrivKeyResponse =
        await _getDefaultEncryptionPrivateKey(
      atLookup,
      atsign,
      pending.enrollmentId,
    );

    Map<String, dynamic> selfEncKeyResponse = await _getSelfEncryptionKey(
      atLookup,
      atsign,
      pending.enrollmentId,
    );

    // decrypting the following after fetching
    // selfEncryptionKey (encrypted via apkamSymmetricKey from the enrollment)
    // defaultEncryptionPrivateKey (encrypted via apkamSymmetricKey from the enrollment)

    // ignore: deprecated_member_use_from_same_package
    final apkamSymmetricKey = pending.keys.apkamSymmetricKey;
    if (apkamSymmetricKey == null) {
      throw AtAuthenticationException(
          'No apkam symmetric key available to decrypt the enrolled keys');
    }
    final aesEncryption =
        StringAESEncryptor(AESKey(apkamSymmetricKey.toString()));

    String decryptedSelfEncryptionKey = aesEncryption.decrypt(
      selfEncKeyResponse['value'],
      iv: InitialisationVector.fromBase64(selfEncKeyResponse['iv']),
    );

    String decryptedDefaultEncryptionPrivateKey = aesEncryption.decrypt(
      encPrivKeyResponse['value'],
      iv: InitialisationVector.fromBase64(encPrivKeyResponse['iv']),
    );

    // The keyset is only now complete: with a selfEncryptionKey it can finally
    // be persisted (FileAtKeysIo needs it to self-encrypt the APKAM fields).
    // ignore: deprecated_member_use_from_same_package
    pending.keys.defaultSelfEncryptionKey =
        AtBytes.fromString(decryptedSelfEncryptionKey);
    // ignore: deprecated_member_use_from_same_package
    pending.keys.defaultEncryptionPrivateKey =
        AtBytes.fromString(decryptedDefaultEncryptionPrivateKey);

    // Persist the completed keyset to the session's destination, then hand back
    // a session that is actually usable: same atsign and key source, now with
    // the approved enrollmentId and the authenticated connection. `flush` for a
    // durable store (it may be upgrading an existing keyfile); `write` for
    // anything else, which is a create/replace.
    final keysIo = pending.session.atKeysIo;
    if (keysIo is WrittenAtKeysIo) {
      await keysIo.flush(atsign, pending.keys);
    } else {
      await keysIo.write(atsign, pending.keys);
    }
    pending.session = AtAuthSession(
      atsign: atsign,
      rootDomain: rootDomain,
      namespace: pending.session.namespace,
      atKeysIo: keysIo,
      enrollmentId: pending.enrollmentId,
      atLookUp: atLookup,
    );
  }

  @override
  Future<List<ServerEnrollmentRequest>> list(
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

  Future<String> _getDefaultEncryptionPublicKey(
      AtLookUp atLookupImpl, String atsign) async {
    LookupVerbBuilder builder = LookupVerbBuilder()
      ..atKey = (AtKey()
        ..key = 'publicKey'
        ..sharedBy = atsign);
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
      AtLookUp atLookUp, String atsign, String enrollmentId) async {
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
      AtLookUp atLookUp, String atsign, String enrollmentId) async {
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
            'Exception occurred when authenticating the atsign caused by ${e.toString()}';
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
