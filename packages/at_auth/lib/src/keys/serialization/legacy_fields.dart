import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/src/auth_constants.dart' as auth_constants;
import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/serialization/base64_field.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';

/// Reads the text of a plain (not passphrase-protected) `.atKeys` file.
///
/// Web-safe, unlike [FileAtKeysIo]: a browser that has the file's text, from a
/// file picker, has no path to give it.
///
/// Throws [AtKeysFormatException] when [text] is not a JSON object.
Future<AtKeys> parseAtKeysFile(String text) async {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException catch (e) {
    throw AtKeysFormatException.notJson('the atKeys file', e);
  }
  if (decoded is! Map<String, dynamic>) {
    throw AtKeysFormatException.notAnObject('the atKeys file');
  }
  return AtKeys.fromJson(await selfDecryptLegacyFields(decoded));
}

const _selfEncryptedLegacyFields = [
  auth_constants.apkamPublicKey,
  auth_constants.apkamPrivateKey,
  auth_constants.defaultEncryptionPublicKey,
  auth_constants.defaultEncryptionPrivateKey,
];

Future<Map<String, dynamic>> selfEncryptLegacyFields(
    Map<String, dynamic> document) {
  return _applyToLegacyFields(
      document,
      (algorithm, _, value) async => base64.encode(await algorithm.encrypt(
          Uint8List.fromList(utf8.encode(value)),
          iv: InitialisationVector.legacy())));
}

Future<Map<String, dynamic>> selfDecryptLegacyFields(
    Map<String, dynamic> document) {
  return _applyToLegacyFields(
      document,
      (algorithm, field, value) async => utf8.decode(await algorithm.decrypt(
          decodeBase64Field(value, field),
          iv: InitialisationVector.legacy())));
}

/// Applies [transform] to whichever of the self-encrypted legacy fields the
/// document holds, under the key it carries in the clear.
///
/// The all-zero initialisation vector both transforms pass makes this an
/// at-rest format rather than a choice: every `.atKeys` file on disk was
/// written that way, and `legacy_field_self_encryption_test.dart` pins the
/// bytes against openssl.
Future<Map<String, dynamic>> _applyToLegacyFields(
  Map<String, dynamic> document,
  Future<String> Function(
          AESEncryptionAlgo algorithm, String field, String value)
      transform,
) async {
  final present = _selfEncryptedLegacyFields
      .where((field) => document[field] != null)
      .toList();
  if (present.isEmpty) {
    return document;
  }
  final selfEncryptionKey =
      document[auth_constants.defaultSelfEncryptionKey] as String?;
  if (selfEncryptionKey == null) {
    throw AtException(
        'selfEncryptionKey is required to process the self-encrypted legacy atKeys fields');
  }
  // NOTE: a malformed key fails here, by field name, not inside the cipher.
  decodeBase64Field(selfEncryptionKey, auth_constants.defaultSelfEncryptionKey);
  final algorithm = AESEncryptionAlgo(AESKey(selfEncryptionKey));
  final result = Map<String, dynamic>.from(document);
  for (final field in present) {
    result[field] =
        await transform(algorithm, field, document[field] as String);
  }
  return result;
}
