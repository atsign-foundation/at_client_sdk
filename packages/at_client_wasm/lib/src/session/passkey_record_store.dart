import 'package:at_client/at_client.dart';
import 'package:at_lookup/at_lookup.dart' show SecondaryAddressFinder;

import 'public_lookup.dart';

/// Reads a per-passkey @keys record by its lookup id.
abstract interface class PasskeyRecordReader {
  /// The record's JSON text, or null when there is none or it has expired.
  Future<String?> get(String atSign, String lookupHex);
}

/// Reads, writes and deletes per-passkey @keys records.
abstract interface class PasskeyRecordStore implements PasskeyRecordReader {
  /// Writes [record] to expire after [ttl]; writing it again restarts [ttl].
  Future<void> put(String atSign, String lookupHex, String record,
      {required Duration ttl});

  /// Deletes the record.
  Future<void> delete(String atSign, String lookupHex);
}

final _lookupHex = RegExp(r'^[0-9a-f]{64}$');

/// The atProtocol key of a passkey record, without the `public:` scope:
/// `_<lookupHex>.atkeysv@<atsign>` with the atSign canonical.
///
/// Throws [ArgumentError] when [lookupHex] is not 64 lowercase hex characters.
String passkeyRecordKey(String atSign, String lookupHex) {
  if (!_lookupHex.hasMatch(lookupHex)) {
    throw ArgumentError.value(
        lookupHex, 'lookupHex', 'must be 64 lowercase hex characters');
  }
  return '_$lookupHex.atkeysv${atSign.toAtsign()}';
}

/// Reads records with an unauthenticated `lookup:` on a connection of its own
/// from [lookUps], closed after each read.
class LookupPasskeyRecordReader implements PasskeyRecordReader {
  LookupPasskeyRecordReader(
      {required this.lookUps,
      required this.rootDomain,
      this.secondaryAddressFinder});

  final AtLookUpFactory lookUps;
  final AtRootDomain rootDomain;
  final SecondaryAddressFinder? secondaryAddressFinder;

  @override
  Future<String?> get(String atSign, String lookupHex) => publicLookup(
      lookUps: lookUps,
      rootDomain: rootDomain,
      secondaryAddressFinder: secondaryAddressFinder,
      atSign: atSign,
      key: passkeyRecordKey(atSign, lookupHex));
}

/// Reads through [reader]; writes and deletes on [remote], the client's own
/// authenticated connection, which it leaves open.
class RemotePasskeyRecordStore implements PasskeyRecordStore {
  RemotePasskeyRecordStore(this.reader, this.remote);

  final PasskeyRecordReader reader;
  final RemoteSecondary remote;

  @override
  Future<String?> get(String atSign, String lookupHex) =>
      reader.get(atSign, lookupHex);

  @override
  Future<void> put(String atSign, String lookupHex, String record,
      {required Duration ttl}) async {
    if (record.contains('\n')) {
      throw ArgumentError.value(record, 'record', 'must not contain newlines');
    }
    if (ttl <= Duration.zero) {
      throw ArgumentError.value(ttl, 'ttl', 'must be positive');
    }
    final key = passkeyRecordKey(atSign, lookupHex);
    await remote.executeCommand(
        'update:ttl:${ttl.inMilliseconds}:public:$key $record\n',
        auth: true);
  }

  @override
  Future<void> delete(String atSign, String lookupHex) async {
    await remote.executeCommand(
        'delete:public:${passkeyRecordKey(atSign, lookupHex)}\n',
        auth: true);
  }
}
