import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_auth/src/auth_constants.dart' as auth_constants;
import 'package:at_auth/src/keys/atkeys.dart';

@Deprecated(
    'AtKeys are now the legacy model. Please use AtKeysSet, which is open ended id set of keys.')
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

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AtKeys) return false;
    return enrollmentId == other.enrollmentId &&
        apkamPublicKey == other.apkamPublicKey &&
        apkamPrivateKey == other.apkamPrivateKey &&
        defaultEncryptionPublicKey == other.defaultEncryptionPublicKey &&
        defaultEncryptionPrivateKey == other.defaultEncryptionPrivateKey &&
        defaultSelfEncryptionKey == other.defaultSelfEncryptionKey &&
        apkamSymmetricKey == other.apkamSymmetricKey;
  }

  @override
  int get hashCode => Object.hash(enrollmentId, metadata);

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

  static AtKeys fromAtKeysSet(AtKeysSet atKeysSet) {
    final pkamKeyPair = _keyPairForLegacyPurpose(
      atKeysSet,
      KeyPurposes.pkam,
    );
    final encryptionKeyPair = _keyPairForLegacyPurpose(
      atKeysSet,
      KeyPurposes.encryption,
    );
    final selfEncryptionKey = _symmetricKeyForLegacyPurpose(
      atKeysSet,
      KeyPurposes.selfEncryption,
    );
    final apkamSymmetricKey = _symmetricKeyForLegacyPurpose(
      atKeysSet,
      KeyPurposes.apkamSymmetric,
    );

    return AtKeys()
      ..apkamPublicKey = pkamKeyPair?.publicKey
      ..apkamPrivateKey = pkamKeyPair?.privateKey
      ..defaultEncryptionPublicKey = encryptionKeyPair?.publicKey
      ..defaultEncryptionPrivateKey = encryptionKeyPair?.privateKey
      ..defaultSelfEncryptionKey = selfEncryptionKey?.bytes
      ..apkamSymmetricKey = apkamSymmetricKey?.bytes
      ..enrollmentId = atKeysSet.enrollmentId;
  }

  AtKeysSet toAtKeysSet({Atsign? atsign}) {
    final keyPairs = <AtKeyPair>[
      if (apkamPublicKey != null || apkamPrivateKey != null)
        _legacyKeyPair(
          pairId: KeyPurposes.pkam,
          purpose: KeyPurposes.pkam,
          publicKey: apkamPublicKey,
          privateKey: apkamPrivateKey,
        ),
      if (defaultEncryptionPublicKey != null ||
          defaultEncryptionPrivateKey != null)
        _legacyKeyPair(
          pairId: KeyPurposes.encryption,
          purpose: KeyPurposes.encryption,
          publicKey: defaultEncryptionPublicKey,
          privateKey: defaultEncryptionPrivateKey,
        ),
    ];

    final symmetricKeys = <AtSymmetricKey>[
      if (defaultSelfEncryptionKey != null)
        _legacySymmetricKey(
          id: KeyPurposes.selfEncryption,
          purpose: KeyPurposes.selfEncryption,
          bytes: defaultSelfEncryptionKey!,
        ),
      if (apkamSymmetricKey != null)
        _legacySymmetricKey(
          id: KeyPurposes.apkamSymmetric,
          purpose: KeyPurposes.apkamSymmetric,
          bytes: apkamSymmetricKey!,
        ),
    ];

    return WritableAtKeysSet(
      atsign: _resolveAtSign(this, atsign),
      enrollmentId: enrollmentId,
      keys: [
        ...keyPairs,
        ...symmetricKeys,
      ],
    );
  }
}

// Splitting these implementations to improve understanding

/// APKAMChops should contain:
///   - apkamPublicKey
///   - apkamPrivateKey
///   - usual PKAM keys
/// As well as APKAMChops can potentially have two states:
///   - approval
///   - post approval
/// During approval: the enroll will wait to confirm via PKAM
/// post approval: we fetch the defaultEncryptionPrivateKey & defaultSelfEncryptionKey
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

