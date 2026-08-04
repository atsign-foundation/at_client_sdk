import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'package:at_auth/src/auth/apkam_signing.dart';
import 'package:at_auth/src/auth/pkam_authenticator.dart';
import 'package:at_auth/src/enroll/at_enrollment.dart';
import 'package:at_auth/src/enroll/models/at_enrollment_response.dart';
import 'package:at_auth/src/enroll/models/at_enrollment_request.dart';
import 'package:at_auth/src/enroll/models/enrollment_request_decision.dart';
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

/// A concrete implementation of [AtEnrollment] for managing enrollments.
///
/// This class provides functionality to submit and manage enrollment requests.
class AtEnrollmentImpl implements AtEnrollment {
  final AtSignLogger _logger = AtSignLogger('AtEnrollmentImpl');
  @override
  final AtLookUp atLookUp;

  @override
  final ApkamSigning signing;

  /// Substitutes the connection [waitForApproval] would otherwise build, so a
  /// test can exercise the flow without a network.
  @visibleForTesting
  AtLookUp Function(AtKeys keys, String enrollmentId)? lookUpOverride;

  AtEnrollmentImpl(this.atLookUp, {this.signing = ApkamSigning.legacy});

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
  Future<AtEnrollmentResponse> enroll(
      EnrollmentRequest enrollmentRequest) async {
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
    );
  }

  /// Handles the subsequent enrollment requests.
  Future<AtEnrollmentResponse> _handleAtEnrollmentRequest(
      AtEnrollmentRequest atEnrollmentRequest, AtLookUp atLookUp) async {
    // Generate required keys
    final apkamKeyPair = await RsaSigningAlgo().generateKeyPair();
    // The constructor argument is a length in BYTES: AES-256 is 32, not 256.
    final apkamSymmetricKey = AesCtrEncryptionAlgo(32).generateKey();
    // The wire form of the symmetric key is its base64 string, and that string
    // — not the raw bytes — is what gets RSA-wrapped for the approver.
    final apkamSymmetricKeyStr = base64Encode(apkamSymmetricKey);

    //Fetch required keys from atServer
    String defaultEncryptionPublicKey = await _getDefaultEncryptionPublicKey(
      atLookUp,
      atEnrollmentRequest.atsign,
    );

    // encrypting the following APKAM keys:
    // apkamSymmetricKey for the enroll verb
    String encryptedAPKAMSymmetricKey = base64Encode(RsaEncryptionAlgo()
        .encrypt(Uint8List.fromList(utf8.encode(apkamSymmetricKeyStr)),
            base64Decode(defaultEncryptionPublicKey)));

    EnrollVerbBuilder enrollVerbBuilder = EnrollVerbBuilder()
      ..appName = atEnrollmentRequest.appName
      ..deviceName = atEnrollmentRequest.deviceName
      ..encryptedAPKAMSymmetricKey = encryptedAPKAMSymmetricKey
      ..apkamPublicKey = base64Encode(apkamKeyPair.publicKey)
      ..otp = atEnrollmentRequest.otp
      ..namespaces = Map.fromEntries(atEnrollmentRequest.namespaces
          .map((p) => MapEntry(p.namespace, p.toString())))
      ..apkamKeysExpiryDuration = atEnrollmentRequest.apkamKeysExpiryDuration;

    String? serverResponse =
        await _executeEnrollCommand(enrollVerbBuilder, atLookUp);
    var enrollJson = jsonDecode(serverResponse);
    var enrollmentIdFromServer = enrollJson[AtConstants.enrollmentId];
    var enrollStatus = getEnrollStatusFromString(enrollJson['status']);

    AtKeys pendingKeys = AtKeys(atsign: atEnrollmentRequest.atsign)
      ..apkamPrivateKey = AtBytes(apkamKeyPair.secretKey)
      ..apkamPublicKey = AtBytes(apkamKeyPair.publicKey)
      ..apkamSymmetricKey = AtBytes(apkamSymmetricKey)
      ..enrollmentId = enrollJson[AtConstants.enrollmentId]
      ..defaultEncryptionPublicKey =
          AtBytes.fromString(defaultEncryptionPublicKey);

    // The keys minted here are not yet persistable (no selfEncryptionKey until
    // the server hands one over at approval), so they travel on the response
    // for waitForApproval to complete and persist.
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
    EnrollmentRequestDecision enrollmentRequestDecision,
  ) async {
    // The approver's own encryption private key and self-encryption key, read
    // from its key source — the same way every other consumer gets keys across
    // a boundary.
    final atKeys = await atKeysIo.read(atsign);
    // ignore: deprecated_member_use_from_same_package
    final encryptionPrivateKey = atKeys.defaultEncryptionPrivateKey;
    final encryptedAPKAMSymmetricKey =
        enrollmentRequestDecision.encryptedAPKAMSymmetricKey;
    // ignore: deprecated_member_use_from_same_package
    final selfEncryptionKey = atKeys.defaultSelfEncryptionKey;
    if (encryptionPrivateKey == null || selfEncryptionKey == null) {
      throw AtAuthenticationException(
          'The authentication keys are not initialized');
    }
    if (encryptedAPKAMSymmetricKey == null) {
      throw AtAuthenticationException(
          'The encryptedAPKAMSymmetricKey was never set');
    }
    // Decrypt the encrypted APKAM symmetric key with the encryption private key
    // (RSA; wraps crypton's RSAPrivateKey.decrypt).
    String apkamSymmetricKey = utf8.decode(RsaEncryptionAlgo()
        .decrypt(encryptedAPKAMSymmetricKey.bytes, encryptionPrivateKey.bytes));
    final apkamAesKey = base64Decode(apkamSymmetricKey);
    final apkamAes = AesCtrEncryptionAlgo(apkamAesKey.length);

    // Re-encrypt the encryption private key and self-encryption key under the
    // APKAM symmetric key (AES-256; byte-identical to the former
    // AtChops.encryptString(aes256) path: base64(AES.encrypt(utf8(data), iv))).
    InitialisationVector encryptionPrivateKeyIV =
        InitialisationVector.random(16);
    String encryptedDefaultEncryptionPrivateKey = base64Encode(
        await apkamAes.encrypt(
            Uint8List.fromList(utf8.encode(encryptionPrivateKey.toString())),
            apkamAesKey,
            iv: encryptionPrivateKeyIV));

    InitialisationVector selfEncryptionKeyIV = InitialisationVector.random(16);
    String encryptedDefaultSelfEncryptionKey = base64Encode(
        await apkamAes.encrypt(
            Uint8List.fromList(utf8.encode(selfEncryptionKey.toString())),
            apkamAesKey,
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
    );
    return enrollmentResponse;
  }

  @override
  Future<AtEnrollmentResponse> deny(
    EnrollmentRequestDecision enrollmentRequestDecision,
  ) async {
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
    );
    return enrollmentResponse;
  }

  @override
  Future<AtEnrollmentResponse> revoke(
    EnrollmentRequestDecision enrollmentRequestDecision,
  ) async {
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
    // ignore: deprecated_member_use_from_same_package
    final apkamPrivateKey = pending.atKeys.apkamPrivateKey;
    if (apkamPrivateKey == null) {
      throw AtAuthenticationException(
          'No apkam private key available to sign PKAM for the enrollment');
    }

    // PKAM as the pending enrollment, not as whoever owns [atLookUp]: this is
    // the first connection that can sign with the APKAM key minted at submit.
    final enrollmentLookUp =
        lookUpOverride?.call(pending.atKeys, pending.enrollmentId) ??
            buildAtLookUp(signing, atsign, rootDomain, pending.atKeys,
                enrollmentId: pending.enrollmentId);

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
