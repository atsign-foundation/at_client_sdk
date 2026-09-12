import 'dart:async';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/lifecycle/at_connection.dart';
import 'package:at_client/src/lifecycle/atsign_lifecycle.dart';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/secret_sharing/enrollment_symmetric_key.dart'
    show enrollmentApkamSymmetricKeyResolver;
import 'package:at_client/src/storage/at_client_storage.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart' show AtLookUp;
import 'package:at_utils/at_logger.dart';
import 'package:at_utils/at_progress.dart';

/// An enrollment this device has submitted and the atSign's manager has not
/// yet decided.
///
/// The keys the submission minted are already in [keys], filed under
/// [enrollmentId] as `pending` material together with the app, device and
/// namespaces asked for, so a restart finds them with
/// `Atsign.resumeEnrollment` and picks up here. [client] waits for the
/// decision: approval completes the keys in the store, moves them to
/// active, and opens a client the caller owns; denial removes them and
/// throws.
class PendingEnrollment {
  final Atsign atSign;
  final String enrollmentId;
  final String app;
  final String device;
  final Map<String, String> namespaces;

  /// The store the submission wrote, which approval completes.
  final WrittenAtKeysIo keys;
  final AtRootDomain rootDomain;
  final SigningAlgoType signingAlgo;
  final EnrollmentKeyExchangeMode keyExchangeMode;
  final AtLookUp? _atLookUp;
  final AtEnrollment _enrollment = AtEnrollment.create();
  final AtSignLogger _logger;

  /// What the wait is doing, as it does it.
  Stream<ProgressEvent> get progress => _enrollment.progressStream;

  /// [atLookUp] is the connection the approval handshake runs on, for a
  /// caller that already holds one; with none, one is built from the atSign
  /// and root domain.
  PendingEnrollment({
    required this.atSign,
    required this.enrollmentId,
    required this.app,
    required this.device,
    required this.namespaces,
    required this.keys,
    required this.rootDomain,
    required this.signingAlgo,
    required this.keyExchangeMode,
    AtLookUp? atLookUp,
  })  : _atLookUp = atLookUp,
        _logger = AtSignLogger('PendingEnrollment ($atSign)');

  /// Waits for the manager's decision, and on approval completes the keys in
  /// [keys] and moves them to active.
  ///
  /// The wait for a decision has no bound: somebody decides on their own
  /// schedule. [maxRetries] budgets consecutive failures to reach the
  /// atServer, and [retryInterval] is the pause between polls. A denial
  /// removes this enrollment from [keys] and throws [AtEnrollmentException].
  Future<void> awaitApproval({
    Duration retryInterval = AtEnrollment.defaultRetryInterval,
    int maxRetries = AtEnrollment.defaultMaxRetries,
  }) async {
    final stored = await keys.read(atSign);
    if (!stored.pendingEnrollmentIds.contains(enrollmentId)) {
      throw AtEnrollmentException(
          '$atSign holds nothing pending for enrollment $enrollmentId: it was '
          'already completed, or removed after a denial');
    }

    // The handshake proves possession of the keypair filed at submission, so
    // it is handed a copy with that keypair live. The store itself moves only
    // once the atServer has said yes.
    final handshakeKeys = AtKeys.fromJson(stored.toJson())
      ..activatePending(enrollmentId);
    final response = AtEnrollmentResponse(
      enrollmentId,
      EnrollmentStatus.pending,
      atSign: atSign,
      rootDomain: rootDomain,
      atAuthKeys: handshakeKeys,
      session: AtAuthSession(
          atSign: atSign,
          rootDomain: rootDomain,
          atKeysIo: InMemoryAtKeysIo.holding(atSign, handshakeKeys),
          enrollmentId: enrollmentId),
      apkamSymmetricKeyResolver: keyExchangeMode == EnrollmentKeyExchangeMode.pq
          ? enrollmentApkamSymmetricKeyResolver(atSign)
          : null,
    );

    try {
      await _enrollment.waitForApproval(response,
          retryInterval: retryInterval,
          maxRetries: maxRetries,
          atLookup: _atLookUp);
    } on AtEnrollmentException catch (e) {
      if (e.message.contains('denied')) await _discard();
      rethrow;
    }

    await keys.update(atSign, (stored) {
      stored.activatePending(enrollmentId);
      _completeFrom(stored, handshakeKeys);
      return true;
    });
    _logger.info('enrollment $enrollmentId of $atSign is approved and its '
        'keys are complete');
  }

