import 'package:at_chops/at_chops.dart';
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
      auth_constants.defaultEncryptionPublicKey:
          defaultEncryptionPublicKey?.toString(),
      auth_constants.defaultEncryptionPrivateKey:
          defaultEncryptionPrivateKey?.toString(),
      auth_constants.defaultSelfEncryptionKey:
          defaultSelfEncryptionKey?.toString(),
      auth_constants.apkamSymmetricKey: apkamSymmetricKey?.toString(),
      'enrollmentId': enrollmentId,
      for (var entry in metadata.entries)
        if (!auth_constants.keySchemaList.contains(entry.key))
          entry.key: entry.value
    };
  }

  factory AtKeys.fromJson(Map<String, dynamic> json) {
    var keys = AtKeys()
      ..apkamPublicKey = _existsAndNotNull(json, auth_constants.apkamPublicKey)
          ? AtBytes.fromString(json[auth_constants.apkamPublicKey])
          : null
      ..apkamPrivateKey =
          _existsAndNotNull(json, auth_constants.apkamPrivateKey)
              ? AtBytes.fromString(json[auth_constants.apkamPrivateKey])
              : null
      ..defaultEncryptionPublicKey = _existsAndNotNull(
              json, auth_constants.defaultEncryptionPublicKey)
          ? AtBytes.fromString(json[auth_constants.defaultEncryptionPublicKey])
          : null
      ..defaultEncryptionPrivateKey = _existsAndNotNull(
              json, auth_constants.defaultEncryptionPrivateKey)
          ? AtBytes.fromString(json[auth_constants.defaultEncryptionPrivateKey])
          : null
      ..defaultSelfEncryptionKey = _existsAndNotNull(
              json, auth_constants.defaultSelfEncryptionKey)
          ? AtBytes.fromString(json[auth_constants.defaultSelfEncryptionKey])
          : null
      ..apkamSymmetricKey =
          _existsAndNotNull(json, auth_constants.apkamSymmetricKey)
              ? AtBytes.fromString(json[auth_constants.apkamSymmetricKey])
              : null
      ..enrollmentId =
          _existsAndNotNull(json, 'enrollmentId') ? json['enrollmentId'] : null;
    for (var entry in json.entries) {
      if (!auth_constants.keySchemaList.contains(entry.key)) {
        keys.metadata[entry.key] = entry.value;
      }
    }
    return keys;
  }

  AtKeys copyWith(AtKeys other) {
    var keys = AtKeys()
      ..apkamPublicKey = other.apkamPublicKey ?? apkamPublicKey
      ..apkamPrivateKey = other.apkamPrivateKey ?? apkamPrivateKey
      ..defaultEncryptionPublicKey =
          other.defaultEncryptionPublicKey ?? defaultEncryptionPublicKey
      ..defaultEncryptionPrivateKey =
          other.defaultEncryptionPrivateKey ?? defaultEncryptionPrivateKey
      ..defaultSelfEncryptionKey =
          other.defaultSelfEncryptionKey ?? defaultSelfEncryptionKey
      ..apkamSymmetricKey = other.apkamSymmetricKey ?? apkamSymmetricKey
      ..enrollmentId = other.enrollmentId ?? enrollmentId;
    if (other.metadata.isNotEmpty) {
      keys.metadata.addAll(other.metadata);
    }
    return keys;
  }

  AtChops toAtChops() {
    //if the keys contain an apkamSymmetricKey, they're a apkam key
    return switch (apkamSymmetricKey) {
      AtBytes() => _createApkamChops(this),
      null => _createPkamChops(this),
    };
  }
}

// Splitting these implementations to improve understanding

///APKAMChops should contain:
AtChops _createApkamChops(AtKeys atKeys) {
  if (atKeys.apkamPublicKey == null) {
    AtKeyNotFoundException(
        "apkamPublicKey not found in AtKeys, unable to make atChops instance");
  }
  if (atKeys.apkamSymmetricKey == null) {
    throw AtKeyNotFoundException(
        "apkamSymmetricKey not found in AtKeys, unable to make atChops instance");
  }
  final atEncryptionKeyPair = AtEncryptionKeyPair.create(
    atKeys.defaultEncryptionPublicKey!.toString(),
    atKeys.defaultEncryptionPrivateKey == null
        ? ''
        : atKeys.defaultEncryptionPrivateKey!.toString(),
  );

  final atPkamKeyPair = AtPkamKeyPair.create(
    atKeys.apkamPublicKey!.toString(),
    atKeys.apkamPrivateKey!.toString(),
  );

  final atChopsKeys = AtChopsKeys.create(atEncryptionKeyPair, atPkamKeyPair)
    ..apkamSymmetricKey = AESKey(atKeys.apkamSymmetricKey!.toString());

  if (atKeys.defaultSelfEncryptionKey != null) {
    atChopsKeys.selfEncryptionKey =
        AESKey(atKeys.defaultSelfEncryptionKey!.toString());
  }

  return AtChopsImpl(atChopsKeys);
}

AtChops _createPkamChops(AtKeys atKeysFile) {
  if (atKeysFile.defaultEncryptionPrivateKey == null) {
    throw AtPrivateKeyNotFoundException(
        'PKAM mode requires defaultEncryptionPrivateKey');
  }

  final atEncryptionKeyPair = AtEncryptionKeyPair.create(
    atKeysFile.defaultEncryptionPublicKey!.toString(),
    atKeysFile.defaultEncryptionPrivateKey!.toString(),
  );

  final atPkamKeyPair = AtPkamKeyPair.create(
    atKeysFile.apkamPublicKey!.toString(),
    atKeysFile.apkamPrivateKey!.toString(),
  );

  final atChopsKeys = AtChopsKeys.create(atEncryptionKeyPair, atPkamKeyPair)
    ..selfEncryptionKey =
        AESKey(atKeysFile.defaultSelfEncryptionKey!.toString());

  return AtChopsImpl(atChopsKeys);
}

bool _existsAndNotNull(Map<String, dynamic> json, String key) {
  return json.containsKey(key) && json[key] != null;
}
