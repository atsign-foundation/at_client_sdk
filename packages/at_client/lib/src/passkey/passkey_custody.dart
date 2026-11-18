import 'dart:typed_data';

import 'package:at_auth/at_auth.dart'
    show
        AtKeys,
        AtKeysAssuranceException,
        AtKeysFileOverwriteException,
        WrittenAtKeysIo;
import 'package:at_auth/passkey.dart';
import 'package:at_commons/at_commons.dart'
    show AtException, InvalidAtSignException;
import 'package:at_commons/atsign.dart';
import 'package:at_utils/at_logger.dart' show AtSignLogger;

import '../client/at_client_spec.dart' show AtClient;
import '../lifecycle/atsign_lifecycle.dart' show scratchKeysIo;
import 'at_server_at_keys_io.dart';
import 'enrollment_gateway.dart' show ApkamKeyPair, apkamKeyPairFromSeed;
import 'enrollment_document_store.dart';
import 'enrollment_pointer_store.dart';
import 'pending_keys_journal.dart';

/// Asks the platform to keep this application's stored data rather than
/// evict it.
abstract class StoragePersistence {
  /// Whether the platform granted persistence.
  Future<bool> requestPersist();
}

/// Thrown when the atServer explicitly refuses PKAM for an enrollment (its
/// `pkam:` reply is an authentication failure; a server error, a throttled
/// reply or a lost connection is not this): it is no longer valid, or the key derived from the passkey is not that enrollment's key.
///
/// Terminal: an approver must `enroll:unrevoke` a revoked enrollment, or
/// `enroll:delete` it and approve a new one; the device cannot re-enroll
/// itself.
class PkamRefusedException extends AtException {
  PkamRefusedException(this.enrollmentId)
      : super('PKAM refused for enrollment $enrollmentId; an approver must '
            'enroll:unrevoke or delete it and approve a new enrollment');

  final String enrollmentId;

  @override
  String toString() => 'PkamRefusedException: PKAM refused for enrollment '
      '$enrollmentId; an approver must enroll:unrevoke or delete it and '
      'approve a new enrollment';
}

final _logger = AtSignLogger('passkeyCustody');

/// Thrown by [PasskeyCustody.open] when the passkey cannot open [atSign]'s
/// @keys: the ceremony returned no credential, the passkey's enrollment
/// pointer does not exist, or the atServer refused PKAM for the key derived
/// from it. The caller decides the screen; re-enrolling takes an OTP.
///
/// When [cause] is a `PasskeyCeremonyException`, the prompt failed, and the
/// user may simply have cancelled it: WebAuthn reports a cancel and a missing
/// passkey the same way. The library never deletes or clears anything, and
/// ends no enrollment, after a failed or cancelled prompt, so an app should
/// offer "Try again" (nothing changes; the user is prompted again) and "Reset"
/// (a new enrollment, which needs an OTP and an approval, and ends the old
/// one), and never reset on its own.
class PasskeyLostException extends AtException {
  PasskeyLostException(this.atSign, this.reason, {this.cause})
      : super('$reason for $atSign');

  final String atSign;
  final String reason;

  /// The failure that made the passkey count as lost, when there is one.
  final Object? cause;

  @override
  String toString() => 'PasskeyLostException: $reason for $atSign';
}

/// Thrown when an authenticated enrollment has no @keys document.
class MissingAtKeysDocumentException extends AtException {
  MissingAtKeysDocumentException(this.enrollmentId)
      : super('enrollment $enrollmentId has no @keys document');

  final String enrollmentId;

  @override
  String toString() => 'MissingAtKeysDocumentException: enrollment '
      '$enrollmentId has no @keys document';
}

/// Thrown when the restored public keys differ from the published ones.
class PublicKeyMismatchException extends AtException {
  PublicKeyMismatchException()
      : super('the restored keys do not match the published public keys');

  @override
  String toString() => 'PublicKeyMismatchException: the restored keys do not '
      'match the published public keys';
}

/// Thrown by [EnrollmentGateway.activate] when it fails after the CRAM was
/// spent and the activation enrollment's @keys were filed: [atKeys] holds the
/// minted @keys (without the APKAM private key, which the
/// passkey re-derives).
class ActivationUnfinishedException extends AtException {
  ActivationUnfinishedException(this.enrollmentId,
      {required Map<String, dynamic> atKeys, required this.cause})
      : _atKeys = atKeys,
        super('enrollment $enrollmentId did not finish activating');

  final String enrollmentId;

  Map<String, dynamic>? _atKeys;

  /// Hands over the activated @keys as a document and forgets them, so the
  /// exception no longer holds them. It holds plaintext keys: never log it.
  ///
  /// Throws [StateError] on a second call.
  Map<String, dynamic> takeAtKeys() {
    final keys = _atKeys;
    if (keys == null) {
      throw StateError('the @keys of enrollment $enrollmentId were taken');
    }
    _atKeys = null;
    return keys;
  }

  /// The failure that ended the activation.
  final Object cause;

  @override
  String toString() =>
      'ActivationUnfinishedException: enrollment $enrollmentId did not '
      'finish activating';
}

