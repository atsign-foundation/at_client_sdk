import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/crypto/legacy/string_crypto.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  group('a corrupted key is not quoted in the exception', () {
    final String key = AESKey.generate(32).key;
    final AESEncryptionAlgo algorithm =
        AESEncryptionAlgo(AESKey('!${key.substring(1)}'));
    final InitialisationVector iv = InitialisationVector.random(16);

    Matcher withoutKey<T extends AtException>() => throwsA(predicate((e) =>
        e is T &&
        !e.toString().contains(key.substring(1)) &&
        !e.getTraceMessage().contains(key.substring(1)) &&
        e.message == 'FormatException'));

    test('encryptStringToBase64', () async {
      await expectLater(() => encryptStringToBase64('abcd', algorithm, iv: iv),
          withoutKey<AtEncryptionException>());
    });

    test('decryptStringFromBase64', () async {
      await expectLater(
          () => decryptStringFromBase64(base64Encode(Uint8List(16)), algorithm,
              iv: iv),
          withoutKey<AtDecryptionException>());
    });
  });

  test('an Error from the cipher is reported by type', () async {
    final RsaEncryptionAlgo algorithm =
        RsaEncryptionAlgo.fromKeyPair(RsaKeyPair.generate());
    await expectLater(
        () => decryptStringFromBase64(base64Encode(Uint8List(256)), algorithm),
        throwsA(predicate((e) =>
            e is AtDecryptionException && e.message == 'ArgumentError')));
  });
}