  /// Waits for the decision, then opens a client on the completed keys.
  ///
  /// The client is the caller's to stop. See `Atsign.open` for [preference],
  /// [namespace], [storage] and [connectBudget]; see [awaitApproval] for
  /// [retryInterval] and [maxRetries] and for what a denial does.
  Future<AtClient> client(
    AtClientPreference preference, {
    String? namespace,
    AtClientStorage? storage,
    Duration retryInterval = AtEnrollment.defaultRetryInterval,
    int maxRetries = AtEnrollment.defaultMaxRetries,
    Duration connectBudget = AtConnection.defaultBudget,
  }) async {
    await awaitApproval(retryInterval: retryInterval, maxRetries: maxRetries);
    return atSign.open(
        keys: keys,
        preference: preference,
        namespace: namespace,
        storage: storage,
        atLookUp: _atLookUp,
        connectBudget: connectBudget);
  }

  /// Copies onto [stored] what the approval released into [completed]: the
  /// atSign's encryption private key and self-encryption key, the symmetric
  /// key that carried them, and the flat spelling of the enrollment every
  /// published reader looks for. An rsa2048 keypair is copied into the flat
  /// APKAM fields too, so the completed keyfile reads as a legacy one would.
  void _completeFrom(AtKeys stored, AtKeys completed) {
    // ignore: deprecated_member_use
    stored.enrollmentId = enrollmentId;
    // ignore: deprecated_member_use
    stored.defaultEncryptionPublicKey ??= stored
        .keysForEnrollment(enrollmentId)
        .where((m) =>
            m.role == CryptographicMaterialRole.publicEncryption &&
            m.algorithm == CryptographicMaterialAlgorithm.rsa2048)
        .firstOrNull
        ?.bytes;
    // ignore: deprecated_member_use
    stored.defaultEncryptionPrivateKey ??=
        completed.defaultEncryptionPrivateKey;
    // ignore: deprecated_member_use
    stored.defaultSelfEncryptionKey ??= completed.defaultSelfEncryptionKey;
    // ignore: deprecated_member_use
    stored.apkamSymmetricKey ??= completed.apkamSymmetricKey;
    if (signingAlgo == SigningAlgoType.rsa2048) {
      final pair = stored.authenticationKeyPairFor(enrollmentId);
      if (pair != null) {
        // ignore: deprecated_member_use
        stored.apkamPublicKey ??= AtBytes.fromString(pair.publicKey);
        // ignore: deprecated_member_use
        stored.apkamPrivateKey ??= AtBytes.fromString(pair.privateKey);
      }
    }
  }

  Future<void> _discard() async {
    try {
      await keys.update(atSign, (stored) {
        if (!stored.enrollmentIds.contains(enrollmentId)) return false;
        stored.discardEnrollment(enrollmentId);
        // The flat fields the submission carried for this request go with
        // it, so the store reads as holding nothing for the atSign.
        // ignore: deprecated_member_use
        if (stored.enrollmentId == enrollmentId) stored.enrollmentId = null;
        if (stored.enrollmentIds.isEmpty &&
            !stored.holdsAuthenticationMaterial) {
          // ignore: deprecated_member_use
          stored.apkamSymmetricKey = null;
        }
        return true;
      });
      _logger.info('enrollment $enrollmentId of $atSign was denied; its '
          'pending keys are removed');
    } catch (e) {
      _logger.warning('enrollment $enrollmentId of $atSign was denied, and '
          'its pending keys could not be removed: $e');
    }
  }
}

/// `open` was asked to open a keyfile that holds nothing but an enrollment
/// awaiting approval, so there is no credential to authenticate with yet.
/// `Atsign.resumeEnrollment` is the way to pick it up.
class AtEnrollmentPendingException extends AtException {
  final String atSign;
  final List<String> pendingEnrollmentIds;

  AtEnrollmentPendingException(this.atSign, this.pendingEnrollmentIds)
      : super('$atSign holds no live credential, only the pending enrollment'
            '${pendingEnrollmentIds.length == 1 ? '' : 's'} '
            '${pendingEnrollmentIds.join(', ')}: resume it with '
            'resumeEnrollment rather than opening it');
}
