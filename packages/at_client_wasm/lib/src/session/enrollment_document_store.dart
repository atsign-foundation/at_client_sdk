import 'package:at_client/at_client.dart';
// ignore: implementation_imports
import 'package:at_client/src/client/remote_secondary.dart';

/// Reads, writes and deletes an enrollment's sealed @keys document, which
/// only that enrollment's authenticated connection can reach.
abstract interface class EnrollmentDocumentStore {
  /// The document's JSON text, or null when there is none.
  Future<String?> get(String atSign, String enrollmentId);

  /// Writes [document], replacing any document of that name.
  Future<void> put(String atSign, String enrollmentId, String document);

  /// Deletes the document.
  Future<void> delete(String atSign, String enrollmentId);
}

final _enrollmentId = RegExp(r'^[A-Za-z0-9_-]+$');

/// The atProtocol key of an enrollment's document,
/// `atkeys.<enrollmentId>.a.__e@<atsign>` with the atSign canonical.
///
/// Throws [ArgumentError] when [enrollmentId] is empty or holds a character
/// outside `A-Z a-z 0-9 _ -`.
String enrollmentDocumentKey(String enrollmentId, String atSign) {
  if (!_enrollmentId.hasMatch(enrollmentId)) {
    throw ArgumentError.value(
        enrollmentId, 'enrollmentId', 'must match [A-Za-z0-9_-]+');
  }
  return 'atkeys.$enrollmentId.a.__e${atSign.toAtsign()}';
}

/// Reads, writes and deletes documents on [remote], the enrollment's own
/// PKAM-authenticated connection, which it leaves open.
class RemoteEnrollmentDocumentStore implements EnrollmentDocumentStore {
  RemoteEnrollmentDocumentStore(this.remote);

  final RemoteSecondary remote;

  @override
  Future<String?> get(String atSign, String enrollmentId) async {
    final key = enrollmentDocumentKey(enrollmentId, atSign);
    final String? response;
    try {
      response = await remote.executeCommand('llookup:$key\n', auth: true);
    } on KeyNotFoundException {
      return null;
    }
    if (response == null || !response.startsWith('data:')) {
      throw StateError('unexpected llookup response: $response');
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
    await remote.executeCommand(
        'update:${enrollmentDocumentKey(enrollmentId, atSign)} $document\n',
        auth: true);
  }

  @override
  Future<void> delete(String atSign, String enrollmentId) async {
    await remote.executeCommand(
        'delete:${enrollmentDocumentKey(enrollmentId, atSign)}\n',
        auth: true);
  }
}
