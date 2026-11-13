import 'dart:typed_data';

import 'package:at_commons/atsign.dart';

import '../keys/key_bytes_store.dart';
import '../keys/passkey_port.dart' show PasskeyCeremonyException;
import '../keys/passkey_record.dart';
import '../keys/passkey_record_keys.dart';
import 'enrollment_document_store.dart';
import 'enrollment_pointer_store.dart';
import 'setup_lock.dart';

/// Asks the browser not to evict this origin's storage.
abstract interface class StoragePersistence {
  /// Whether the browser granted persistence.
  Future<bool> requestPersist();
}

/// Thrown when the atServer refuses PKAM for an enrollment: it is revoked, or
/// the key derived from the passkey is not that enrollment's key.
///
/// Terminal: an approver must `enroll:delete` the enrollment and approve a
/// new one; the device cannot re-enroll itself.
class PkamRefusedException implements Exception {
  PkamRefusedException(this.enrollmentId);

  final String enrollmentId;

  @override
  String toString() => 'PkamRefusedException: PKAM refused for enrollment '
      '$enrollmentId; an approver must delete it and approve a new enrollment';
}

/// Thrown by [PasskeyCustody.open] when the passkey cannot open [atSign]'s
/// @keys: the ceremony returned no credential, the passkey's enrollment
/// pointer does not exist, or the atServer refused PKAM for the key derived
/// from it. The caller decides the screen; re-enrolling takes an OTP.
class PasskeyLostException implements Exception {
  PasskeyLostException(this.atSign, this.reason, {this.cause});

  final String atSign;
  final String reason;

  /// The failure that made the passkey count as lost, when there is one.
  final Object? cause;

  @override
  String toString() => 'PasskeyLostException: $reason for $atSign';
}

/// Thrown when an authenticated enrollment has no @keys document.
class MissingAtKeysDocumentException implements Exception {
  MissingAtKeysDocumentException(this.enrollmentId);

  final String enrollmentId;

  @override
  String toString() => 'MissingAtKeysDocumentException: enrollment '
      '$enrollmentId has no @keys document';
}

/// Thrown when the restored public keys differ from the published ones.
class PublicKeyMismatchException implements Exception {
  @override
  String toString() => 'PublicKeyMismatchException: the restored keys do not '
      'match the published public keys';
}

/// Thrown by [PasskeyCustody.rotate] when the new pointer does not read back;
/// the old enrollment and pointer are untouched.
class RotationAbortedException implements Exception {
  @override
  String toString() => 'RotationAbortedException: the new enrollment pointer '
      'did not read back';
}

/// A PKAM-authenticated enrollment on the atServer.
abstract interface class EnrollmentSession {
  String get enrollmentId;

  /// This enrollment's document, on this session's connection.
  EnrollmentDocumentStore get documents;

  /// Pointer writes on this session's connection; reads are anonymous.
  EnrollmentPointerStore get pointers;

  /// The @keys the atServer holds for this enrollment.
  Future<Map<String, dynamic>> atKeys();

  /// Whether the public keys of [atKeys] are the ones the atServer publishes.
  Future<bool> publicKeysMatch(Map<String, dynamic> atKeys);

  /// Revokes [enrollmentId].
  Future<void> revoke(String enrollmentId);

  Future<void> close();
}

/// Enrolls and authenticates with the ML-DSA-65 APKAM key derived from an
/// auth seed.
abstract interface class EnrollmentGateway {
  /// Enrolls the key derived from [authSeed] with [otp] and returns the
  /// approved, authenticated session.
  Future<EnrollmentSession> enroll(
      {required String atSign,
      required Uint8List authSeed,
      required String otp});

  /// Authenticates [enrollmentId] with the key derived from [authSeed].
  ///
  /// Throws [PkamRefusedException] when the atServer refuses it.
  Future<EnrollmentSession> authenticate(
      {required String atSign,
      required String enrollmentId,
      required Uint8List authSeed});
}

