import 'dart:async';
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
import 'package:meta/meta.dart' show visibleForTesting;

import '../client/at_client_spec.dart' show AtClient;
import 'at_server_at_keys_io.dart';
import 'completion_due_record.dart' show CompletionDue;
import 'enrollment_gateway.dart' show ApkamKeyPair, apkamKeyPairFromSeed;
import 'enrollment_document_store.dart';
import 'enrollment_pointer_store.dart';
import 'passkey_session.dart';

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

/// How the encryption public key the atServer publishes for an atSign stands
/// against the one an @keys document holds.
enum PublishedEncryptionKey {
  /// The atServer publishes none.
  none,

  /// The atServer publishes the document's key, or the document holds none.
  same,

  /// The atServer publishes a key other than the document's.
  different,
}

/// A PKAM-authenticated enrollment on the atServer.
abstract class EnrollmentSession {
  String get enrollmentId;

  /// This enrollment's document, on this session's connection.
  EnrollmentDocumentStore get documents;

  /// Pointer writes on this session's connection; reads are anonymous.
  EnrollmentPointerStore get pointers;

  /// The @keys the activation that opened this session minted, as a document
  /// without any APKAM private key.
  ///
  /// Throws [StateError] for a session that was authenticated rather than
  /// activated.
  Future<Map<String, dynamic>> atKeys();

  /// How the encryption public key the atServer publishes stands against the
  /// one [atKeys] holds. A lookup that fails other than with the key not
  /// found throws.
  Future<PublishedEncryptionKey> publishedEncryptionKey(
      Map<String, dynamic> atKeys);

  /// Revokes every approved enrollment of the atSign other than this one.
  ///
  /// Throws when an approved enrollment other than this one is still listed
  /// afterwards; a revoke the atServer refuses for an enrollment that is no
  /// longer approved is not a failure. A revoke that fails with an
  /// `AtConnectException`, an `AtTimeoutException` or a plain `AtException`,
  /// as a lost connection or a timeout does, throws at once.
  Future<void> revokeOtherEnrollments();

  /// Completes the activation this session's enrollment was created by:
  /// publishes the encryption public key [atKeys] holds, replacing any that is
  /// published, then deletes the atSign's CRAM secret. When [atKeys] holds no
  /// encryption public key it publishes nothing and only deletes the CRAM
  /// secret.
  Future<void> completeActivation(Map<String, dynamic> atKeys);

  /// Writes [state] to this enrollment's completion-due record, which says
  /// that the completion of the activation that created it is due, replacing
  /// what the record held. From at_server p3.15.0 no other enrollment can
  /// read or write the record.
  Future<void> recordCompletionDue(CompletionDue state);

  /// What this enrollment's completion-due record says, or null when there is
  /// none and the completion is not due. Every failure other than the record
  /// being absent is thrown.
  Future<CompletionDue?> completionDue();

  /// Deletes this enrollment's completion-due record. One the atServer
  /// reports as not found counts as deleted.
  Future<void> clearCompletionDue();

  /// A client running as this enrollment, reading its @keys from [keysIo] and
  /// persisting every change through it. The client takes over this session's
  /// connection and stops it when the client stops; once it is opened, do not
  /// [close] the session. When opening throws, the opener may already have
  /// stopped a client it built, which releases the connection; the caller
  /// still closes the session, which is safe after such a stop.
  Future<AtClient> openClient(WrittenAtKeysIo keysIo);

  Future<void> close();
}

/// Enrolls and authenticates with an ML-DSA-65 APKAM key pair derived from a
/// passkey.
abstract class EnrollmentGateway {
  /// The device name every enrollment of this gateway carries.
  String get device;

  /// Authenticates [enrollmentId] with [apkamKeyPair].
  ///
  /// Throws [PkamRefusedException] when the atServer refuses it.
  Future<EnrollmentSession> authenticate(
      {required String atSign,
      required String enrollmentId,
      required ApkamKeyPair apkamKeyPair});

