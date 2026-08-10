import 'dart:convert';

import 'package:at_auth/src/auth/models/at_auth_session.dart';
import 'package:at_auth/src/enroll/enrollment_progress.dart';
import 'package:at_auth/src/enroll/models/at_enrollment_response.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/io/at_keys_io.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_utils/at_progress.dart';

/// The second half of an enrollment, from the submitted request to a usable
/// keyset.
///
/// A request is decided by somebody else, on their own schedule, so there is
/// nothing to await but the atServer's answer: PKAM authentication is retried
/// until it succeeds, which is both the approval signal and the earliest
/// moment this enrollment may read anything. What approval released — the
/// symmetric key, the encryption private key, the self encryption key — is
/// then collected and decrypted here, and persisted if the requesting app
/// supplied somewhere to put it.
class EnrollmentHandshake {
  final AtSignLogger _logger = AtSignLogger('EnrollmentHandshake');

  final EnrollmentProgress _progress;

  EnrollmentHandshake(this._progress);

  /// waits for Approval of the enrollmentId related to [enrollmentResponse]
  /// completes the end of the handshake for the APKAM flow
  ///
  /// returns [AtEnrollmentResponse] to intake additional keys provided after submission
  Future<void> waitForApproval(
    AtEnrollmentResponse enrollmentResponse, {
    required Duration retryInterval,
    required bool logProgress,
    required int maxRetries,
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
    while (true) {
      retryAttempt++;
      _logger.info('Attempting pkam auth');
      if (logProgress) {
        _progress.add('PKAM', 'attempting PKAM auth', ProgressEventType.info);
        await _waitBriefly();
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
          _logger.info('Pkam auth failed: ${e.message}');
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
          _logger.severe(message);
          _progress.add('PKAM', message, ProgressEventType.error);
          rethrow;
        }
        _logger.severe(message);
      }
      if (pkamAuthSucceeded) {
        if (logProgress) {
          _progress.add(
              'PKAM',
              'Enrollment has been approved'
                  ' (PKAM auth success)',
              ProgressEventType.success);
        }
        _logger.info('Authentication succeeded - request was approved');
        return;
      } else {
        if (logProgress) {
          _progress.add(
              'PKAM',
              'Auth failed, not yet approved.'
                  ' Will retry in ${retryInterval.inSeconds} seconds',
              ProgressEventType.info);
        }
        _logger.info('Will retry pkam in ${retryInterval.inSeconds} seconds');
        await Future.delayed(retryInterval); // Delay and retry
      }
    }
  }

  Future<void> _waitBriefly({int millis = 500}) async {
    await Future.delayed(Duration(milliseconds: millis));
  }
}
