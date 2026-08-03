import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

/// [Metadata.copy] exists so nobody hand-rolls the field list, and the point of
/// that is only kept if the copy stays exhaustive. These tests compare against
/// `toJson()` and `toAtProtocolFragment()` rather than naming fields, so a field
/// added to `Metadata` later fails here instead of being silently dropped by
/// every caller that copies.
void main() {
  /// Every field set to a value distinguishable from its default, so a field
  /// the copy forgets shows up as a difference rather than matching by luck.
  Metadata populated() => Metadata()
    ..ttl = 1000
    ..ttb = 2000
    ..ttr = 3000
    ..ccd = true
    ..availableAt = DateTime.utc(2026, 1, 2, 3, 4, 5)
    ..expiresAt = DateTime.utc(2026, 2, 3, 4, 5, 6)
    ..refreshAt = DateTime.utc(2026, 3, 4, 5, 6, 7)
    ..createdAt = DateTime.utc(2026, 4, 5, 6, 7, 8)
    ..updatedAt = DateTime.utc(2026, 5, 6, 7, 8, 9)
    ..dataSignature = 'a-signature'
    ..sharedKeyStatus = 'shared'
    ..isPublic = true
    ..isHidden = true
    ..namespaceAware = false
    ..isBinary = true
    ..isEncrypted = true
    ..isCached = true
    ..sharedKeyEnc = 'shared-key-enc'
    ..pubKeyCS = 'checksum'
    ..pubKeyHash = PublicKeyHash('the-hash', 'sha512')
    ..encoding = 'base64'
    ..encKeyName = 'key_1.__shared_keys.wavi'
    ..encAlgo = 'AES/SIC/PKCS7Padding'
    ..ivNonce = 'the-nonce'
    ..skeEncKeyName = 'key_2.__public_keys.wavi'
    ..skeEncAlgo = 'RSA'
    ..immutable = true
    ..appMetadata = AppMetadata(
      providerId: 'at/symmetric/AES/GCM',
      additional: {'ckKid': 'abc123'},
    );

  test('a copy serialises identically to its original', () {
    final original = populated();

    expect(original.copy().toJson(), original.toJson(),
        reason: 'a field missing from copy() would differ here — which is the '
            'whole point of comparing against toJson() rather than naming the '
            'fields a second time');
  });

  test('a copy produces the same at-protocol fragment', () {
    final original = populated();

    expect(
        original.copy().toAtProtocolFragment(), original.toAtProtocolFragment(),
        reason: 'the fragment is what reaches the atServer, so a dropped field '
            'is a wire difference and not merely an in-memory one');
  });

  test('a copy of a default Metadata is a default Metadata', () {
    expect(Metadata().copy().toJson(), Metadata().toJson());
  });

  test('the copy is independent of the original', () {
    final original = populated();
    final copy = original.copy();

    original
      ..ttl = 999999
      ..immutable = false
      ..appMetadata = AppMetadata(providerId: 'legacy');

    expect(copy.ttl, 1000);
    expect(copy.immutable, isTrue);
    expect(copy.appMetadata?.providerId, 'at/symmetric/AES/GCM',
        reason: 'a caller that copies then edits the original must not find '
            'its copy changed underneath it');
  });
}