/// Thrown by [PasskeyCustody.onboard] when the atSign is activated but its
/// sealed document, pointer or device hints were not all written. A failure to
/// open the client after they are written is not this: [PasskeyCustody.onboard]
/// rethrows it and the atSign is ready for [PasskeyCustody.open].
///
/// [pending] holds the activated @keys and, when there is one, the open
/// session; the caller either resumes it or abandons it.
class OnboardingIncompleteException extends AtException {
  OnboardingIncompleteException(this.pending, this.cause)
      : super('onboarding of ${pending.atSign} was interrupted after '
            'activation');

  final PendingOnboarding pending;

  /// The failure that interrupted onboarding.
  final Object cause;

  @override
  String toString() => 'OnboardingIncompleteException: onboarding of '
      '${pending.atSign} was interrupted after activation';
}

/// An activated atSign whose custody records are not yet written.
///
/// One-shot: [resume] succeeds once, a failed client open ends the handle, and
/// neither it nor [abandon] can follow the other. Holds the passkey's vault
/// (its auth seed and sealer), the enrollment session if it has one and the
/// @keys, in memory, until [resume] succeeds or [abandon] completes. [abandon]
/// closes the vault, which overwrites the auth seed with zeroes and closes the
/// sealer; a successful [resume] hands the vault to the returned client, which
/// holds it for its session. The handle then drops its references to the
/// session and the @keys. Its [toString] names only the atSign.
///
/// A failed or cancelled passkey prompt while a handle is resumed or its
/// record is opened leaves the record and the handle as they were: the library
/// deletes nothing then, and the user can be prompted again.
class PendingOnboarding {
  PendingOnboarding._(this._custody, this.atSign, this._credentialId,
      this._vault, this._enrollmentId, this._session, this._atKeys,
      {bool finishActivation = false})
      : _finishActivation = finishActivation;

  final PasskeyCustody _custody;
  final String atSign;
  final Uint8List _credentialId;
  final PasskeyVault _vault;
  final String _enrollmentId;

  /// Whether [resume] first finishes the activation (publishes the encryption
  /// public key, deletes the CRAM secret), which an interrupted one may not
  /// have done.
  final bool _finishActivation;
  EnrollmentSession? _session;
  Map<String, dynamic>? _atKeys;

  /// The APKAM pair the auth seed derives, taken by the first [resume] before
  /// it wipes the seed, so a later one reuses it.
  ApkamKeyPair? _pair;
  var _finished = false;
  void Function()? _release;

  /// Runs [release] once, after [resume] succeeds, a failed open ends this
  /// handle or [abandon] completes: the point at which nothing else will use
  /// what this handle's custody holds. On a handle that has already finished
  /// it runs at once.
  void releaseWith(void Function() release) {
    if (_finished) {
      release();
    } else {
      _release = release;
    }
  }

  /// Writes the document, reads it back, writes the pointer, remembers the
  /// passkey, deletes the device's pending record and opens the client, under
  /// [atSign]'s setup lock. A failure
  /// to authenticate, write or remember leaves this handle usable; success
  /// finishes it and hands the session and the vault to the returned client.
  ///
  /// When the activation left no session, resume authenticates as the
  /// activation's enrollment first; a failed authentication propagates and
  /// leaves this handle ready for another [resume]. When the atServer refuses
  /// PKAM for that enrollment the failure is a [PasskeyLostException] whose
  /// cause is the [PkamRefusedException].
  ///
  /// A failure to open the client comes after the document, pointer and hints
  /// are written, so it ends this handle: the session and the vault are
  /// closed, the release runs and the open error propagates. Log in with
  /// [PasskeyCustody.open] instead.
  ///
  /// Throws [StateError] when this handle was already resumed or abandoned.
  Future<AtClient> resume() => _custody.setupLock
      .run(setupLockName(_custody.setupLockPrefix, atSign), _resumeHoldingLock);

  /// [resume] for a caller that already holds [atSign]'s setup lock.
  Future<AtClient> _resumeHoldingLock() async {
    if (_finished) {
      throw StateError('onboarding of $atSign was already resumed or '
          'abandoned');
    }
    // The seed is wiped below; the pair the client re-authenticates with is
    // derived while it is still there.
    final ApkamKeyPair pair =
        _pair ?? await _vault.withAuthSeed(apkamKeyPairFromSeed);
    _pair = pair;
    final EnrollmentSession session;
    try {
      session = _session ??
          await _vault.withAuthSeed((seed) => _custody.gateway.authenticate(
              atSign: atSign, enrollmentId: _enrollmentId, authSeed: seed));
    } on PkamRefusedException catch (e) {
      throw PasskeyLostException(atSign, 'PKAM refused', cause: e);
    }
    _session = session;
    // PKAM succeeded; nothing later needs the seed.
    _vault.wipeAuthSeed();
    final atKeys = _atKeys ?? await session.atKeys();
    if (_finishActivation) await session.completeActivation(atKeys);
    await _custody._publish(atSign, _vault, session, atKeys, pair);
    await _custody._remember(atSign, _credentialId, session.enrollmentId);
    final AtClient client;
    final keysIo = _custody._keysIo(session, _vault, pair);
    try {
      // Reads the document just published, so the client's reads never need
      // the atServer.
      await keysIo.read(atSign);
      client = await session.openClient(keysIo);
    } on Object {
      keysIo.close();
      try {
        await PasskeyCustody._closeAfterFailedOpen(session);
      } finally {
        _finish();
      }
      rethrow;
    }
    // Only now is the record spent: a failed open keeps it, so a retry
    // resumes it without a new passkey or CRAM.
    await _custody._deleteRecordOf(atSign, _enrollmentId);
    _finish(closeVault: false);
    return client;
  }

