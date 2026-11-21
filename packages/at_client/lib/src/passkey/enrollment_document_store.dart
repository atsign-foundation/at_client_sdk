import 'package:at_auth/passkey.dart' show clipForMessage;
import 'package:at_commons/at_builders.dart'
    show LLookupVerbBuilder, UpdateVerbBuilder;
import 'package:at_commons/at_commons.dart'
    show AtKey, InvalidResponseException, KeyNotFoundException;
import 'package:at_commons/atsign.dart';

import 'package:at_client/src/client/remote_secondary.dart';
import 'package:at_client/src/client/server_mutex.dart';

/// Reads and writes an enrollment's sealed @keys document over that
/// enrollment's authenticated connection.
abstract class EnrollmentDocumentStore {
  /// The document's JSON text, or null when there is none.
  Future<String?> get(String atSign, String enrollmentId);

  /// Writes [document], replacing any document of that name.
  Future<void> put(String atSign, String enrollmentId, String document);

  /// Takes the lock on the document of [enrollmentId] for [ttl], or returns
  /// null while it is held. Every other failure is thrown.
  Future<ServerMutexLease?> tryLock(String atSign, String enrollmentId,
      {required Duration ttl});
}

final _enrollmentId = RegExp(r'^[a-z0-9_-]+$');

/// Throws [ArgumentError] when [enrollmentId] is empty or holds a character
/// outside `a-z 0-9 _ -`; the one test every use of an id goes through.
void checkEnrollmentId(String enrollmentId) {
  if (!_enrollmentId.hasMatch(enrollmentId)) {
    throw ArgumentError.value(
        enrollmentId, 'enrollmentId', 'must match [a-z0-9_-]+');
  }
}

/// The atProtocol key of an enrollment's document,
/// `atkeys.<enrollmentId>.a.__e@<atsign>` with the atSign canonical.
///
/// Throws [ArgumentError] when [enrollmentId] is empty or holds a character
/// outside `a-z 0-9 _ -`.
String enrollmentDocumentKey(String enrollmentId, String atSign) {
  checkEnrollmentId(enrollmentId);
  return 'atkeys.$enrollmentId.a.__e${atSign.toAtsign()}';
}

/// The [AtKey] of the document of [enrollmentId] at [atSign], which names the
/// same key as [enrollmentDocumentKey].
AtKey _documentKey(String enrollmentId, String atSign) {
  checkEnrollmentId(enrollmentId);
  return AtKey()
    ..key = 'atkeys.$enrollmentId.a'
    ..namespace = '__e'
    ..sharedBy = atSign.toAtsign();
}

/// The name of the lock on an enrollment's document,
/// `atkeys-lock.<enrollmentId>.a.__e@<atsign>` with the atSign canonical.
///
/// Throws [ArgumentError] when [enrollmentId] is empty or holds a character
/// outside `a-z 0-9 _ -`.
String enrollmentLockKey(String enrollmentId, String atSign) =>
    '${_lockKey(enrollmentId, atSign)}';

/// The [AtKey] of the lock on the document of [enrollmentId] at [atSign]: a
/// self record in the enrollment's own namespace, beside the document.
AtKey _lockKey(String enrollmentId, String atSign) {
  checkEnrollmentId(enrollmentId);
  return AtKey()
    ..key = 'atkeys-lock.$enrollmentId.a'
    ..namespace = '__e'
    ..sharedBy = atSign.toAtsign();
}

/// Reads and writes documents on [remote], the enrollment's own
/// PKAM-authenticated connection, which it leaves open, and takes their
/// locks there as server mutexes.
class RemoteEnrollmentDocumentStore implements EnrollmentDocumentStore {
  RemoteEnrollmentDocumentStore(this.remote);

  final RemoteSecondary remote;

  @override
  Future<String?> get(String atSign, String enrollmentId) async {
    final command = (LLookupVerbBuilder()
          ..atKey = _documentKey(enrollmentId, atSign))
        .buildCommand();
    final String? response;
    try {
      response = await remote.executeCommand(command, auth: true);
    } on KeyNotFoundException {
      // A missing document is reported as null, not as an error.
      return null;
    }
    if (response == null || !response.startsWith('data:')) {
      throw InvalidResponseException(
          'unexpected llookup response: ${clipForMessage('$response')}');
    }
    final text = response.substring('data:'.length).trim();
    return text == 'null' ? null : text;
  }

  @override
  Future<void> put(String atSign, String enrollmentId, String document) async {
    if (document.contains('\n') || document.contains('\r')) {
      throw ArgumentError.value(document, 'document',
          'must not contain newlines or carriage returns');
    }
    final command = (UpdateVerbBuilder()
          ..omitMetadata = true
          ..atKey = _documentKey(enrollmentId, atSign)
          ..value = document)
        .buildCommand();
    await remote.executeCommand(command, auth: true);
  }

  @override
  Future<ServerMutexLease?> tryLock(String atSign, String enrollmentId,
          {required Duration ttl}) async =>
      takeServerMutex(remote,
          atSign: atSign.toAtsign(),
          enrollmentId: enrollmentId,
          key: _lockKey(enrollmentId, atSign),
          ttl: ttl);
}