AtChops _createPkamChops(AtKeys atKeys) {
  if (atKeys.defaultEncryptionPrivateKey == null) {
    throw AtPrivateKeyNotFoundException(
        'PKAM mode requires defaultEncryptionPrivateKey');
  }
  if (atKeys.apkamPrivateKey == null) {
    throw AtPrivateKeyNotFoundException(
        'PKAM mode requries defaultPkamPrivateKey');
  }

  final atEncryptionKeyPair = AtEncryptionKeyPair.create(
    atKeys.defaultEncryptionPublicKey!.toString(),
    atKeys.defaultEncryptionPrivateKey!.toString(),
  );

  final atPkamKeyPair = AtPkamKeyPair.create(
    atKeys.apkamPublicKey!.toString(),
    atKeys.apkamPrivateKey!.toString(),
  );

  final atChopsKeys = AtChopsKeys.create(atEncryptionKeyPair, atPkamKeyPair)
    ..selfEncryptionKey = AESKey(atKeys.defaultSelfEncryptionKey!.toString());

  return AtChopsImpl(atChopsKeys);
}

bool _existsAndNotNull(Map<String, dynamic> json, String key) {
  return json.containsKey(key) && json[key] != null;
}

AtKeyPair _legacyKeyPair({
  required String pairId,
  required String purpose,
  required AtBytes? publicKey,
  required AtBytes? privateKey,
}) {
  if (publicKey == null || privateKey == null) {
    throw StateError(
      'Legacy AtKeys $purpose key pair requires both public and private keys',
    );
  }

  return AtKeyPair(
    pairId: pairId,
    purpose: purpose,
    algorithm: _legacyRsaAlgorithm,
    publicKey: publicKey,
    privateKey: privateKey,
  );
}

AtSymmetricKey _legacySymmetricKey({
  required String id,
  required String purpose,
  required AtBytes bytes,
}) {
  return AtSymmetricKey(
    id: id,
    purpose: purpose,
    algorithm: _legacyAesAlgorithm,
    bytes: bytes,
  );
}

Atsign _resolveAtSign(AtKeys atKeys, Atsign? atsign) {
  if (atsign != null) {
    return atsign;
  }

  final metadataAtSign = atKeys.metadata['atsign'] ?? atKeys.metadata['atSign'];
  if (metadataAtSign is Atsign) {
    return metadataAtSign;
  }
  if (metadataAtSign is String && metadataAtSign.isNotEmpty) {
    return metadataAtSign.toAtsign();
  }

  throw ArgumentError(
    'AtKeysSet requires an atSign. Pass atsign or set AtKeys.metadata["atsign"].',
  );
}

AtKeyPair? _keyPairForLegacyPurpose(AtKeysSet atKeysSet, String purpose) {
  final keyPairs =
      atKeysSet.keyPairs.where((key) => key.purpose == purpose).toList();
  return _singleLegacyKeyMaterial(keyPairs, purpose);
}

AtSymmetricKey? _symmetricKeyForLegacyPurpose(
  AtKeysSet atKeysSet,
  String purpose,
) {
  final symmetricKeys =
      atKeysSet.symmetricKeys.where((key) => key.purpose == purpose).toList();
  return _singleLegacyKeyMaterial(symmetricKeys, purpose);
}

T? _singleLegacyKeyMaterial<T extends AtKeysMaterial>(
  List<T> keys,
  String purpose,
) {
  if (keys.isEmpty) {
    return null;
  }

  final activeKeys = keys
      .where((key) =>
          switch (key) {
            AtKeyPair(:final rotation) => rotation?.status,
            AtSymmetricKey(:final rotation) => rotation?.status,
          } ==
          KeyRotationStatus.active)
      .toList();
  final candidates = activeKeys.isEmpty ? keys : activeKeys;

  if (candidates.length > 1) {
    throw StateError(
      'Legacy AtKeys supports only one $purpose key, found ${candidates.length}',
    );
  }

  return candidates.single;
}

const _legacyRsaAlgorithm = 'rsa-2048';
const _legacyAesAlgorithm = 'aes-256';
