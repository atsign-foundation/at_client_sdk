import 'dart:convert';
import 'dart:typed_data';

import 'package:at_client/at_client.dart';
import 'package:at_lookup/at_lookup.dart'
    show AtLookUpException, SecondaryAddressFinder;

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
    final lookUp = lookUps(
        atSign: atSign,
        rootDomain: rootDomain,
        authenticator: null,
        secondaryAddressFinder: secondaryAddressFinder);
    try {
      final response = await lookUp
          .executeCommand('lookup:${atKeysRecordKey(atSign, app)}\n');
      if (response == null || !response.startsWith('data:')) {
        throw StateError('unexpected lookup response: $response');
      }
      final text = response.substring('data:'.length).trim();
      return text == 'null' ? null : Uint8List.fromList(utf8.encode(text));
    } on AtLookUpException catch (e) {
      if (e.errorCode == 'AT0015') return null;
      rethrow;
    } finally {
      await lookUp.close();
    }
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
