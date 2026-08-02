import 'package:at_client/at_client.dart';
import 'package:at_client/src/response/at_notification.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_client/src/util/at_client_util.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

/// Every hand-rolled metadata converter in this package, held to one standard.
///
/// The sync PUSH once dropped `appMetadata` because its serializer was a
/// duplicate of the canonical builder that had fallen behind it. Deleting that
/// duplicate fixed one of five converters; these are the rest. A dropped field
/// never fails loudly — the value simply is not there on the other side — so
/// the only defence is a test that names the whole field set and checks each
/// converter against it.
void main() {
  /// The canonical field inventory: what `Metadata` says it has.
  ///
  /// Pinned deliberately. When a field is added to `Metadata` in at_commons,
  /// this fails first, and fixing it means visiting each converter below and
  /// deciding — on purpose — whether that field travels. That decision is the
  /// thing the push-side drift never got.
  const knownMetadataFields = {
    'availableAt',
    'expiresAt',
    'refreshAt',
    AtConstants.createdAt,
    AtConstants.updatedAt,
    'isPublic',
    AtConstants.ttl,
    AtConstants.ttb,
    AtConstants.ttr,
    AtConstants.ccd,
    AtConstants.isBinary,
    AtConstants.isEncrypted,
    AtConstants.publicDataSignature,
    AtConstants.sharedKeyStatus,
    AtConstants.sharedKeyEncrypted,
    AtConstants.sharedWithPublicKeyCheckSum,
    AtConstants.sharedWithPublicKeyHash,
    AtConstants.encoding,
    AtConstants.encryptingKeyName,
    AtConstants.encryptingAlgo,
    AtConstants.ivOrNonce,
    AtConstants.sharedKeyEncryptedEncryptingKeyName,
    AtConstants.sharedKeyEncryptedEncryptingAlgo,
    AtConstants.immutable,
    AtConstants.appMetadata,
    'namespaceAware',
    'isCached',
  };

  test('the Metadata field inventory has not grown unnoticed', () {
    expect(Metadata().toJson().keys.toSet(), knownMetadataFields,
        reason: 'a new Metadata field means every converter in this file needs '
            'a deliberate decision about whether it travels — that is exactly '
            'what silently dropping appMetadata cost');
  });

  group('read path · AtClientUtil.prepareMetadata', () {
    test('carries immutable — dropped for every remote read until now', () {
      final metadata = AtClientUtil.prepareMetadata(
          {AtConstants.immutable: true}, false,
          isCached: false);

      expect(metadata!.immutable, isTrue,
          reason: 'this is the deserializer behind every remote get/lookup, so '
              'a client-side guard on immutable was reading a constant false');
    });

    test('defaults immutable to false when the server does not send it', () {
      expect(AtClientUtil.prepareMetadata({}, false)!.immutable, isFalse);
    });

    test('still carries appMetadata alongside it', () {
      final metadata = AtClientUtil.prepareMetadata({
        AtConstants.appMetadata: Metadata.encodeAppMetadata(
            AppMetadata(providerId: 'at/symmetric/AES/GCM')),
        AtConstants.immutable: true,
      }, false);

      expect(metadata!.appMetadata?.providerId, 'at/symmetric/AES/GCM');
      expect(metadata.immutable, isTrue);
    });
  });

  group('sync pull · SyncServiceImpl.setMetadataFromCommitEntry', () {
    /// The commit entry carries every value as a string, which is why this
    /// converter cannot simply delegate to Metadata.fromJson.
    void pull(Metadata into, Map<String, String> serverMetadata) =>
        SyncServiceImpl.setMetadataFromCommitEntry(
            into, {'metadata': serverMetadata});

    test('carries immutable', () {
      final md = Metadata();
      pull(md, {AtConstants.immutable: 'true'});
      expect(md.immutable, isTrue,
          reason: 'the mirror of the push-side drop this branch fixed');
    });

    test('carries appMetadata', () {
      final md = Metadata();
      pull(md, {
        AtConstants.appMetadata: Metadata.encodeAppMetadata(
            AppMetadata(providerId: 'at/nskey/XWING/AES/GCM')),
      });
      expect(md.appMetadata?.providerId, 'at/nskey/XWING/AES/GCM');
    });

    test('leaves immutable alone when the server does not send it', () {
      final md = Metadata()..immutable = true;
      pull(md, {AtConstants.ttl: '1000'});
      expect(md.immutable, isTrue);
    });
  });

  group('notification read · AtNotification.fromJson', () {
    test('carries isBinary, which decides the payload wire format', () {
      final n = AtNotification.fromJson({
        'id': 'abc',
        'key': '@bob:phone.wavi@alice',
        'from': '@alice',
        'to': '@bob',
        'epochMillis': 0,
        'messageType': 'key',
        AtConstants.isEncrypted: true,
        'metadata': {AtConstants.isBinary: 'true'},
      });

      expect(n.metadata!.isBinary, isTrue,
          reason: 'a provider branches on isBinary; losing it makes a binary '
              'notification decode as text');
    });

    test('accepts a real bool as well as the string form', () {
      final n = AtNotification.fromJson({
        'id': 'abc',
        'key': '@bob:phone.wavi@alice',
        'from': '@alice',
        'to': '@bob',
        'epochMillis': 0,
        'messageType': 'key',
        AtConstants.isEncrypted: true,
        'metadata': {
          AtConstants.isBinary: true,
          AtConstants.encoding: 'base64'
        },
      });

      expect(n.metadata!.isBinary, isTrue);
      expect(n.metadata!.encoding, 'base64');
    });

    test('defaults isBinary to false when absent', () {
      final n = AtNotification.fromJson({
        'id': 'abc',
        'key': '@bob:phone.wavi@alice',
        'from': '@alice',
        'to': '@bob',
        'epochMillis': 0,
        'messageType': 'key',
        AtConstants.isEncrypted: true,
        'metadata': {AtConstants.ivOrNonce: 'an-iv'},
      });

      expect(n.metadata!.isBinary, isFalse);
      expect(n.metadata!.ivNonce, 'an-iv');
    });
  });
}