  /// Closes the session, drops this handle's reference to the @keys and closes
  /// the vault, which overwrites the auth seed with zeroes and closes the
  /// sealer. The device's pending record stays, so a later
  /// [PasskeyCustody.onboard] or [PasskeyCustody.open] resumes it. Runs under
  /// [atSign]'s setup lock, so it waits for a [resume] in flight. Does nothing after [resume] succeeded or a first [abandon].
  Future<void> abandon() => _custody.setupLock.run(
      setupLockName(_custody.setupLockPrefix, atSign), _abandonHoldingLock);

  Future<void> _abandonHoldingLock() async {
    if (_finished) return;
    final session = _session;
    _session = null;
    _atKeys = null;
    try {
      await session?.close();
    } finally {
      _finish();
    }
  }

  /// Ends this handle. The vault closes with it unless [closeVault] is false,
  /// when the client [resume] returned owns it.
  void _finish({bool closeVault = true}) {
    _finished = true;
    _session = null;
    _atKeys = null;
    _pair = null;
    if (closeVault) _vault.close();
    final release = _release;
    _release = null;
    release?.call();
  }

  @override
  String toString() => 'PendingOnboarding($atSign)';
}

/// A PKAM-authenticated enrollment on the atServer.
abstract class EnrollmentSession {
  String get enrollmentId;

  /// This enrollment's document, on this session's connection.
  EnrollmentDocumentStore get documents;

  /// Pointer writes on this session's connection; reads are anonymous.
  EnrollmentPointerStore get pointers;

  /// The @keys the atServer holds for this enrollment.
  Future<Map<String, dynamic>> atKeys();

  /// Whether the public keys of [atKeys] are the ones the atServer publishes.
  Future<bool> publicKeysMatch(Map<String, dynamic> atKeys);

  /// Finishes an activation, whatever of it already ran: publishes the
  /// encryption public key of [atKeys] when none is published, deletes the
  /// activation's CRAM secret, and does nothing for a step already done.
  ///
  /// Throws [PublicKeyMismatchException] when a different public key is
  /// already published; nothing is deleted then.
  Future<void> completeActivation(Map<String, dynamic> atKeys);

  /// A client running as this enrollment, reading its @keys from [keysIo] and
  /// persisting every change through it. The client takes over this session's
  /// connection and stops it when the client stops; once it is opened, do not
  /// [close] the session. When opening throws, the opener may already have
  /// stopped a client it built, which releases the connection and closes a
  /// key store handed to it; the caller still closes the session, which is
  /// safe after such a stop.
  Future<AtClient> openClient(WrittenAtKeysIo keysIo);

  Future<void> close();
}

/// Enrolls and authenticates with the ML-DSA-65 APKAM key derived from an
/// auth seed.
abstract class EnrollmentGateway {
  /// The device name every enrollment of this gateway carries.
  String get device;

  /// Authenticates [enrollmentId] with the key derived from [authSeed].
  ///
  /// Throws [PkamRefusedException] when the atServer refuses it.
  Future<EnrollmentSession> authenticate(
      {required String atSign,
      required String enrollmentId,
      required Uint8List authSeed});

  /// Onboards a fresh atSign: CRAM with [cram], activation with the key
  /// derived from [authSeed] as the APKAM key, then PKAM. Returns the
  /// authenticated session.
  ///
  /// The activation files its @keys in [keysIo] when one is given, so a caller
  /// sees them as they are written, before the CRAM secret is spent.
  Future<EnrollmentSession> activate(
      {required String atSign,
      required Uint8List authSeed,
      required String cram,
      WrittenAtKeysIo? keysIo});
}

const _apkamPrivateKey = 'aesPkamPrivateKey';
const _encryptPublicKey = 'aesEncryptPublicKey';
const _apkamPublicKey = 'aesPkamPublicKey';

/// The ids a device remembers for an atSign.
typedef _Hints = ({Uint8List credentialId, String enrollmentId});

/// Raised inside [PasskeyCustody.open] when the remembered ids led to no
/// credential or a refused PKAM.
class _StaleHints extends AtException {
  _StaleHints() : super('saved passkey hints are stale');
}

/// Raised inside [PasskeyCustody] when the device's pending record cannot be
/// opened: its passkey is gone or cancelled, or its contents are not ours.
class _PendingUnopenable extends AtException {
  _PendingUnopenable(this.cause)
      : super('the pending onboarding cannot be opened');

  final Object cause;
}

/// Raised inside [PasskeyCustody] when the atServer refused PKAM for the
/// enrollment a pending record describes: the record is of no further use.
/// [enrollmentId] is the enrollment the atServer refused.
class _PendingRefused extends AtException {
  _PendingRefused(this.enrollmentId)
      : super('the pending onboarding\'s enrollment is refused');

