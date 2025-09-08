import 'package:at_commons/at_commons.dart';
import 'package:at_auth/src/auth_constants.dart' as auth_constants;

class AtKeys {
  AtBytes? apkamPublicKey;
  AtBytes? apkamPrivateKey;
  AtBytes? defaultEncryptionPublicKey;
  AtBytes? defaultEncryptionPrivateKey;
  AtBytes? defaultSelfEncryptionKey;
  AtBytes? apkamSymmetricKey;
  String? enrollmentId;

  AtKeys();

  Map<String, dynamic> toJson() {
    return {
      auth_constants.apkamPublicKey: apkamPublicKey?.toString(),
      auth_constants.apkamPrivateKey: apkamPrivateKey?.toString(),
      auth_constants.defaultEncryptionPublicKey: defaultEncryptionPublicKey?.toString(),
      auth_constants.defaultEncryptionPrivateKey: defaultEncryptionPrivateKey?.toString(),
      auth_constants.defaultSelfEncryptionKey: defaultSelfEncryptionKey?.toString(),
      auth_constants.apkamSymmetricKey: apkamSymmetricKey?.toString(),
      'enrollmentId': enrollmentId
    };
  }

  factory AtKeys.fromJson(Map<String, dynamic> json) {
    return AtKeys()
      ..apkamPublicKey = _existsAndNotNull(json, auth_constants.apkamPublicKey)
          ? AtBytes.fromString(json[auth_constants.apkamPublicKey])
          : null
      ..apkamPrivateKey = _existsAndNotNull(json, auth_constants.apkamPrivateKey)
          ? AtBytes.fromString(json[auth_constants.apkamPrivateKey])
          : null
      ..defaultEncryptionPublicKey =
          _existsAndNotNull(json, auth_constants.defaultEncryptionPublicKey)
              ? AtBytes.fromString(json[auth_constants.defaultEncryptionPublicKey])
              : null
      ..defaultEncryptionPrivateKey =
          _existsAndNotNull(json, auth_constants.defaultEncryptionPrivateKey)
              ? AtBytes.fromString(json[auth_constants.defaultEncryptionPrivateKey])
              : null
      ..defaultSelfEncryptionKey =
          _existsAndNotNull(json, auth_constants.defaultSelfEncryptionKey)
              ? AtBytes.fromString(json[auth_constants.defaultSelfEncryptionKey])
              : null
      ..apkamSymmetricKey = _existsAndNotNull(json, auth_constants.apkamSymmetricKey)
          ? AtBytes.fromString(json[auth_constants.apkamSymmetricKey])
          : null
      ..enrollmentId =
          _existsAndNotNull(json, 'enrollmentId') ? json['enrollmentId'] : null;
  }
}

bool _existsAndNotNull(Map<String, dynamic> json, String key) {
  return json.containsKey(key) && json[key] != null;
}
