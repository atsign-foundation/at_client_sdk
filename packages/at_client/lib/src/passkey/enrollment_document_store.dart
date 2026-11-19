import 'package:at_auth/passkey.dart' show clipForMessage;
import 'package:at_commons/at_builders.dart'
    show DeleteVerbBuilder, LLookupVerbBuilder, UpdateVerbBuilder;
import 'package:at_commons/at_commons.dart'
    show AtKey, InvalidResponseException, KeyNotFoundException;
import 'package:at_commons/atsign.dart';

import 'package:at_client/src/client/remote_secondary.dart';
import 'package:at_client/src/client/server_mutex.dart';

/// Reads and writes an enrollment's sealed @keys document, and the record
/// that its activation's completion is due, over that enrollment's
/// authenticated connection.
abstract class EnrollmentDocumentStore {
  /// The document's JSON text, or null when there is none.
  Future<String?> get(String atSign, String enrollmentId);

  /// Writes [document], replacing any document of that name.
  Future<void> put(String atSign, String enrollmentId, String document);

  /// Takes the lock on the document of [enrollmentId] for [ttl], or returns
  /// null while it is held. Every other failure is thrown.
  Future<ServerMutexLease?> tryLock(String atSign, String enrollmentId,
      {required Duration ttl});

  /// Records that the completion of the activation that created
  /// [enrollmentId] is due.
  Future<void> markCompletionDue(String atSign, String enrollmentId);

  /// Whether the completion of the activation that created [enrollmentId] is
  /// due: true while its record exists. Every failure other than the record
  /// being absent is thrown.
  Future<bool> isCompletionDue(String atSign, String enrollmentId);

  /// Deletes the record that the completion of [enrollmentId]'s activation is
  /// due. A record the atServer reports as not found counts as deleted.
  Future<void> clearCompletionDue(String atSign, String enrollmentId);
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

/// The name of the record that the completion of an enrollment's activation
/// is due, `completion-due.<enrollmentId>.a.__e@<atsign>` with the atSign
/// canonical.
///
/// Throws [ArgumentError] when [enrollmentId] is empty or holds a character
/// outside `a-z 0-9 _ -`.
String completionDueKey(String enrollmentId, String atSign) =>
    '${_completionDueKey(enrollmentId, atSign)}';

/// The [AtKey] of the record that the completion of [enrollmentId]'s
/// activation at [atSign] is due: a self record in the enrollment's own
/// namespace, beside the document.
AtKey _completionDueKey(String enrollmentId, String atSign) {
  checkEnrollmentId(enrollmentId);
  return AtKey()
    ..key = 'completion-due.$enrollmentId.a'
    ..namespace = '__e'
    ..sharedBy = atSign.toAtsign();
}

/// The value of every completion-due record.
const _completionDue = 'due';

/// Reads and writes documents and completion-due records on [remote], the
/// enrollment's own PKAM-authenticated connection, which it leaves open, and
/// takes the documents' locks there as server mutexes.
class RemoteEnrollmentDocumentStore implements EnrollmentDocumentStore {
  RemoteEnrollmentDocumentStore(this.remote);

  final RemoteSecondary remote;

  @override
  Future<String?> get(String atSign, String enrollmentId) async =>
      _localLookup(_documentKey(enrollmentId, atSign));

  /// The value [key] holds, or null when the atServer holds none.
  Future<String?> _localLookup(AtKey key) async {
    final command = (LLookupVerbBuilder()..atKey = key).buildCommand();
    final String? response;
    try {
      response = await remote.executeCommand(command, auth: true);
    } on KeyNotFoundException {
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
    if (document.contains('\n')) {
      throw ArgumentError.value(
          document, 'document', 'must not contain newlines');
    }
    final command = (UpdateVerbBuilder()
          ..omitMetadata = true
          ..atKey = _documentKey(enrollmentId, atSign)
          ..value = document)
        .buildCommand();
    await remote.executeCommand(command, auth: true);
  }

  @override
  Future<void> markCompletionDue(String atSign, String enrollmentId) async {
    final command = (UpdateVerbBuilder()
          ..omitMetadata = true
          ..atKey = _completionDueKey(enrollmentId, atSign)
          ..value = _completionDue)
        .buildCommand();
    await remote.executeCommand(command, auth: true);
  }

  @override
  Future<bool> isCompletionDue(String atSign, String enrollmentId) async =>
      await _localLookup(_completionDueKey(enrollmentId, atSign)) != null;

  @override
  Future<void> clearCompletionDue(String atSign, String enrollmentId) async {
    final command = (DeleteVerbBuilder()
          ..atKey = _completionDueKey(enrollmentId, atSign))
        .buildCommand();
    try {
      await remote.executeCommand(command, auth: true);
    } on KeyNotFoundException {
      return;
    }
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