  final String enrollmentId;
}

const _documentAttempts = 3;

/// Onboards and opens the passkey-held @keys of an atSign.
///
/// The enrollment's APKAM key is derived from the passkey, so the document
/// holds no APKAM private key; the pointer names the enrollment for a device
/// that remembers nothing.
class PasskeyCustody {
  PasskeyCustody(
      {required this.prf,
      required this.pointerReader,
      required this.gateway,
      required this.credentials,
      required this.enrollmentIds,
      required this.pendingStore,
      required this.setupLock,
      required this.setupLockPrefix,
      this.persistence,
      this.now = DateTime.now,
      this.retryDelay = const Duration(milliseconds: 250),
      required this.deriver});

  final PasskeyPrf prf;
  final EnrollmentPointerReader pointerReader;
  final EnrollmentGateway gateway;
  final CredentialHintStore credentials;
  final EnrollmentIdStore enrollmentIds;

  /// Where an activation's sealed @keys are kept until the document is filed.
  final PendingOnboardingStore pendingStore;
  final SetupLock setupLock;

  /// The prefix of every setup lock name: the lock guarding [atSign]'s first
  /// setup is `<setupLockPrefix>:<atSign>`. Every tab of the origin must use
  /// the same prefix.
  final String setupLockPrefix;
  final StoragePersistence? persistence;

  /// The clock stamping each passkey registration.
  final DateTime Function() now;

  /// The pause between attempts to write a document.
  final Duration retryDelay;

  /// Derives the vault's keys from a passkey's PRF output.
  final PasskeyKeyDeriver deriver;

  /// The vault [deriver] derives from [secret], which is overwritten with
  /// zeroes once the vault is derived or the derivation fails.
  Future<PasskeyVault> _deriveAndWipe(PrfSecret secret, String atSign) async {
    try {
      return PasskeyVault(await deriver.derive(secret, atSign), atSign: atSign);
    } finally {
      secret.wipe();
    }
  }

  /// Onboards a fresh [atSign]: registers a passkey, activates the atSign
  /// with [cram] and the APKAM key derived from the passkey, then writes the
  /// document and pointer, and returns the client running as the new
  /// enrollment.
  ///
  /// The whole flow holds [atSign]'s setup lock, so a second tab onboarding
  /// the same atSign waits for the first; the passkey is registered before
  /// the CRAM is spent. The activation files its @keys through a journal that
  /// seals each write, without the APKAM private key, into [pendingStore]
  /// before the CRAM is spent, and that record is deleted once the document,
  /// pointer and hints are written. When [pendingStore] already holds a record
  /// for [atSign], an earlier onboarding was interrupted after activation: it
  /// is resumed with the passkey that sealed it, with no new registration and
  /// no CRAM. A record that passkey cannot open is a [PasskeyLostException]
  /// and stays, as does a record whose resume fails for any other reason (a
  /// connection error, a server error). When the atServer explicitly refuses
  /// PKAM for the record's enrollment, the record is deleted and this
  /// onboarding goes on with the new passkey and [cram]. The PRF output is overwritten with zeroes once the
  /// vault is derived. The vault's auth seed is overwritten with zeroes when
  /// onboarding fails before a handle exists, or when a handle from
  /// [OnboardingIncompleteException] is abandoned or resumed; until then
  /// that handle holds it. The returned client holds the vault for its session
  /// and persists its @keys through an [AtServerAtKeysIo] sealed with it; the
  /// seed is zeroed by then, and the sealer closes when the client stops.
  ///
  /// When the assertion after registering the new passkey fails or yields no
  /// usable PRF output, or activation fails before any record is sealed, the
  /// new passkey is reported to the platform as unknown where the platform
  /// supports that, so it can drop the passkey.
  ///
  /// When the client fails to open after the document, pointer and hints are
  /// written, the session and the vault are closed and that error propagates
  /// as it is; log in with [open].
  ///
  /// A failed or cancelled passkey prompt deletes and clears nothing and ends
  /// no enrollment. When the prompt that registers the passkey fails, nothing
  /// has been written and the same call can be made again. When the prompt that
  /// opens a pending record fails, the record is kept and the failure is a
  /// [PasskeyLostException] whose cause is a `PasskeyCeremonyException`: the
  /// user may simply have cancelled, so an app offers "Try again" and
  /// "Discard" ([discardPendingOnboarding]), and never discards on its own.
  ///
  /// The setup lock is always taken, so this can also throw what the lock
  /// throws when it cannot be taken (for example a
  /// `SetupLockTimeoutException`).
  Future<AtClient> onboard(
      {required String atSign, required String cram}) async {
    final canonical = canonicalPasskeyAtSign(atSign);
    return await setupLock.run(setupLockName(setupLockPrefix, canonical),
        () async {
      final record = await pendingStore.get(canonical);
      if (record != null) {
        try {
          return await _resumeRecord(canonical, record);
        } on _PendingUnopenable catch (e) {
          throw PasskeyLostException(
              canonical,
              'an earlier onboarding is pending and its passkey '
              'cannot open it',
              cause: e.cause);
        } on _PendingRefused catch (e) {
          // The atServer refused the record's enrollment: it can never be
          // resumed, so this onboarding starts afresh with the new CRAM.
          await _deleteRecordOf(canonical, e.enrollmentId);
        }
      }
      final passkey = await prf.register(canonical,
          enrolledAt: now(), deviceName: gateway.device);
      final vault = await _deriveAndWipe(passkey.secret, canonical);
      var handedOver = false;
      try {
        await _requestPersist();
        final journal = PendingKeysJournal(
            inner: scratchKeysIo(),
            atSign: canonical,
            credentialId: passkey.credentialId,
            vault: vault,
            store: pendingStore);
        final EnrollmentSession session;
        try {
          session = await vault.withAuthSeed((seed) => gateway.activate(
              atSign: canonical, authSeed: seed, cram: cram, keysIo: journal));
        } on ActivationUnfinishedException catch (e) {
          handedOver = true;
          throw OnboardingIncompleteException(
              PendingOnboarding._(this, canonical, passkey.credentialId, vault,
                  e.enrollmentId, null, e.takeAtKeys(),
                  finishActivation: true),
              e.cause);
        } on Object {
          // Activation failed. With no record sealed the passkey belongs to
          // no onboarding, so the platform is told it is unknown.
          if (await pendingStore.get(canonical) == null) {
            await prf.signalUnknownCredential(passkey.credentialId);
          }
          rethrow;
        }
        final pending = PendingOnboarding._(this, canonical,
            passkey.credentialId, vault, session.enrollmentId, session, null);
        handedOver = true;
        try {
          return await pending._resumeHoldingLock();
        } on Object catch (e) {
          // A failed client open ends the handle: nothing is left to resume.
          if (pending._finished) rethrow;
          throw OnboardingIncompleteException(pending, e);
        }
      } finally {
        if (!handedOver) vault.close();
      }
    });
  }

