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
import 'package:at_lookup/at_lookup.dart'
    show AtLookUpFactory, AtLookupMuxable, SecondaryAddressFinder;
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
  final AtLookupMuxable? _atLookUp;
  final AtLookUpFactory _lookUps;
  final SecondaryAddressFinder _secondaryAddressFinder;
  final AtEnrollment _enrollment = AtEnrollment.create();
  final AtSignLogger _logger;

  final Completer<void> _cancel = Completer<void>();
  Future<void>? _cancelling;

  /// The handshake connection [awaitApproval] built, while it waits; null for
  /// one the caller supplied.
  AtLookupMuxable? _ownHandshake;

  /// What the wait is doing, as it does it.
  Stream<ProgressEvent> get progress => _enrollment.progressStream;

  /// [lookUps] builds the connection the approval handshake runs on and the
  /// ones the client opened on the completed keys uses, each to the atServer
  /// [secondaryAddressFinder] finds; [atLookUp] is a connection for the
  /// handshake instead, for a caller that already holds one, and is left
  /// open.
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
    AtLookupMuxable? atLookUp,
    required AtLookUpFactory lookUps,
    required SecondaryAddressFinder secondaryAddressFinder,
  })  : _atLookUp = atLookUp,
        _lookUps = lookUps,
        _secondaryAddressFinder = secondaryAddressFinder,
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
    _refuseIfCancelled();
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
          // NOTE: a key source for the handshake alone, never a keyfile.
          // ignore: invalid_use_of_visible_for_testing_member
          atKeysIo: InMemoryAtKeysIo.holding(atSign, handshakeKeys),
          enrollmentId: enrollmentId),
      apkamSymmetricKeyResolver: keyExchangeMode == EnrollmentKeyExchangeMode.pq
          ? enrollmentApkamSymmetricKeyResolver(atSign)
          : null,
    );

    // The handshake's connection, built the way the application chose and
    // closed when it is done; a supplied one is the caller's to close.
    final handshake = _atLookUp ??
        _lookUps(
            atSign: atSign,
            rootDomain: rootDomain,
            authenticator: null,
            secondaryAddressFinder: _secondaryAddressFinder);
    if (_atLookUp == null) _ownHandshake = handshake;
    try {
      _refuseIfCancelled();
      await _enrollment.waitForApproval(response,
          retryInterval: retryInterval,
          maxRetries: maxRetries,
          atLookup: handshake,
          cancelled: _cancel.future);
    } on Exception catch (e) {
      if (_cancel.isCompleted) throw _cancelled();
      if (e is AtEnrollmentException && e.message.contains('denied')) {
        await _discard('denied');
      }
      rethrow;
    } finally {
      _ownHandshake = null;
      if (_atLookUp == null) await handshake.close();
    }

    // NOTE: the cancel check and the write are one update, so a cancel lands
    // either before the approval is written or after it.
    var written = false;
    await keys.update(atSign, (stored) {
      if (_cancel.isCompleted) return false;
      _completeFrom(stored, handshakeKeys);
      if (signingAlgo == SigningAlgoType.rsa2048) {
        _fileFlat(stored);
      } else {
        stored.activatePending(enrollmentId);
      }
      written = true;
      return true;
    });
    if (!written) throw _cancelled();
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
    required AtClientStorage storage,
    Duration retryInterval = AtEnrollment.defaultRetryInterval,
    int maxRetries = AtEnrollment.defaultMaxRetries,
    Duration connectBudget = AtConnection.defaultBudget,
  }) async {
    await awaitApproval(retryInterval: retryInterval, maxRetries: maxRetries);
    final client = await atSign.open(
        keys: keys,
        preference: preference,
        namespace: namespace,
        storage: storage,
        atLookUp: _atLookUp,
        lookUps: _lookUps,
        secondaryAddressFinder: _secondaryAddressFinder,
        connectBudget: connectBudget);
    if (_cancel.isCompleted) {
      await client.stop();
      throw _cancelled();
    }
    return client;
  }

  /// Ends the wait [client] or [awaitApproval] is in, which then throws
  /// [AtEnrollmentCancelledException]; this enrollment's pending keys leave
  /// [keys] as a denial's do.
  ///
  /// An approval already written to [keys] stays there, and a client that
  /// [client] has opened on it by then is stopped. A connection the caller
  /// supplied is left open. Nothing withdraws the request on the atServer.
  /// A second call does nothing more.
  Future<void> cancel() => _cancelling ??= _cancelOnce();

  Future<void> _cancelOnce() async {
    _cancel.complete();
    await _ownHandshake?.stop();
    await _discard('cancelled');
  }

  void _refuseIfCancelled() {
    if (_cancel.isCompleted) throw _cancelled();
  }

  AtEnrollmentCancelledException _cancelled() => AtEnrollmentCancelledException(
      'the wait for enrollment $enrollmentId of $atSign was cancelled');

  /// Copies onto [stored] what the approval released into [completed]: the
  /// atSign's encryption private key and self-encryption key, the symmetric
  /// key that carried them, and the flat spelling of the enrollment every
  /// published reader looks for.
  ///
  /// NOTE: this and [_fileFlat] write the legacy document shape on the
  /// approval's behalf, filling only what the store does not hold yet, so
  /// the flat fields are read directly here.
  void _completeFrom(AtKeys stored, AtKeys completed) {
    stored.fileLegacyMaterial(
      enrollmentId: enrollmentId,
      encryptionPublicKey: _unlessFiled(
          // ignore: deprecated_member_use
          stored.defaultEncryptionPublicKey,
          stored
              .keysForEnrollment(enrollmentId)
              .where((m) =>
                  m.role == CryptographicMaterialRole.publicEncryption &&
                  m.algorithm == CryptographicMaterialAlgorithm.rsa2048)
              .firstOrNull
              ?.bytes),
      encryptionPrivateKey: _unlessFiled(
          // ignore: deprecated_member_use
          stored.defaultEncryptionPrivateKey,
          // ignore: deprecated_member_use
          completed.defaultEncryptionPrivateKey),
      selfEncryptionKey: _unlessFiled(
          // ignore: deprecated_member_use
          stored.defaultSelfEncryptionKey,
          // ignore: deprecated_member_use
          completed.defaultSelfEncryptionKey),
      apkamSymmetricKey: _unlessFiled(
          // ignore: deprecated_member_use
          stored.apkamSymmetricKey,
          // ignore: deprecated_member_use
          completed.apkamSymmetricKey),
    );
  }

  /// Moves an rsa2048 keypair from the typed pending material into the flat
  /// APKAM fields, leaving the enrollment slot holding its snapshot and no
  /// keys: the shape a legacy enrollment has always had, and the one every
  /// published reader and the self-retrofit expect. Typed active material
  /// under the enrollment would read as a retrofit already done and block
  /// the upgrade a post-quantum posture asks for.
  void _fileFlat(AtKeys stored) {
    final materials = stored.keysForEnrollment(enrollmentId);
    AtBytes? bytesOf(CryptographicMaterialRole role) => materials
        .where((m) =>
            m.role == role &&
            m.algorithm == CryptographicMaterialAlgorithm.rsa2048)
        .firstOrNull
        ?.bytes;
    stored.fileLegacyMaterial(
      apkamPublicKey: _unlessFiled(
          // ignore: deprecated_member_use
          stored.apkamPublicKey,
          bytesOf(CryptographicMaterialRole.publicAuthentication)),
      apkamPrivateKey: _unlessFiled(
          // ignore: deprecated_member_use
          stored.apkamPrivateKey,
          bytesOf(CryptographicMaterialRole.privateAuthentication)),
    );
    final info = stored.enrollmentInfo(enrollmentId);
    stored.discardEnrollment(enrollmentId);
    stored.recordEnrollmentSnapshot(enrollmentId,
        namespaces: info?.namespaces,
        appName: info?.appName,
        deviceName: info?.deviceName);
  }

  /// [value] as [AtKeys.fileLegacyMaterial] takes it, or null to leave the
  /// field as it is when the store already holds [filed].
  static String? _unlessFiled(AtBytes? filed, AtBytes? value) =>
      filed == null ? value?.toString() : null;

  /// Removes this enrollment's pending keys from [keys], after the request
  /// was [why]: denied or cancelled.
  Future<void> _discard(String why) async {
    var removed = false;
    try {
      await keys.update(atSign, (stored) {
        if (!stored.pendingEnrollmentIds.contains(enrollmentId)) return false;
        stored
          ..discardEnrollment(enrollmentId)
          ..unfileLegacyEnrollment(enrollmentId);
        removed = true;
        return true;
      });
      if (removed) {
        _logger.info('enrollment $enrollmentId of $atSign was $why; its '
            'pending keys are removed');
      }
    } catch (e) {
      _logger.warning('enrollment $enrollmentId of $atSign was $why, and '
          'its pending keys could not be removed: $e');
    }
  }
}

/// The wait [PendingEnrollment.awaitApproval] or [PendingEnrollment.client]
/// was in was ended by [PendingEnrollment.cancel].
class AtEnrollmentCancelledException extends AtEnrollmentException {
  AtEnrollmentCancelledException(super.message);
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
