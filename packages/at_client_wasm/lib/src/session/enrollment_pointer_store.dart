import 'package:at_client/at_client.dart';
// ignore: implementation_imports
import 'package:at_client/src/client/remote_secondary.dart';

import 'public_lookup.dart';

/// Reads a passkey's enrollment pointer by its lookup id and namespace.
abstract interface class EnrollmentPointerReader {
  /// The pointer's JSON text, or null when there is none.
  Future<String?> get(String atSign, String lookupHex, {required String ns});
}

/// Reads, writes and deletes enrollment pointers.
abstract interface class EnrollmentPointerStore
    implements EnrollmentPointerReader {
  /// Writes [record], replacing any pointer of that name; it never expires.
  Future<void> put(String atSign, String lookupHex, String record,
      {required String ns});

  /// Deletes the pointer.
  Future<void> delete(String atSign, String lookupHex, {required String ns});
}

final _hex64 = RegExp(r'^[0-9a-f]{64}$');

/// The atProtocol key of an enrollment pointer, without the `public:` scope:
/// `_<lookupHex>.<ns>@<atsign>` with the atSign canonical.
///
/// Throws [ArgumentError] when [lookupHex] or [ns] is not 64 lowercase hex
/// characters.
String enrollmentPointerKey(String atSign, String lookupHex,
    {required String ns}) {
  for (final (name, value) in [('lookupHex', lookupHex), ('ns', ns)]) {
    if (!_hex64.hasMatch(value)) {
      throw ArgumentError.value(
          value, name, 'must be 64 lowercase hex characters');
    }
  }
  return '_$lookupHex.$ns${atSign.toAtsign()}';
}

/// Reads pointers with an unauthenticated `lookup:` on a connection of its own
/// from [lookUps], closed after each read.
class LookupEnrollmentPointerReader implements EnrollmentPointerReader {
  LookupEnrollmentPointerReader(
      {required this.lookUps,
      required this.rootDomain,
      this.secondaryAddressFinder});

  final AtLookUpFactory lookUps;
  final AtRootDomain rootDomain;
  final SecondaryAddressFinder? secondaryAddressFinder;

  @override
  Future<String?> get(String atSign, String lookupHex, {required String ns}) =>
      publicLookup(
          lookUps: lookUps,
          rootDomain: rootDomain,
          secondaryAddressFinder: secondaryAddressFinder,
          atSign: atSign,
          key: enrollmentPointerKey(atSign, lookupHex, ns: ns));
}

/// Reads through [reader]; writes and deletes on [remote], the client's own
/// authenticated connection, which it leaves open.
class RemoteEnrollmentPointerStore implements EnrollmentPointerStore {
  RemoteEnrollmentPointerStore(this.reader, this.remote);

  final EnrollmentPointerReader reader;
  final RemoteSecondary remote;

  @override
  Future<String?> get(String atSign, String lookupHex, {required String ns}) =>
      reader.get(atSign, lookupHex, ns: ns);

  @override
  Future<void> put(String atSign, String lookupHex, String record,
      {required String ns}) async {
    if (record.contains('\n')) {
      throw ArgumentError.value(record, 'record', 'must not contain newlines');
    }
    final key = enrollmentPointerKey(atSign, lookupHex, ns: ns);
    await remote.executeCommand('update:public:$key $record\n', auth: true);
  }

  @override
  Future<void> delete(String atSign, String lookupHex,
      {required String ns}) async {
    await remote.executeCommand(
        'delete:public:${enrollmentPointerKey(atSign, lookupHex, ns: ns)}\n',
        auth: true);
  }
}
