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

    /// The guard for the defect class rather than the field.
    ///
    /// `VerbSyntax.metadataFragment` is a sequence of OPTIONAL groups, so a
    /// field emitted in the wrong order does not error — the regex stops
    /// matching at that point and the atServer silently drops everything after
    /// it. Neither a `contains` assertion nor comparing against
    /// `toAtProtocolFragment` can see that: the latter agrees with the canonical
    /// builder even if the canonical builder itself is the one out of order.
    /// Only parsing the built command with the verb the atServer actually uses
    /// closes it. Every field is populated so a new one added out of order here
    /// fails.
    test('a fully-populated fragment parses as a valid update command', () {
      final appMetadata = AppMetadata(
          providerId: 'at/nskey/XWING/AES/GCM',
          additional: {'ckKid': 'k1', 'nskeyKid': 'n1'});
      final metadata = AtMetaData()
        ..ttl = 1000
        ..ttb = 2000
        ..ttr = 3000
        ..isCascade = true
        ..dataSignature = 'a-signature'
        ..isBinary = true
        ..isEncrypted = true
        ..sharedKeyEnc = 'enc-shared-key'
        ..pubKeyCS = 'a-checksum'
        ..pubKeyHash = PublicKeyHash('a-hash', 'sha512')
        ..encoding = 'base64'
        ..encKeyName = 'enc-key-name'
        ..encAlgo = 'AES/GCM'
        ..ivNonce = 'an-iv'
        ..skeEncKeyName = 'ske-key-name'
        ..skeEncAlgo = 'RSA'
        ..immutable = true
        ..appMetadata = appMetadata;

      final command = 'update'
          '${SyncServiceImpl.metadataToString(metadata)}'
          ':@bob:test.unit@alice a-value';
      final match = RegExp(VerbSyntax.update).firstMatch(command);

      expect(match, isNotNull,
          reason: 'the atServer parses the sync push with VerbSyntax.update, '
              'and a fragment it cannot match is truncated rather than '
              'rejected. Command was: $command');

      // Assert through to the tail: those are the groups a mis-ordered field
      // strands, and the key/value pair is what silently goes missing.
      expect(match!.namedGroup('atKey'), 'test.unit');
      expect(match.namedGroup('forAtSign'), 'bob');
      expect(match.namedGroup('atSign'), 'alice');
      expect(match.namedGroup('value'), 'a-value');
      expect(match.namedGroup('immutable'), 'true');
      expect(match.namedGroup('appMetadata'),
          Metadata.encodeAppMetadata(appMetadata));

      final decoded =
          Metadata.decodeAppMetadata(match.namedGroup('appMetadata'));
      expect(decoded?.providerId, 'at/nskey/XWING/AES/GCM');
      expect(decoded?.additional?['ckKid'], 'k1');
    });
  });
}