  /// Deletes [atSign]'s pending onboarding record, if there is one, under the
  /// atSign's setup lock (the one [onboard], [open] and a resume take, so it
  /// waits for them). It runs no ceremony and makes no atServer call, and a
  /// second call, or one with no record, does nothing.
  ///
  /// This is the user's "Discard" choice after a pending record would not
  /// open. If no @keys document was written, the record held the only copy of
  /// the new keys, so discarding it destroys them and the atSign must be reset
  /// with a new CRAM. Never call it automatically, and never after a failed or
  /// cancelled prompt on the app's own account: offer "Try again" and let the
  /// user choose.
  ///
  /// Throws what the setup lock throws when it cannot be taken (for example a
  /// `SetupLockTimeoutException`).
  Future<void> discardPendingOnboarding(String atSign) async {
    final canonical = canonicalPasskeyAtSign(atSign);
    return await setupLock.run(setupLockName(setupLockPrefix, canonical),
        () => pendingStore.delete(canonical));
  }

  /// Opens [atSign]'s @keys and returns the client running as its
  /// enrollment. A device that remembers [atSign]'s credential and enrollment
  /// returns without reading the pointer; any other (one id alone counts as
  /// none) asserts any discoverable passkey and finds the enrollment through
  /// the pointer, after waiting for [atSign]'s setup lock so that an
  /// onboarding in another tab finishes first.
  ///
  /// When the remembered ceremony yields no credential, or the atServer
  /// refuses PKAM for the remembered enrollment, the open is retried once, as
  /// a device with no hints, under the setup lock; a success replaces the
  /// remembered ids. The ceremony's exception does not tell a cancel from a
  /// deleted passkey, so a cancel is retried too, and a second failure is a
  /// lost passkey.
  ///
  /// A remembered or pointed enrollment id outside the id alphabet is a lost
  /// passkey, refused before any PKAM.
  ///
  /// The PRF output is overwritten with zeroes once the vault is derived, and
  /// the vault, with its auth seed, is closed when this throws. The returned
  /// client holds the vault for its session, persists its @keys through an
  /// [AtServerAtKeysIo] sealed with it. The seed is zeroed once PKAM succeeds,
  /// and the sealer closes when the client stops.
  ///
  /// Throws [PasskeyLostException], [MissingAtKeysDocumentException] or
  /// [PublicKeyMismatchException]; none leaves a session open or the device's
  /// hints rewritten.
  ///
  /// A [PasskeyLostException] whose cause is a `PasskeyCeremonyException`
  /// means the prompt failed, and the user may simply have cancelled it. This
  /// method never deletes or clears anything, and ends no enrollment, after a
  /// failed or cancelled prompt, so the app offers "Try again" (call [open]
  /// again; nothing changed) and "Reset" (a new enrollment through [onboard],
  /// which needs an OTP and an approval and ends the old one), and never
  /// resets on its own.
  ///
  /// The setup lock is taken when a pending onboarding record exists, when the
  /// device has no hints, and when remembered hints are stale, so the call can
  /// also throw what the lock throws when it cannot be taken (for example a
  /// `SetupLockTimeoutException`). A pending record is resumed first; one that
  /// cannot be opened does not stop a login that can succeed, and stays. Only when the atServer explicitly refuses PKAM for
  /// the record's enrollment is it deleted, and the login goes on. A resume
  /// that fails for another reason (a connection error) propagates and keeps
  /// the record.
  Future<AtClient> open({required String atSign}) async {
    final canonical = canonicalPasskeyAtSign(atSign);
    if (await pendingStore.get(canonical) != null) {
      return setupLock.run(setupLockName(setupLockPrefix, canonical), () async {
        final record = await pendingStore.get(canonical);
        if (record != null) {
          try {
            return await _resumeRecord(canonical, record);
          } on _PendingUnopenable {
            // A record this device cannot open does not stop a login that
            // can; the login deletes it when it proves the record obsolete.
          } on _PendingRefused catch (e) {
            // The atServer refused the record's enrollment: it can never be
            // resumed, so it is dropped and the login goes on.
            await _deleteRecordOf(canonical, e.enrollmentId);
          }
        }
        return _openHoldingLock(canonical, useSavedHints: true);
      });
    }
    final hints = await _savedHints(canonical);
    if (hints == null) return _lockedOpen(canonical, useSavedHints: true);
    try {
      return await _attempt(canonical, hints, holdsLock: false);
    } on _StaleHints {
      // The device's hints no longer lead anywhere; the retry replaces them.
    }
    return _lockedOpen(canonical, useSavedHints: false);
  }

