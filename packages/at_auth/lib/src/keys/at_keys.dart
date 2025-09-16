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
  Map<String, dynamic> metadata = {};

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
    var keys = AtKeys()
      ..apkamPublicKey = _existsAndNotNull(json, auth_constants.apkamPublicKey)
          ? AtBytes.fromString(json[auth_constants.apkamPublicKey])
          : null
      ..apkamPrivateKey = _existsAndNotNull(json, auth_constants.apkamPrivateKey)
          ? AtBytes.fromString(json[auth_constants.apkamPrivateKey])
          : null
      ..defaultEncryptionPublicKey = _existsAndNotNull(json, auth_constants.defaultEncryptionPublicKey)
          ? AtBytes.fromString(json[auth_constants.defaultEncryptionPublicKey])
          : null
      ..defaultEncryptionPrivateKey = _existsAndNotNull(json, auth_constants.defaultEncryptionPrivateKey)
          ? AtBytes.fromString(json[auth_constants.defaultEncryptionPrivateKey])
          : null
      ..defaultSelfEncryptionKey = _existsAndNotNull(json, auth_constants.defaultSelfEncryptionKey)
          ? AtBytes.fromString(json[auth_constants.defaultSelfEncryptionKey])
          : null
      ..apkamSymmetricKey = _existsAndNotNull(json, auth_constants.apkamSymmetricKey)
          ? AtBytes.fromString(json[auth_constants.apkamSymmetricKey])
          : null
      ..enrollmentId = _existsAndNotNull(json, 'enrollmentId') ? json['enrollmentId'] : null;
    if (_existsAndNotNull(json, 'metadata')) {
      for (var entry in (json['metadata'] as Map).entries) {
        keys.metadata[entry.key] = entry.value;
      }
    }
    return keys;
  }

  AtKeys copyWith(AtKeys other) {
    var keys = AtKeys()
      ..apkamPublicKey = other.apkamPublicKey ?? apkamPublicKey
      ..apkamPrivateKey = other.apkamPrivateKey ?? apkamPrivateKey
      ..defaultEncryptionPublicKey = other.defaultEncryptionPublicKey ?? defaultEncryptionPublicKey
      ..defaultEncryptionPrivateKey = other.defaultEncryptionPrivateKey ?? defaultEncryptionPrivateKey
      ..defaultSelfEncryptionKey = other.defaultSelfEncryptionKey ?? defaultSelfEncryptionKey
      ..apkamSymmetricKey = other.apkamSymmetricKey ?? apkamSymmetricKey
      ..enrollmentId = other.enrollmentId ?? enrollmentId;
    if (other.metadata.isNotEmpty) {
      keys.metadata.addAll(other.metadata);
    }
    return keys;
  }
}

bool _existsAndNotNull(Map<String, dynamic> json, String key) {
  return json.containsKey(key) && json[key] != null;
}
