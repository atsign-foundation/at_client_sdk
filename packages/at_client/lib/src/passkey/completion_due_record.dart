import 'package:at_auth/passkey.dart' show clipForMessage;
import 'package:at_commons/at_builders.dart'
    show DeleteVerbBuilder, LLookupVerbBuilder, UpdateVerbBuilder;
import 'package:at_commons/at_commons.dart'
    show AtKey, InvalidResponseException, KeyNotFoundException;
import 'package:at_commons/atsign.dart';

import 'package:at_client/src/client/remote_secondary.dart';

import 'enrollment_document_store.dart' show checkEnrollmentId;

/// What an enrollment's completion-due record says: that the completion of
/// the activation that created the enrollment is due, and how far the
/// onboarding got.
enum CompletionDue {
  /// The activation is done and its completion is due; the onboarding has
  /// not recorded that its own delete of the CRAM secret answered.
  activated,

  /// The onboarding's own delete of the CRAM secret answered, and the rest
  /// of the completion is due.
  cramSecretDeleted,
}

const _activated = 'activated';
const _cramSecretDeleted = 'cram-deleted';

/// The name of an enrollment's completion-due record,
/// `completion-due.<enrollmentId>.a.__e@<atsign>` with the atSign canonical.
///
/// Throws [ArgumentError] when [enrollmentId] is empty or holds a character
/// outside `a-z 0-9 _ -`.
String completionDueKey(String enrollmentId, String atSign) =>
    '${_recordKey(enrollmentId, atSign)}';

/// The [AtKey] of [enrollmentId]'s completion-due record at [atSign]: a self
/// record in the enrollment's own namespace, beside its @keys document.
AtKey _recordKey(String enrollmentId, String atSign) {
  checkEnrollmentId(enrollmentId);
  return AtKey()
    ..key = 'completion-due.$enrollmentId.a'
    ..namespace = '__e'
    ..sharedBy = atSign.toAtsign();
}

/// One enrollment's completion-due record, on [remote], that enrollment's own
/// PKAM-authenticated connection, which it leaves open.
///
/// The atServer refuses a read, write or delete of the record to every other
/// enrollment of the atSign from at_server p3.15.0, one holding `*:rw`
/// included, and to a connection with the atSign's legacy keys from p3.16.5.
/// A CRAM-authenticated connection may read the record on every version, and
/// write or delete it before p3.19.0.
///
/// Throws [ArgumentError] when [enrollmentId] is empty or holds a character
/// outside `a-z 0-9 _ -`.
class CompletionDueRecord {
  CompletionDueRecord(this.remote,
      {required String atSign, required String enrollmentId})
      : _key = _recordKey(enrollmentId, atSign);

  final RemoteSecondary remote;
  final AtKey _key;

  /// Writes [state] to the record, replacing what it held.
  Future<void> write(CompletionDue state) async {
    final command = (UpdateVerbBuilder()
          ..omitMetadata = true
          ..atKey = _key
          ..value = switch (state) {
            CompletionDue.activated => _activated,
            CompletionDue.cramSecretDeleted => _cramSecretDeleted,
          })
        .buildCommand();
    await remote.executeCommand(command, auth: true);
  }

  /// What the record says, or null when there is none. A value other than
  /// the one [CompletionDue.cramSecretDeleted] writes reads as
  /// [CompletionDue.activated]. Every failure other than the record being
  /// absent is thrown.
  Future<CompletionDue?> read() async {
    final command = (LLookupVerbBuilder()..atKey = _key).buildCommand();
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
    return switch (response.substring('data:'.length).trim()) {
      'null' => null,
      _cramSecretDeleted => CompletionDue.cramSecretDeleted,
      _ => CompletionDue.activated,
    };
  }

  /// Deletes the record. One the atServer reports as not found counts as
  /// deleted.
  Future<void> clear() async {
    final command = (DeleteVerbBuilder()..atKey = _key).buildCommand();
    try {
      await remote.executeCommand(command, auth: true);
    } on KeyNotFoundException {
      return;
    }
  }
}