  /// Opens [canonical] under its setup lock, so that an onboarding in another
  /// tab finishes first. Saved hints written while waiting are used unless
  /// [useSavedHints] is false; a refused set is replaced by one attempt
  /// without them.
  Future<AtClient> _lockedOpen(String canonical,
          {required bool useSavedHints}) =>
      setupLock.run(setupLockName(setupLockPrefix, canonical),
          () => _openHoldingLock(canonical, useSavedHints: useSavedHints));

  /// [_lockedOpen] for a caller that already holds [canonical]'s setup lock.
  Future<AtClient> _openHoldingLock(String canonical,
      {required bool useSavedHints}) async {
    final hints = useSavedHints ? await _savedHints(canonical) : null;
    if (hints == null) return _attempt(canonical, null, holdsLock: true);
    try {
      return await _attempt(canonical, hints, holdsLock: true);
    } on _StaleHints {
      return _attempt(canonical, null, holdsLock: true);
    }
  }

  /// Resumes the onboarding [record] holds, under [canonical]'s setup lock:
  /// opens it with the passkey that sealed it, then finishes the activation
  /// and writes the document, pointer and hints as [PendingOnboarding.resume]
  /// does. Throws [_PendingUnopenable] when the record cannot be opened and
  /// [_PendingRefused] when the atServer refuses its enrollment; any
  /// other failure closes the vault and session and propagates, and the record
  /// stays for the next attempt.
  Future<AtClient> _resumeRecord(
      String canonical, PendingOnboardingRecord record) async {
    final PasskeyUnlock unlocked;
    try {
      unlocked = await prf.unlock(credentialId: record.credentialId);
    } on PasskeyCeremonyException catch (e) {
      throw _PendingUnopenable(e);
    } on PrfUnavailableException catch (e) {
      // The record's passkey gave no usable PRF output; another may.
      throw _PendingUnopenable(e);
    }
    final vault = await _deriveAndWipe(unlocked.secret, canonical);
    final String enrollmentId;
    final Map<String, dynamic> atKeys;
    try {
      final sealed = await vault.open(PasskeyRecordType.pending, record.sealed);
      final id = sealed['enrollmentId'];
      final keys = sealed['atKeys'];
      if (id is! String || keys is! Map<String, dynamic>) {
        throw UnsupportedPasskeyRecordException(
            'pending record holds no enrollmentId and @keys');
      }
      checkEnrollmentId(id);
      enrollmentId = id;
      atKeys = keys;
    } on Object catch (e) {
      vault.close();
      throw _PendingUnopenable(e);
    }
    final pending = PendingOnboarding._(this, canonical, unlocked.credentialId,
        vault, enrollmentId, null, atKeys,
        finishActivation: true);
    try {
      return await pending._resumeHoldingLock();
    } on Object catch (e) {
      if (!pending._finished) await pending._abandonHoldingLock();
      final cause = e is PasskeyLostException ? e.cause : null;
      if (cause is PkamRefusedException) {
        throw _PendingRefused(cause.enrollmentId);
      }
      rethrow;
    }
  }

  /// The credential and enrollment ids this device remembers for [canonical],
  /// or null unless it remembers both: one of the two alone, as a write that
  /// stopped halfway leaves, counts as no hints.
  Future<_Hints?> _savedHints(String canonical) async {
    final credentialId = await credentials.credentialId(canonical);
    final enrollmentId = await enrollmentIds.enrollmentId(canonical);
    if (credentialId == null || enrollmentId == null) return null;
    return (credentialId: credentialId, enrollmentId: enrollmentId);
  }