/// An open custody session: the restored @keys and the authenticated
/// enrollment holding them.
class CustodySession {
  CustodySession._(
      {required this.atSign,
      required this.enrollmentId,
      required this.atKeys,
      required this.session,
      required this.lookupHex,
      required this.credentialId});

  final String atSign;
  final String enrollmentId;
  final Map<String, dynamic> atKeys;
  final EnrollmentSession session;

  /// The name of this passkey's enrollment pointer.
  final String lookupHex;
  final Uint8List credentialId;

  Future<void> close() => session.close();
}

const _apkamPrivateKey = 'aesPkamPrivateKey';

/// Enrolls, opens and rotates the passkey-held @keys of an atSign.
///
/// The enrollment's APKAM key is derived from the passkey, so the document
/// holds no APKAM private key; the pointer names the enrollment for a device
/// that remembers nothing.
class PasskeyCustody {
  PasskeyCustody(
      {required this.kek,
      required this.pointerReader,
      required this.gateway,
      required this.credentials,
      required this.enrollmentIds,
      required this.setupLock,
      this.persistence});

  final PasskeyKek kek;
  final EnrollmentPointerReader pointerReader;
  final EnrollmentGateway gateway;
  final CredentialHintStore credentials;
  final EnrollmentIdStore enrollmentIds;
  final SetupLock setupLock;
  final StoragePersistence? persistence;

  /// Enrolls a passkey for [atSign] with an approver-issued [otp], then writes
  /// its document and pointer. [existingPasskey] asserts the device's passkey instead of
  /// registering one.
  ///
  /// The whole flow holds [atSign]'s setup lock, so a second tab enrolling the
  /// same atSign waits for the first.
  Future<CustodySession> enroll(
      {required String atSign,
      required String otp,
      bool existingPasskey = false}) {
    final canonical = atSign.toAtsign();
    return setupLock.run(setupLockName(canonical), () async {
      final PasskeyRegistration passkey;
      if (existingPasskey) {
        final unlocked = await kek.unlock(
            credentialId: await credentials.credentialId(canonical));
        passkey =
            (credentialId: unlocked.credentialId, secret: unlocked.secret);
      } else {
        passkey = await kek.register(canonical);
      }
      final keys = await RecordKeys.derive(passkey.secret, canonical);
      final session = await gateway.enroll(
          atSign: canonical, authSeed: keys.authSeed, otp: otp);
      final published = await _publish(canonical, passkey.credentialId, keys,
          session, await session.atKeys());
      await _remember(canonical, passkey.credentialId, published.enrollmentId);
      return published;
    });
  }

  /// Opens [atSign]'s @keys. A device that remembers [atSign]'s credential
  /// and enrollment returns without reading the pointer; any other asserts
  /// any discoverable passkey and finds the enrollment through the pointer.
  ///
  /// Throws [PasskeyLostException], [MissingAtKeysDocumentException] or
  /// [PublicKeyMismatchException]; none leaves a session open or the device's
  /// hints rewritten.
  Future<CustodySession> open({required String atSign}) async {
    final canonical = atSign.toAtsign();
    final hintedCredential = await credentials.credentialId(canonical);
    final hintedEnrollment = await enrollmentIds.enrollmentId(canonical);

    final PasskeyUnlock unlocked;
    try {
      unlocked = await kek.unlock(credentialId: hintedCredential);
    } on PasskeyCeremonyException catch (e) {
      throw PasskeyLostException(canonical, 'no passkey credential', cause: e);
    }
    final keys = await RecordKeys.derive(unlocked.secret, canonical);
    final enrollmentId =
        hintedEnrollment ?? await _enrollmentIdFromPointer(canonical, keys);

    final EnrollmentSession session;
    try {
      session = await gateway.authenticate(
          atSign: canonical,
          enrollmentId: enrollmentId,
          authSeed: keys.authSeed);
    } on PkamRefusedException catch (e) {
      throw PasskeyLostException(canonical, 'PKAM refused', cause: e);
    }
    final Map<String, dynamic> atKeys;
    try {
      atKeys = await _restore(canonical, enrollmentId, keys, session);
    } on Object {
      await session.close();
      rethrow;
    }
    await _remember(canonical, unlocked.credentialId, enrollmentId);
    return CustodySession._(
        atSign: canonical,
        enrollmentId: enrollmentId,
        atKeys: atKeys,
        session: session,
        lookupHex: keys.lookupHex,
        credentialId: unlocked.credentialId);
  }

