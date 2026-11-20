import 'package:at_commons/at_builders.dart' show UpdateVerbBuilder;
import 'package:at_commons/at_commons.dart' show AtKey, AtRootDomain, Metadata;
import 'package:at_commons/atsign.dart';
import 'package:at_lookup/at_lookup.dart'
    show AtLookUpFactory, SecondaryAddressFinder;

import 'package:at_client/src/client/remote_secondary.dart';

import 'public_lookup.dart';

/// Reads a passkey's enrollment pointer by its lookup id and namespace.
abstract class EnrollmentPointerReader {
  /// The pointer's JSON text, or null when there is none.
  Future<String?> get(String atSign, String lookupHex, {required String ns});
}

/// Reads and writes enrollment pointers.
abstract class EnrollmentPointerStore implements EnrollmentPointerReader {
  /// Writes [record], replacing any pointer of that name; it never expires.
  Future<void> put(String atSign, String lookupHex, String record,
      {required String ns});
}

final _hex64 = RegExp(r'^[0-9a-f]{64}$');

/// The Atsign Protocol key of an enrollment pointer, without the `public:`
/// scope: `_<lookupHex>.<ns>@<atsign>` with the atSign canonical.
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

/// The key name of the pointer, `_<lookupHex>`, after the same check of
/// [lookupHex] and [ns] as [enrollmentPointerKey].
String _pointerName(String atSign, String lookupHex, String ns) {
  enrollmentPointerKey(atSign, lookupHex, ns: ns);
  return '_$lookupHex';
}

/// The public [AtKey] of the pointer at [lookupHex] and [ns], which names the
/// same key as [enrollmentPointerKey].
AtKey _pointerKey(String atSign, String lookupHex, String ns) {
  return AtKey()
    ..key = _pointerName(atSign, lookupHex, ns)
    ..namespace = ns
    ..sharedBy = atSign.toAtsign()
    ..metadata = (Metadata()..isPublic = true);
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
          key: _pointerName(atSign, lookupHex, ns),
          namespace: ns);
}

/// Reads through [reader]; writes on [remote], the client's own
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
    final command = (UpdateVerbBuilder()
          ..omitMetadata = true
          ..atKey = _pointerKey(atSign, lookupHex, ns)
          ..value = record)
        .buildCommand();
    await remote.executeCommand(command, auth: true);
  }
}