  /// One open of [canonical]. With [hints] the ceremony is narrowed to the
  /// remembered credential and the remembered enrollment is authenticated; a
  /// ceremony that yields no credential, or a PKAM the atServer refuses, then
  /// throws [_StaleHints] so the caller can try again without them. Without
  /// hints either is a lost passkey. A login that [holdsLock] also deletes a
  /// pending record it proves obsolete.
  Future<AtClient> _attempt(String canonical, _Hints? hints,
      {required bool holdsLock}) async {
    final PasskeyUnlock unlocked;
    try {
      unlocked = await prf.unlock(credentialId: hints?.credentialId);
    } on PasskeyCeremonyException catch (e) {
      // A cancelled ceremony and one that matched no passkey are the same
      // exception, so a cancel is retried once too, with a second prompt.
      if (hints != null) throw _StaleHints();
      throw PasskeyLostException(canonical, 'no passkey credential', cause: e);
    }
    final vault = await _deriveAndWipe(unlocked.secret, canonical);
    var clientOwnsVault = false;
    try {
      final enrollmentId = hints?.enrollmentId ??
          await _enrollmentIdFromPointer(canonical, vault);
      try {
        checkEnrollmentId(enrollmentId);
      } on ArgumentError {
        // Not the id: it came from the device or the server, and is not ours
        // to echo.
        throw PasskeyLostException(canonical, 'malformed enrollment id');
      }

      final pair = await vault.withAuthSeed(apkamKeyPairFromSeed);
      final EnrollmentSession session;
      try {
        session = await vault.withAuthSeed((seed) => gateway.authenticate(
            atSign: canonical, enrollmentId: enrollmentId, authSeed: seed));
      } on PkamRefusedException catch (e) {
        if (hints != null) throw _StaleHints();
        throw PasskeyLostException(canonical, 'PKAM refused', cause: e);
      }
      vault.wipeAuthSeed();
      try {
        final restored =
            await _restore(canonical, enrollmentId, vault, session, pair);
        await _remember(canonical, unlocked.credentialId, enrollmentId);
        final client = await session
            .openClient(_keysIo(session, vault, pair, restored: restored));
        clientOwnsVault = true;
        if (holdsLock) {
          await _dropObsoleteRecord(canonical, enrollmentId, restored);
        }
        return client;
      } on Object {
        await _closeAfterFailedOpen(session);
        rethrow;
      }
    } finally {
      if (!clientOwnsVault) vault.close();
    }
  }

  /// Deletes [canonical]'s pending record when it is the record of
  /// [enrollmentId]: the enrollment whose client just opened, or which the
  /// atServer refused. A record another enrollment replaced meanwhile stays.
  /// A failing store is logged and does not fail the caller (an open would
  /// leave the client running with no caller); a later open or resume clears
  /// the record. Runs only under [canonical]'s setup lock.
  Future<void> _deleteRecordOf(String canonical, String enrollmentId) async {
    try {
      final record = await pendingStore.get(canonical);
      if (record?.enrollmentId == enrollmentId) {
        await pendingStore.delete(canonical);
      }
    } on Object catch (e) {
      _logger.warning('deleting the pending record of enrollment '
          '$enrollmentId failed: ${e.runtimeType}');
    }
  }

  /// Deletes [canonical]'s pending record when it is for the keys [restored]
  /// holds, matched by encryption public key: the onboarding it describes was
  /// finished some other way. A record for other keys, or one that names no
  /// key, stays. A failing store is logged and does not fail the open. Runs
  /// only under [canonical]'s setup lock.
  Future<void> _dropObsoleteRecord(
      String canonical, String enrollmentId, AtKeys restored) async {
    try {
      final record = await pendingStore.get(canonical);
      final key = record?.encryptionPublicKey;
      if (key != null && key == restored.toJson()[_encryptPublicKey]) {
        await _deleteRecordOf(canonical, enrollmentId);
      }
    } on Object catch (e) {
      // The record is cleared by a later open.
      _logger.warning('dropping the obsolete pending record of enrollment '
          '$enrollmentId failed: ${e.runtimeType}');
    }
  }

  /// Closes [session] after a failure; a failure of the close itself is
  /// logged and dropped, so it never replaces the error being propagated.
  static Future<void> _closeAfterFailedOpen(EnrollmentSession session) async {
    try {
      await session.close();
    } on Object catch (e) {
      // The caller rethrows the failure that led here.
      _logger.severe('closing the session of enrollment '
          '${session.enrollmentId} failed: ${e.runtimeType}');
    }
  }

  /// The sealed @keys document of [session]'s enrollment, which a client
  /// persists its changes through.
  ///
  /// With [restored], the store's first read returns those keys instead of
  /// reading the document again.
  AtServerAtKeysIo _keysIo(
          EnrollmentSession session, PasskeyVault vault, ApkamKeyPair pair,
          {AtKeys? restored}) =>
      AtServerAtKeysIo(
          documents: session.documents,
          vault: vault,
          enrollmentId: session.enrollmentId,
          apkamKeyPair: pair,
          closedByClient: true,
          restored: restored);

  /// Writes the document and pointer for [session]'s enrollment: the @keys
  /// without the APKAM private key.
  Future<void> _publish(
    String atSign,
    PasskeyVault vault,
    EnrollmentSession session,
    Map<String, dynamic> atKeys,
    ApkamKeyPair pair,
  ) async {
    final held = {...atKeys}..remove(_apkamPrivateKey);
    await _putDocument(atSign, vault, session, held, pair);
    final pointer = await vault
        .seal(PasskeyRecordType.eid, {'enrollmentId': session.enrollmentId});
    await session.pointers.put(atSign, vault.lookupHex, pointer, ns: vault.ns);
  }