  /// Moves [current]'s @keys to a newly registered passkey: enrolls it with
  /// [otp], writes its document and pointer, and only once the pointer reads
  /// back deletes the old pointer and revokes the old enrollment.
  ///
  /// Throws [RotationAbortedException] when the new pointer does not read
  /// back, leaving the old enrollment and pointer untouched.
  Future<CustodySession> rotate(CustodySession current,
      {required String otp}) async {
    final passkey = await kek.register(current.atSign);
    final keys = await RecordKeys.derive(passkey.secret, current.atSign);
    final session = await gateway.enroll(
        atSign: current.atSign, authSeed: keys.authSeed, otp: otp);
    final CustodySession rotated;
    try {
      rotated = await _publish(
          current.atSign, passkey.credentialId, keys, session, current.atKeys);
      if (await _pointedEnrollmentId(current.atSign, keys) !=
          rotated.enrollmentId) {
        throw RotationAbortedException();
      }
    } on Object {
      await session.close();
      rethrow;
    }
    await session.pointers.delete(current.atSign, current.lookupHex);
    await session.revoke(current.enrollmentId);
    await _remember(current.atSign, passkey.credentialId, rotated.enrollmentId);
    await current.close();
    return rotated;
  }

  Future<CustodySession> _publish(
    String atSign,
    Uint8List credentialId,
    RecordKeys keys,
    EnrollmentSession session,
    Map<String, dynamic> atKeys,
  ) async {
    final held = {...atKeys}..remove(_apkamPrivateKey);
    final document =
        await PasskeyRecordCodec.seal(keys.kek, PasskeyRecordType.atkeys, held);
    await session.documents.put(atSign, session.enrollmentId, document);
    final pointer = await PasskeyRecordCodec.seal(keys.kek,
        PasskeyRecordType.eid, {'enrollmentId': session.enrollmentId});
    await session.pointers.put(atSign, keys.lookupHex, pointer);
    return CustodySession._(
        atSign: atSign,
        enrollmentId: session.enrollmentId,
        atKeys: held,
        session: session,
        lookupHex: keys.lookupHex,
        credentialId: credentialId);
  }

  Future<String> _enrollmentIdFromPointer(
          String atSign, RecordKeys keys) async =>
      await _pointedEnrollmentId(atSign, keys) ??
      (throw PasskeyLostException(atSign, 'no enrollment pointer'));

  Future<String?> _pointedEnrollmentId(String atSign, RecordKeys keys) async {
    final record = await pointerReader.get(atSign, keys.lookupHex);
    if (record == null) return null;
    final pointer =
        await PasskeyRecordCodec.open(keys.kek, PasskeyRecordType.eid, record);
    return switch (pointer) {
      {'enrollmentId': String id} => id,
      _ => throw UnsupportedPasskeyRecordException(
          'enrollment pointer holds no enrollmentId'),
    };
  }

  Future<Map<String, dynamic>> _restore(String atSign, String enrollmentId,
      RecordKeys keys, EnrollmentSession session) async {
    final record = await session.documents.get(atSign, enrollmentId) ??
        (throw MissingAtKeysDocumentException(enrollmentId));
    final atKeys = await PasskeyRecordCodec.open(
        keys.kek, PasskeyRecordType.atkeys, record);
    if (!await session.publicKeysMatch(atKeys)) {
      throw PublicKeyMismatchException();
    }
    return atKeys;
  }

  Future<void> _remember(
      String atSign, Uint8List credentialId, String enrollmentId) async {
    await credentials.putCredentialId(atSign, credentialId);
    await enrollmentIds.putEnrollmentId(atSign, enrollmentId);
    try {
      await persistence?.requestPersist();
    } on Object {
      // A refused or failed request does not fail the open.
    }
  }
}
