import 'dart:convert';
import 'dart:typed_data';

import 'package:at_client/at_client.dart';
import 'package:at_lookup/at_lookup.dart' show SecondaryAddressFinder;

import 'public_lookup.dart';
import 'server_copy.dart';

/// Reads the server copy with an unauthenticated `lookup:` on a connection
/// of its own from [lookUps], closed after each read.
class LookupServerCopyReader implements ServerCopyReader {
  LookupServerCopyReader(
      {required this.lookUps,
      required this.rootDomain,
      this.secondaryAddressFinder});

  final AtLookUpFactory lookUps;
  final AtRootDomain rootDomain;
  final SecondaryAddressFinder? secondaryAddressFinder;

  /// The envelope, or null when the key is not found or holds null.
  @override
  Future<Uint8List?> fetch(String atSign, String app) async {
    final text = await publicLookup(
        lookUps: lookUps,
        rootDomain: rootDomain,
        secondaryAddressFinder: secondaryAddressFinder,
        atSign: atSign,
        key: atKeysRecordKey(atSign, app));
    return text == null ? null : Uint8List.fromList(utf8.encode(text));
  }
}

/// Reads through [reader] and writes with an `update:public:` on [remote],
/// the client's own authenticated connection, which it leaves open.
class RemoteServerCopy implements ServerCopy {
  RemoteServerCopy(this.reader, this.remote);

  final ServerCopyReader reader;
  final RemoteSecondary remote;

  @override
  Future<Uint8List?> fetch(String atSign, String app) =>
      reader.fetch(atSign, app);

  @override
  Future<void> put(String atSign, String app, Uint8List envelope) async {
    await remote.executeCommand(updateCommand(atSign, app, envelope),
        auth: true);
  }
}
