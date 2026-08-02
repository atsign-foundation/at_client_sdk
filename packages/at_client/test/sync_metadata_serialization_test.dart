import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart'
    show AtMetaData;
import 'package:test/test.dart';

/// Regression: the client→server sync push must serialize metadata through the
/// single canonical serializer.
///
/// `SyncServiceImpl.metadataToString` used to be a hand-rolled serializer
/// parallel to `Metadata.toAtProtocolFragment`; it had drifted and silently
/// dropped `appMetadata` (and `immutable`), so a synced record reached the
/// server without them and a cross-atSign `lookup:all` returned a null
/// `providerId` — CryptoRuntime then fell back to legacy and hunted a
/// shared_key a PQ write never created. It now delegates to
/// `toAtProtocolFragment`, so it cannot drift again.
void main() {
  group('SyncServiceImpl.metadataToString', () {
    test('delegates to Metadata.toAtProtocolFragment — cannot re-drift', () {
      final metadata = AtMetaData()
        ..ttl = 1000
        ..sharedKeyEnc = 'enc-shared-key'
        ..isEncrypted = true
        ..immutable = true
        ..appMetadata = AppMetadata(providerId: 'at/symmetric/AES/GCM');
      // The sync push must serialize identically to the direct-write path
      // (UpdateVerbBuilder also uses toAtProtocolFragment), byte-for-byte.
      expect(SyncServiceImpl.metadataToString(metadata),
          metadata.toCommonsMetadata().toAtProtocolFragment());
    });

    test('carries appMetadata — the field the drift dropped — base64 and last',
        () {
      final appMetadata = AppMetadata(providerId: 'at/symmetric/AES/GCM');
      final result = SyncServiceImpl.metadataToString(
          AtMetaData()..appMetadata = appMetadata);
      final expected =
          ':${AtConstants.appMetadata}:${Metadata.encodeAppMetadata(appMetadata)}';
      expect(result, contains(expected));
      // appMetadata is the final group in VerbSyntax.update, so it must be last.
      expect(result.endsWith(expected), isTrue);
    });

    test('carries immutable — the sibling field the drift also dropped', () {
      expect(SyncServiceImpl.metadataToString(AtMetaData()..immutable = true),
          contains(':${AtConstants.immutable}:true'));
    });

    test('round-trips appMetadata through decodeAppMetadata', () {
      final appMetadata = AppMetadata(
          providerId: 'at/symmetric/AES/GCM', additional: {'ckKid': 'k1'});
      final result = SyncServiceImpl.metadataToString(
          AtMetaData()..appMetadata = appMetadata);
      final token = result.split(':${AtConstants.appMetadata}:').last;
      final decoded = Metadata.decodeAppMetadata(token);
      expect(decoded?.providerId, 'at/symmetric/AES/GCM');
      expect(decoded?.additional?['ckKid'], 'k1');
    });

    test('omits appMetadata when absent', () {
      expect(
          SyncServiceImpl.metadataToString(AtMetaData()..ttl = 1000)
              .contains('appMetadata'),
          isFalse);
    });

    test('null metadata serializes to empty string', () {
      expect(SyncServiceImpl.metadataToString(null), '');
    });
  });
}
