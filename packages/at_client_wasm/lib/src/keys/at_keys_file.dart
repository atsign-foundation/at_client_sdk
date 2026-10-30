import 'dart:convert';

import 'package:at_auth/at_auth.dart' as auth;
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart' show AtException;

const _selfEncryptedFields = [
  auth.apkamPublicKey,
  auth.apkamPrivateKey,
  auth.defaultEncryptionPublicKey,
  auth.defaultEncryptionPrivateKey,
];

/// Decodes [text], the contents of a `.atKeys` file, into [auth.AtKeys].
///
/// The four legacy key fields are AES-CTR encrypted, zero IV, under the
/// file's own `selfEncryptionKey`; they are decrypted before parsing. Throws
/// [FormatException] when [text] is not a JSON object, and [AtException] when
/// a legacy field is present without a `selfEncryptionKey`.
Future<auth.AtKeys> decodeAtKeysFile(String text) async {
  final json = jsonDecode(text);
  if (json is! Map<String, dynamic>) {
    throw const FormatException('a .atKeys file holds a JSON object');
  }
  final present = _selfEncryptedFields.where(json.containsKey).toList();
  if (present.isEmpty) return auth.AtKeys.fromJson(json);

  final selfKey = json[auth.defaultSelfEncryptionKey] as String? ??
      (throw AtException('selfEncryptionKey is required to process the '
          'self-encrypted legacy atKeys fields'));
  final aes = AESEncryptionAlgo(AESKey(selfKey));
  final decrypted = Map<String, dynamic>.of(json);
  for (final field in present) {
    decrypted[field] = utf8.decode(await aes.decrypt(
        base64Decode(json[field] as String),
        iv: InitialisationVector.legacy()));
  }
  return auth.AtKeys.fromJson(decrypted);
}