  /// Activates a fresh atSign with [cram], [apkamKeyPair] being its first
  /// enrollment's APKAM key, and returns the session authenticated as that
  /// enrollment.
  ///
  /// The activation is left to be completed with
  /// [EnrollmentSession.completeActivation]: the encryption public key is not
  /// published and the CRAM secret is not deleted.
  Future<EnrollmentSession> activate(
      {required String atSign,
      required ApkamKeyPair apkamKeyPair,
      required String cram});
}

const _apkamPrivateKey = 'aesPkamPrivateKey';
const _apkamPublicKey = 'aesPkamPublicKey';
const _encryptPublicKey = 'aesEncryptPublicKey';

/// The ids a device remembers for an atSign.
typedef _Hints = ({Uint8List credentialId, String enrollmentId});

/// Raised inside [PasskeyCustody.open] when the remembered ids led to no
/// credential or a refused PKAM.
class _StaleHints extends AtException {
  _StaleHints() : super('saved passkey hints are stale');
}

/// What an onboarding holds once its document and pointer are written.
typedef _Written = ({
  PasskeyVault vault,
  EnrollmentSession session,
  AtServerAtKeysIo store,
  Map<String, dynamic> atKeys,
});

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
      required this.setupLock,
      required this.setupLockPrefix,
      this.persistence,
      this.now = DateTime.now,
      this.retryDelay = const Duration(milliseconds: 250),
      required this.deriver,
      @visibleForTesting this.onKeyStore});

  final PasskeyPrf prf;
  final EnrollmentPointerReader pointerReader;
  final EnrollmentGateway gateway;
  final CredentialHintStore credentials;
  final EnrollmentIdStore enrollmentIds;
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

  /// Sees each key store this custody builds, before any I/O on it; tests use
  /// it to observe that a failed onboarding or login closes the store.
  @visibleForTesting
  final void Function(AtServerAtKeysIo store)? onKeyStore;

  /// The vault [deriver] derives from [secret], which is overwritten with
  /// zeroes once the vault is derived or the derivation fails.
  Future<PasskeyVault> _deriveAndWipe(PrfSecret secret, String atSign) async {
    try {
      return PasskeyVault(await deriver.derive(secret, atSign), atSign: atSign);
    } finally {
      secret.wipe();
    }
  }

  /// The APKAM key pair [vault]'s auth seed derives; the seed is overwritten
  /// with zeroes once it is derived.
  static Future<ApkamKeyPair> _pairOf(PasskeyVault vault) async {
    final pair = await vault.withAuthSeed(apkamKeyPairFromSeed);
    vault.wipeAuthSeed();
    return pair;
  }

  /// Onboards a fresh [atSign]: registers a passkey, activates the atSign
  /// with [cram] and the APKAM key pair derived from the passkey, and, as the
  /// new enrollment, records that the activation's completion is due, then
  /// writes the sealed @keys document and the pointer. Then it completes the
  /// activation: it deletes the CRAM secret and, once that delete answers,
  /// records that it is deleted, then revokes every other approved
  /// enrollment of the atSign, including any an interrupted onboarding left,
  /// then publishes the encryption public key, then deletes the record that
  /// the completion is due. It then remembers the passkey on the device and
  /// returns the session of the client running as the new enrollment.
  ///
  /// The whole flow holds [atSign]'s setup lock, so a second tab onboarding
  /// the same atSign waits for the first.
  ///
  /// An onboarding that fails before the CRAM secret is deleted is run again
  /// with the same [cram] and a new passkey. The passkey this call registered
  /// is reported to the platform as unknown when the failure comes before
  /// the activation is completed, and the failure is thrown without waiting
  /// for the platform to take the report; a failure while completing it, or
  /// after, reports nothing. Once the CRAM secret is deleted the atSign is
  /// onboarded, and a failure after that leaves [open] to log in: without
  /// saved hints it completes the activation while the completion is due,
  /// as [open] says, and it then saves the hints. Nothing is kept on the
  /// device until the CRAM secret is deleted. The failing stage's error is
  /// rethrown as it is, so it does not say whether the CRAM secret was
  /// deleted: a caller retries with [open] first, which finishes the
  /// onboarding when it succeeds. A [PasskeyLostException] from that [open]
  /// does not say whether the passkey filed a pointer, since a cancelled
  /// prompt throws it too, and onboarding again needs the CRAM secret still
  /// live.
  ///
  /// When the assertion after registering the new passkey fails or yields no
  /// usable PRF output, the new passkey is reported to the platform as
  /// unknown where the platform supports that, so it can drop the passkey.
  ///
  /// The PRF output is overwritten with zeroes once the vault is derived, and
  /// the auth seed once the APKAM key pair is derived from it. The returned
  /// [PasskeySession]'s client persists its @keys through an
  /// [AtServerAtKeysIo] sealed with the passkey's vault, and the session
  /// closes the store and the vault once the client stops. Everything is
  /// closed when this throws.
  ///
  /// A failed or cancelled prompt that registers the passkey writes nothing,
  /// and the same call can be made again.
  ///
  /// The setup lock is always taken, so this can also throw what the lock
  /// throws when it cannot be taken (for example a
  /// `SetupLockTimeoutException`).
  Future<PasskeySession> onboard(
      {required String atSign, required String cram}) async {
    final canonical = canonicalPasskeyAtSign(atSign);
    return await setupLock.run(setupLockName(setupLockPrefix, canonical),
        () async {
      final passkey = await prf.register(canonical,
          enrolledAt: now(), deviceName: gateway.device);
      final _Written written;
      try {
        written = await _activateAndWrite(canonical, cram, passkey.secret);
      } on Object {
        unawaited(prf.signalUnknownCredential(passkey.credentialId));
        rethrow;
      }
      return _complete(canonical, passkey.credentialId, written);
    });
  }

  /// Activates [canonical] with [cram], completion deferred, records that the
  /// completion is due, and writes the new enrollment's document and pointer.
  /// Everything it built is closed when it throws.
  Future<_Written> _activateAndWrite(
      String canonical, String cram, PrfSecret secret) async {
    final vault = await _deriveAndWipe(secret, canonical);
    EnrollmentSession? session;
    AtServerAtKeysIo? store;
    try {
      final pair = await _pairOf(vault);
      await _requestPersist();
      final activated = session = await gateway.activate(
          atSign: canonical, apkamKeyPair: pair, cram: cram);
      await activated.recordCompletionDue(CompletionDue.activated);
      final atKeys = {...await activated.atKeys()}..remove(_apkamPrivateKey);
      final keysIo = store = _keysIo(canonical, activated, vault, pair);
      await _putDocument(canonical, keysIo, atKeys);
      final pointer = await vault.seal(
          PasskeyRecordType.eid, {'enrollmentId': activated.enrollmentId});
      await activated.pointers
          .put(canonical, vault.lookupHex, pointer, ns: vault.ns);
      return (vault: vault, session: activated, store: keysIo, atKeys: atKeys);
    } on Object {
      store?.close();
      if (session != null) await _closeAfterFailedOpen(session);
      vault.close();
      rethrow;
    }
  }

  /// Completes the activation [written] holds, as [_completeActivation]
  /// does, remembers the passkey [credentialId] for [canonical] and opens the
  /// client. Everything is closed when it throws.
  Future<PasskeySession> _complete(
      String canonical, Uint8List credentialId, _Written written) async {
    final (:vault, :session, :store, :atKeys) = written;
    try {
      await _completeActivation(session, atKeys, onboarding: true);
      await _remember(canonical, credentialId, session.enrollmentId);
    } on Object {
      store.close();
      await _closeAfterFailedOpen(session);
      vault.close();
      rethrow;
    }
    try {
      return await _openSession(canonical, session, store, vault);
    } on Object {
      vault.close();
      rethrow;
    }
  }

  /// Completes the activation [session]'s enrollment was created by: deletes
  /// the atSign's CRAM secret, then, for an [onboarding], records that it is
  /// deleted, then revokes every other approved enrollment, then publishes
  /// the encryption public key [atKeys] holds, then deletes the record that
  /// the completion is due.
  static Future<void> _completeActivation(
      EnrollmentSession session, Map<String, dynamic> atKeys,
      {required bool onboarding}) async {
    // NOTE: only an onboarding may record the CRAM secret's deletion.
    await session.completeActivation(const {});
    if (onboarding) {
      await session.recordCompletionDue(CompletionDue.cramSecretDeleted);
    }
    await session.revokeOtherEnrollments();
    await session.completeActivation(atKeys);
    await session.clearCompletionDue();
  }

  /// Opens the client of [session] on [store], whose reads are served from
  /// memory once it holds the document, and returns it as a session over
  /// [vault]. Closes [store] and [session] when the open throws.
  Future<PasskeySession> _openSession(
      String canonical,
      EnrollmentSession session,
      AtServerAtKeysIo store,
      PasskeyVault vault) async {
    final AtClient client;
    try {
      await store.read(canonical);
      client = await session.openClient(store);
    } on Object {
      store.close();
      await _closeAfterFailedOpen(session);
      rethrow;
    }
    return PasskeySession(client, store, vault);
  }

  /// Opens [atSign]'s @keys and returns the session of the client running as
  /// its enrollment. A device that remembers [atSign]'s credential and
  /// enrollment returns without reading the pointer; any other (one id alone
  /// counts as none) asserts any discoverable passkey and finds the
  /// enrollment through the pointer, after waiting for [atSign]'s setup lock
  /// so that an onboarding in another tab finishes first.
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
  /// Every open refuses a document whose APKAM public key is not the
  /// passkey's, before anything is sent. Once the document is read, an open
  /// without remembered ids, including the retry without them, finishes the
  /// activation an onboarding may have left unfinished, before it remembers
  /// anything or opens the client. It reads the record that the completion is
  /// due before it looks at the published encryption public key:
  ///
  /// - When the record says the onboarding's own delete of the CRAM secret
  ///   answered, it deletes the atSign's CRAM secret, then revokes every
  ///   approved enrollment other than this one, then publishes the
  ///   document's key over any that is published, then deletes the record.
  /// - When it says only that the completion is due, it does the same when
  ///   no key or the document's key is published, and refuses another key
  ///   before anything is sent.
  /// - When there is no record, it revokes nothing: it publishes the
  ///   document's key when none is published, deletes the CRAM secret, which
  ///   is already gone, and refuses another key before anything is sent.
  ///
  /// An open never records the CRAM secret's deletion. An open that uses
  /// remembered ids reads no record and sends none of these, since a device
  /// remembers them only once the completion is done; it too refuses a
  /// published key other than the document's. When reading the record or
  /// finishing the activation fails, the open fails, and the next open tries
  /// again.
  ///
  /// The PRF output is overwritten with zeroes once the vault is derived, and
  /// the auth seed once the APKAM key pair is derived from it. The vault is
  /// closed when this throws. The returned [PasskeySession]'s client persists
  /// its @keys through an [AtServerAtKeysIo] sealed with the passkey's vault,
  /// and the session closes the store and the vault once the client stops.
  ///
  /// Throws [PasskeyLostException], [MissingAtKeysDocumentException],
  /// [PublicKeyMismatchException], a `PrfUnavailableException` when the
  /// passkey gives no usable PRF output, or what reading the completion-due
  /// record, revoking the other enrollments or finishing the activation
  /// throws; none leaves a session open or the device's hints rewritten.
  ///
  /// A [PasskeyLostException] whose cause is a `PasskeyCeremonyException`
  /// means the prompt failed, and the user may simply have cancelled it. This
  /// method never deletes or clears anything, and ends no enrollment, after a
  /// failed or cancelled prompt, so the app offers "Try again" (call [open]
  /// again; nothing changed) and "Reset" (a new enrollment, which needs an
  /// OTP and an approval and ends the old one), and never resets on its own.
  ///
  /// The setup lock is taken when the device has no hints and when remembered
  /// hints are stale, so the call can also throw what the lock throws when it
  /// cannot be taken (for example a `SetupLockTimeoutException`).
  Future<PasskeySession> open({required String atSign}) async {
    final canonical = canonicalPasskeyAtSign(atSign);
    final hints = await _savedHints(canonical);
    if (hints == null) return _lockedOpen(canonical, useSavedHints: true);
    try {
      return await _attempt(canonical, hints);
    } on _StaleHints {
      return _lockedOpen(canonical, useSavedHints: false);
    }
  }

  /// Opens [canonical] under its setup lock, so that an onboarding in another
  /// tab finishes first. Saved hints written while waiting are used unless
  /// [useSavedHints] is false; a refused set is replaced by one attempt
  /// without them.
  Future<PasskeySession> _lockedOpen(String canonical,
          {required bool useSavedHints}) =>
      setupLock.run(setupLockName(setupLockPrefix, canonical),
          () => _openHoldingLock(canonical, useSavedHints: useSavedHints));

  /// [_lockedOpen] for a caller that already holds [canonical]'s setup lock.
  Future<PasskeySession> _openHoldingLock(String canonical,
      {required bool useSavedHints}) async {
    final hints = useSavedHints ? await _savedHints(canonical) : null;
    if (hints == null) return _attempt(canonical, null);
    try {
      return await _attempt(canonical, hints);
    } on _StaleHints {
      return _attempt(canonical, null);
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
  /// hints either is a lost passkey. Only an open without hints finishes the
  /// activation, as [_finishActivation] does; one with hints refuses a
  /// published encryption key other than the document's.
  Future<PasskeySession> _attempt(String canonical, _Hints? hints) async {
    final PasskeyUnlock unlocked;
    try {
      unlocked = await prf.unlock(credentialId: hints?.credentialId);
    } on PasskeyCeremonyException catch (e) {
      // NOTE: a cancel throws the same exception as a ceremony that matched
      // no passkey, so it is retried once too, with a second prompt.
      if (hints != null) throw _StaleHints();
      throw PasskeyLostException(canonical, 'no passkey credential', cause: e);
    }
    final vault = await _deriveAndWipe(unlocked.secret, canonical);
    var handedOver = false;
    try {
      final enrollmentId = hints?.enrollmentId ??
          await _enrollmentIdFromPointer(canonical, vault);
      try {
        checkEnrollmentId(enrollmentId);
      } on ArgumentError {
        // NOTE: the message never carries the enrollment id.
        throw PasskeyLostException(canonical, 'malformed enrollment id');
      }

      final pair = await _pairOf(vault);
      final EnrollmentSession session;
      try {
        session = await gateway.authenticate(
            atSign: canonical, enrollmentId: enrollmentId, apkamKeyPair: pair);
      } on PkamRefusedException catch (e) {
        if (hints != null) throw _StaleHints();
        throw PasskeyLostException(canonical, 'PKAM refused', cause: e);
      }
      final store = _keysIo(canonical, session, vault, pair);
      try {
        final atKeys = await _restore(canonical, store, pair);
        if (hints == null) {
          await _finishActivation(session, atKeys);
        } else if (await session.publishedEncryptionKey(atKeys) ==
            PublishedEncryptionKey.different) {
          throw PublicKeyMismatchException();
        }
        await _remember(canonical, unlocked.credentialId, enrollmentId);
      } on Object {
        store.close();
        await _closeAfterFailedOpen(session);
        rethrow;
      }
      final opened = await _openSession(canonical, session, store, vault);
      handedOver = true;
      return opened;
    } finally {
      if (!handedOver) vault.close();
    }
  }

  /// Closes [session] after a failure; a failure of the close itself is
  /// logged and dropped, so it never replaces the error being propagated.
  static Future<void> _closeAfterFailedOpen(EnrollmentSession session) async {
    try {
      await session.close();
    } on Object catch (e) {
      _logger.severe('closing the session of enrollment '
          '${session.enrollmentId} failed: ${e.runtimeType}');
    }
  }

  /// The sealed @keys document of [session]'s enrollment of [atSign], which
  /// the custody writes and reads through and then hands to the client. The
  /// store reaches the vault only to seal and open that document.
  AtServerAtKeysIo _keysIo(String atSign, EnrollmentSession session,
      PasskeyVault vault, ApkamKeyPair pair) {
    final store = AtServerAtKeysIo(
        documents: session.documents,
        atSign: atSign,
        seal: (document) => vault.seal(PasskeyRecordType.atkeys, document),
        open: (record) => vault.open(PasskeyRecordType.atkeys, record),
        enrollmentId: session.enrollmentId,
        apkamKeyPair: pair);
    onKeyStore?.call(store);
    return store;
  }

  /// Creates the enrollment's document from [atKeys] through [store], which
  /// reads it back.
  ///
  /// A put or get that throws is retried, up to [_documentAttempts] times. A
  /// refusal is never retried: a read-back that differs, a candidate that
  /// drops stored material, or an existing document that is not these keys
  /// surfaces on its first occurrence. A document already there that holds
  /// everything these keys hold counts as written, and is never replaced.
  Future<void> _putDocument(String atSign, AtServerAtKeysIo store,
      Map<String, dynamic> atKeys) async {
    final candidate = AtKeys.fromJson(atKeys)..atsign = atSign.toAtsign();
    for (var attempt = 1;; attempt++) {
      try {
        try {
          await store.write(atSign, candidate);
        } on AtKeysFileOverwriteException {
          if (!await store.keepsAllOf(atSign, candidate)) rethrow;
        }
        return;
      } on AtServerAtKeysWriteException {
        rethrow;
      } on AtKeysAssuranceException {
        rethrow;
      } on AtKeysFileOverwriteException {
        rethrow;
      } on Object {
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

  /// Reads the enrollment's document through [store], which then serves the
  /// client's reads from memory, and returns it without the APKAM private
  /// key. Throws [PublicKeyMismatchException] when the document's APKAM
  /// public key is not the public key of [pair], the passkey's.
  Future<Map<String, dynamic>> _restore(
      String atSign, AtServerAtKeysIo store, ApkamKeyPair pair) async {
    final stored = await store.read(atSign);
    if (!_holdsApkamPublicKeyOf(stored, pair)) {
      throw PublicKeyMismatchException();
    }
    return stored.toJson()..remove(_apkamPrivateKey);
  }

  /// Finishes the activation [session]'s enrollment was created by, as far
  /// as it is unfinished, publishing the encryption public key [atKeys]
  /// holds, as [open] says. It reads the completion-due record before it
  /// looks at the published key, and refuses another published key with
  /// [PublicKeyMismatchException] before it sends any delete, revoke or
  /// publish, unless the record says the onboarding's own delete of the CRAM
  /// secret answered.
  static Future<void> _finishActivation(
      EnrollmentSession session, Map<String, dynamic> atKeys) async {
    final key = atKeys[_encryptPublicKey];
    final encryptionKey = {if (key is String) _encryptPublicKey: key};
    switch (await session.completionDue()) {
      case CompletionDue.cramSecretDeleted:
        return _completeActivation(session, encryptionKey, onboarding: false);
      case CompletionDue.activated:
        if (await session.publishedEncryptionKey(atKeys) ==
            PublishedEncryptionKey.different) {
          throw PublicKeyMismatchException();
        }
        return _completeActivation(session, encryptionKey, onboarding: false);
      case null:
        switch (await session.publishedEncryptionKey(atKeys)) {
          case PublishedEncryptionKey.none:
            await session.completeActivation(encryptionKey);
          case PublishedEncryptionKey.same:
            await session.completeActivation(const {});
          case PublishedEncryptionKey.different:
            throw PublicKeyMismatchException();
        }
    }
  }

  /// Whether the flat APKAM public key [stored] holds, if any, is the public
  /// key of [pair], which the passkey derives. A document without one does not
  /// mismatch. The encryption public key is the one the atServer publishes,
  /// checked by [EnrollmentSession.publishedEncryptionKey]. The document never
  /// holds this enrollment's typed APKAM public key (the store strips it), and
  /// no other public key has a second source to compare with.
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
      // NOTE: a refused or failed request must not fail the flow.
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
