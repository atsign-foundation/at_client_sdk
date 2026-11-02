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
/// active, and opens a client the caller owns; denial, or the request's
/// expiry, removes them and throws.
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

  /// Completed by [stop] or [cancel], which ends the wait.
  final Completer<void> _ended = Completer<void>();
  bool _abandoned = false;

  /// Whether the approval has been written to [keys], completing them.
  bool get approved => _approved;
  bool _approved = false;
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
  /// atServer, and [retryInterval] is the pause between polls. A denial, or
  /// the request's expiry, removes this enrollment from [keys] and throws
  /// [AtEnrollmentException].
  Future<void> awaitApproval({
    Duration retryInterval = AtEnrollment.defaultRetryInterval,
    int maxRetries = AtEnrollment.defaultMaxRetries,
  }) async {
    _refuseIfEnded();
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
      _refuseIfEnded();
      await _enrollment.waitForApproval(response,
          retryInterval: retryInterval,
          maxRetries: maxRetries,
          atLookup: handshake,
          cancelled: _ended.future);
    } on Exception catch (e) {
      if (_ended.isCompleted) throw _endedException();
      final decided = e is! AtEnrollmentException
          ? null
          : e.message.contains('denied')
              ? 'denied'
              : e.message.contains('error:AT0028')
                  ? 'expired'
                  : null;
      if (decided != null) {
        try {
          await _discard(decided);
        } catch (failure) {
          _logger.warning('enrollment $enrollmentId of $atSign was $decided, '
              'and its pending keys could not be removed: $failure');
        }
      }
      rethrow;
    } finally {
      _ownHandshake = null;
      if (_atLookUp == null) await handshake.close();
    }

    // NOTE: the check that the wait has not ended and the write are one
    // update, so a stop or cancel lands either before the approval is written
    // or after it.
    var written = false;
    await keys.update(atSign, (stored) {
      if (_ended.isCompleted) return false;
      _completeFrom(stored, handshakeKeys);
      if (signingAlgo == SigningAlgoType.rsa2048) {
        _fileFlat(stored);
      } else {
        stored.activatePending(enrollmentId);
      }
      written = true;
      return true;
    });
    if (!written) throw _endedException();
    _approved = true;
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
    if (_ended.isCompleted) {
      await client.stop();
      throw _endedException();
    }
    return client;
  }

  /// Ends the wait [client] or [awaitApproval] is in, which then throws
  /// [AtEnrollmentCancelledException]; this enrollment's pending keys leave
  /// [keys] as a denial's do. When [keys] cannot remove them, this throws what
  /// it threw, and a later call tries again.
  ///
  /// An approval already written to [keys] stays there, and a client that
  /// [client] has opened on it by then is stopped. A connection the caller
  /// supplied is left open while the wait runs; once [client] has opened a
  /// client on it, that client owns it, as `Atsign.open` does, so stopping
  /// the client stops the connection too. Nothing withdraws the request on
  /// the atServer. Tell the atSign's manager to deny it: an approval after
  /// cancel creates an enrollment nobody can use, which the manager would
  /// then revoke. A second call after one that succeeded does nothing more.
  Future<void> cancel() => _cancelling ??= _cancelOnce();

  /// Ends the wait [client] or [awaitApproval] is in, which then throws
  /// [StoppedException], and keeps this enrollment's pending keys in [keys], so
  /// `Atsign.resumeEnrollment` picks the request up again. Sends nothing.
  ///
  /// The handshake connection [awaitApproval] built is closed, and one the
  /// caller supplied is left open. An approval not yet written to [keys] is not
  /// written, and the next resume finds the request approved; a client that
  /// [client] has opened on an approval already written is stopped. A later
  /// [cancel] still abandons the request. Once the wait has ended, by this or
  /// by [cancel], this does nothing.
  Future<void> stop() async {
    if (_ended.isCompleted) return;
    _ended.complete();
    try {
      await _ownHandshake?.stop();
    } on Exception catch (e) {
      _logger.warning('Could not close the handshake connection of '
          'enrollment $enrollmentId of $atSign while stopping its wait: $e');
    }
  }

  Future<void> _cancelOnce() async {
    _abandoned = true;
    if (!_ended.isCompleted) _ended.complete();
    try {
      await _ownHandshake?.stop();
    } on Exception catch (e) {
      _logger.warning('Could not close the handshake connection of '
          'enrollment $enrollmentId of $atSign while cancelling its wait; its '
          'pending keys are removed all the same: $e');
    } finally {
      try {
        await _discard('cancelled');
      } catch (_) {
        _cancelling = null;
        rethrow;
      }
    }
  }

  void _refuseIfEnded() {
    if (_ended.isCompleted) throw _endedException();
  }

  /// What a wait that [cancel] or [stop] ended throws.
  Exception _endedException() {
    final wait = 'the wait for enrollment $enrollmentId of $atSign';
    if (_approved) {
      final after = 'after its approval was written; the approved keys stay '
          'in its key store';
      return _abandoned
          ? AtEnrollmentCancelledException('$wait was cancelled $after')
          : StoppedException('$wait was stopped $after, to open the atSign '
              'with');
    }
    return _abandoned
        ? AtEnrollmentCancelledException('$wait was cancelled')
        : StoppedException('$wait was stopped; the request stays in its key '
            'store, for resumeEnrollment');
  }

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
  /// was [why]: denied or cancelled. Throws what [keys] throws.
  Future<void> _discard(String why) async {
    var removed = false;
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