  /// Creates the enrollment's document from [atKeys] and reads it back.
  ///
  /// A put or get that throws is retried on the same session, up to
  /// [_documentAttempts] times, each on a fresh store. A refusal is never
  /// retried: a read-back that differs, a candidate that drops stored
  /// material, or an existing document that is not these keys surfaces on its
  /// first occurrence. A document already there that holds everything these
  /// keys hold counts as written, and is never replaced.
  Future<void> _putDocument(
      String atSign,
      PasskeyVault vault,
      EnrollmentSession session,
      Map<String, dynamic> atKeys,
      ApkamKeyPair pair) async {
    final candidate = AtKeys.fromJson(atKeys)..atsign = atSign.toAtsign();
    for (var attempt = 1;; attempt++) {
      final io = AtServerAtKeysIo(
          documents: session.documents,
          vault: vault,
          enrollmentId: session.enrollmentId,
          apkamKeyPair: pair);
      try {
        try {
          await io.write(atSign, candidate);
        } on AtKeysFileOverwriteException {
          if (!await io.keepsAllOf(atSign, candidate)) rethrow;
        }
        return;
      } on AtServerAtKeysWriteException {
        rethrow;
      } on AtKeysAssuranceException {
        rethrow;
      } on AtKeysFileOverwriteException {
        rethrow;
      } on Object {
        // A failed put or get is retried; the last attempt's error propagates.
        if (attempt == _documentAttempts) rethrow;
        await Future<void>.delayed(retryDelay);
      }
    }
  }

  Future<String> _enrollmentIdFromPointer(
          String atSign, PasskeyVault vault) async =>
      await _pointedEnrollmentId(atSign, vault) ??
      (throw PasskeyLostException(atSign, 'no enrollment pointer'));

  Future<String?> _pointedEnrollmentId(
      String atSign, PasskeyVault vault) async {
    final record =
        await pointerReader.get(atSign, vault.lookupHex, ns: vault.ns);
    if (record == null) return null;
    final pointer = await vault.open(PasskeyRecordType.eid, record);
    return switch (pointer) {
      {'enrollmentId': String id} => id,
      _ => throw UnsupportedPasskeyRecordException(
          'enrollment pointer holds no enrollmentId'),
    };
  }

  /// Reads the enrollment's document, checks its public keys against the
  /// published ones and returns it, so the client starts on the keys read
  /// here rather than reading them again.
  Future<AtKeys> _restore(String atSign, String enrollmentId,
      PasskeyVault vault, EnrollmentSession session, ApkamKeyPair pair) async {
    final stored = await AtServerAtKeysIo(
            documents: session.documents,
            vault: vault,
            enrollmentId: enrollmentId,
            apkamKeyPair: pair)
        .read(atSign);
    final atKeys = stored.toJson()..remove(_apkamPrivateKey);
    if (!await session.publicKeysMatch(atKeys) ||
        !_holdsApkamPublicKeyOf(stored, pair)) {
      throw PublicKeyMismatchException();
    }
    return stored;
  }

  /// Whether the flat APKAM public key [stored] holds, if any, is the public
  /// key of [pair], which the passkey derives. A document without one does not
  /// mismatch. The encryption public key is the one the atServer publishes,
  /// checked by [EnrollmentSession.publicKeysMatch]. The document never holds
  /// this enrollment's typed APKAM public key (the store strips it), and no
  /// other public key has a second source to compare with.
  static bool _holdsApkamPublicKeyOf(AtKeys stored, ApkamKeyPair pair) {
    final flat = stored.toJson()[_apkamPublicKey];
    return flat == null || flat == pair.publicKey;
  }

  /// Remembers the passkey and enrollment of [atSign]: both ids in one write
  /// when the hint stores are one [PasskeyHintStore], otherwise one put each.
  Future<void> _remember(
      String atSign, Uint8List credentialId, String enrollmentId) async {
    final combined = credentials;
    if (combined is PasskeyHintStore && identical(combined, enrollmentIds)) {
      await combined.putHint(atSign, credentialId, enrollmentId);
    } else {
      await credentials.putCredentialId(atSign, credentialId);
      await enrollmentIds.putEnrollmentId(atSign, enrollmentId);
    }
    await _requestPersist();
  }

  /// Asks the browser not to evict this origin's storage; a refused or failed
  /// request does not fail the flow.
  Future<void> _requestPersist() async {
    try {
      await persistence?.requestPersist();
    } on Object {
      // Persistence is a request, not a requirement.
    }
  }
}

/// [atSign] as a canonical atSign for a passkey entry point: exactly one
/// leading `@` and no other, validated like any atSign. The passkey, its
/// records and its setup lock are all keyed by that one spelling, so a bare
/// `alice` or a `left@right` is refused rather than normalised.
///
/// Throws [InvalidAtSignException] otherwise.
Atsign canonicalPasskeyAtSign(String atSign) {
  if (!atSign.startsWith('@') || atSign.indexOf('@', 1) != -1) {
    throw InvalidAtSignException(
        'a passkey atSign has one leading "@" and no other: $atSign');
  }
  return atSign.toAtsign();
}
