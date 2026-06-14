import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/util/at_client_util.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:crypton/crypton.dart';
import 'package:test/test.dart';

void main() {
  group('A group of update builder tests', () {
    test('test non public key', () {
      var builder = UpdateVerbBuilder()
        ..atKey.key = 'privatekey:at_pkam_privatekey';
      var updateKey = builder.buildKey();
      expect(updateKey, 'privatekey:at_pkam_privatekey');
    });

    test('test public key', () {
      var builder = UpdateVerbBuilder()
        ..atKey = (AtKey()
          ..key = 'phone'
          ..sharedBy = 'alice'
          ..metadata = (Metadata()..isPublic = true));
      var updateKey = builder.buildKey();
      expect(updateKey, 'public:phone@alice');
    });

    test('test key sharedwith another atsign', () {
      var builder = UpdateVerbBuilder()
        ..atKey = (AtKey()
          ..key = 'phone'
          ..sharedWith = 'bob'
          ..sharedBy = 'alice');
      var updateKey = builder.buildKey();
      expect(updateKey, '@bob:phone@alice');
    });
  });

  group('A group of get secondary info tests', () {
    test('get secondary url and port', () {
      var url = 'atsign.com:6400';
      var secondaryInfo = AtClientUtil.getSecondaryInfo(url);
      expect(secondaryInfo[0], 'atsign.com');
      expect(secondaryInfo[1], '6400');
    });

    test('url is null', () {
      String? url;
      var secondaryInfo = AtClientUtil.getSecondaryInfo(url);
      expect(secondaryInfo.length, 0);
    });

    test('url is empty', () {
      var url = '';
      var secondaryInfo = AtClientUtil.getSecondaryInfo(url);
      expect(secondaryInfo.length, 0);
    });
  });

  group('A group of prepareMetadata tests', () {
    test('prepareMetadata decodes appMetadata', () {
      final appMetadata = AppMetadata(providerId: 'test_provider');
      final metadata = AtClientUtil.prepareMetadata({
        AtConstants.isEncrypted: true,
        AtConstants.appMetadata: Metadata.encodeAppMetadata(appMetadata),
      }, false);

      expect(metadata?.appMetadata, appMetadata);
      expect(metadata?.isEncrypted, true);
    });
  });

  group('signChallenge (routed through at_chops PkamSigningAlgo)', () {
    test(
        'produces a valid RSA SHA-256 signature that verifies under the '
        'public key, byte-identical to the legacy crypton path', () {
      final keyPair = AtChopsUtil.generateAtPkamKeyPair();
      final privateKey = keyPair.atPrivateKey.privateKey;
      final publicKey = keyPair.atPublicKey.publicKey;
      const challenge = '  _0a1b2c3d@alice:deadbeefcafe  ';
      final trimmed = Uint8List.fromList(utf8.encode(challenge.trim()));

      final sig = AtClientUtil.signChallenge(challenge, privateKey);

      // Valid: verifies under the matching public key — what the atServer does.
      expect(
        RSAPublicKey.fromString(publicKey)
            .verifySHA256Signature(trimmed, base64Decode(sig)),
        isTrue,
      );

      // Byte-identical to the pre-migration crypton implementation
      // (RSA SHA-256 PKCS1v15 is deterministic).
      final legacy = base64Encode(
          RSAPrivateKey.fromString(privateKey).createSHA256Signature(trimmed));
      expect(sig, legacy);
    });
  });
}
