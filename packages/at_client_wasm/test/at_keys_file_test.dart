// ignore_for_file: deprecated_member_use
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart' as auth;
import 'package:at_chops/at_chops.dart';
import 'package:at_client_wasm/src/keys/at_keys_file.dart';
import 'package:at_commons/at_commons.dart' show AtException;
import 'package:test/test.dart';

final _selfKey = base64Encode(Uint8List.fromList(List.generate(32, (i) => i)));

Future<String> _selfEncrypt(String plain) async => base64Encode(
    await AESEncryptionAlgo(AESKey(_selfKey))
        .encrypt(utf8.encode(plain), iv: InitialisationVector.legacy()));

void main() {
  group('decodeAtKeysFile', () {
    test('self-decrypts the four legacy fields', () async {
      final plain = {
        auth.apkamPublicKey: base64Encode([1, 2, 3]),
        auth.apkamPrivateKey: base64Encode([4, 5, 6]),
        auth.defaultEncryptionPublicKey: base64Encode([7, 8]),
        auth.defaultEncryptionPrivateKey: base64Encode([9]),
      };
      final file = {
        for (final MapEntry(:key, :value) in plain.entries)
          key: await _selfEncrypt(value),
        auth.defaultSelfEncryptionKey: _selfKey,
        auth.apkamSymmetricKey: base64Encode([42]),
      };

      final keys = await decodeAtKeysFile(jsonEncode(file));

      expect(keys.apkamPublicKey!.bytes, [1, 2, 3]);
      expect(keys.apkamPrivateKey!.bytes, [4, 5, 6]);
      expect(keys.defaultEncryptionPublicKey!.bytes, [7, 8]);
      expect(keys.defaultEncryptionPrivateKey!.bytes, [9]);
      expect(keys.defaultSelfEncryptionKey!.bytes, base64Decode(_selfKey));
      expect(keys.apkamSymmetricKey!.bytes, [42]);
    });

    test('passes a file with none of the legacy fields through', () async {
      final keys = await decodeAtKeysFile(
          jsonEncode({auth.apkamSymmetricKey: base64Encode([42])}));

      expect(keys.apkamSymmetricKey!.bytes, [42]);
      expect(keys.apkamPublicKey, isNull);
    });

    test('refuses legacy fields without a selfEncryptionKey', () async {
      final file = {auth.apkamPublicKey: await _selfEncrypt('x')};

      await expectLater(
          decodeAtKeysFile(jsonEncode(file)), throwsA(isA<AtException>()));
    });

    test('refuses text that is not a JSON object', () async {
      await expectLater(
          decodeAtKeysFile('[1, 2]'), throwsA(isA<FormatException>()));
    });
  });
}
