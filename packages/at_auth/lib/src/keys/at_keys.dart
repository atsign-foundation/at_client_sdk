import 'package:at_auth/src/keys/serialization/assurance.dart';
import 'package:at_auth/src/keys/types.dart';
import 'package:at_chops/at_chops.dart' hide AtPublicKey, AtPrivateKey;
import 'package:at_commons/at_commons.dart';
import 'package:at_auth/src/auth_constants.dart' as auth_constants;
import 'package:at_auth/src/exception/at_auth_exceptions.dart';

class AtKeys {
  static const supportedVersion = 1;
  static const _reservedTopLevelKeys = {'version', 'atSign', 'keys'};

  //todo: make non-nullable and final in v4
  Atsign? atsign;
  final Map<String, Map<CryptographicKeyType, AtKeysMaterial>>
      _materialsByKeyId = {};

  Iterable<AtKeysMaterial> get keyMaterials =>
      _materialsByKeyId.values.expand((byType) => byType.values);

  AtKeys({
    this.atsign,
    List<AtKeysMaterial> keysList = const [],
  }) {
    for (final key in keysList) {
      addKey(key);
    }
  }

  AtKeysMaterial? getMaterial(String keyId, CryptographicKeyType type) =>
      _materialsByKeyId[keyId]?[type];

  /// Returns every material sharing [keyId] — e.g. the public+private halves
  /// of one keypair.
  Iterable<AtKeysMaterial> materialsForKeyId(String keyId) =>
      _materialsByKeyId[keyId]?.values ?? const [];

  /// Returns every key material tagged with [enrollmentId] — the query-based
  /// replacement for the former atomic `AtKeyPackage` grouping.
  Iterable<AtKeysMaterial> keysForEnrollment(String enrollmentId) {
    return keyMaterials
        .where((material) => material.enrollmentId == enrollmentId);
  }

  void addKey(AtKeysMaterial material) {
    final byType = _materialsByKeyId.putIfAbsent(material.keyId, () => {});
    if (byType.containsKey(material.keyPartType)) {
      throw ArgumentError.value(material.keyId, 'key',
          'AtKeys already contains a ${material.keyPartType.name} material for this keyId');
    }
    byType[material.keyPartType] = material;
  }

  /// Decodes the v1 typed-keys document shape (`version`, `atSign`, `keys`,
  /// plus legacy fields flat at the top level). Legacy-only (pre-v1) json
  /// should be routed to [loadLegacy] instead. `keys` entries are parsed via
  /// [AtKeysRecord] only to group/validate them — the flattened
  /// [AtKeysMaterial]s are what's actually stored.
  factory AtKeys.fromDocumentJson(Map<String, dynamic> json) {
    const assurance = AtKeysAssurance();
    final version = assurance.expectInt(json['version'], 'version');
    if (version != supportedVersion) {
      throw AtKeysUnsupportedVersionException(
          'Unsupported atKeys version: $version');
    }

    final atsign =
        assurance.expectNonEmptyString(json['atSign'], 'atSign').toAtsign();
    final keysJson = assurance.expectList(json['keys'], 'keys');

    final keyRecords = keysJson.asMap().entries.map((entry) {
      final recordJson = assurance.expectMap(entry.value, 'keys[${entry.key}]');
      return AtKeysRecord.fromJson(recordJson, index: entry.key);
    }).toList();

    assurance.validateKeyRecords(keyRecords);

    final legacyJson = {
      for (final entry in json.entries)
        if (!_reservedTopLevelKeys.contains(entry.key)) entry.key: entry.value,
    };

    //form the new AtKeys
    AtKeys atKeys = AtKeys(
      atsign: atsign,
      keysList: keyRecords.expand((record) => record.materials.values).toList(),
    );

    // join them with the legacy format
    return AtKeys.fromJson(legacyJson, existing: atKeys);
  }

  /// Encodes this [AtKeys] to the v1 typed-keys document shape. Legacy fields
  /// merge flatly into the top level alongside `version`/`atSign`/`keys` —
  /// upgrading a legacy file is additive, not a format swap. Falls back to
  /// the legacy flat shape when there's no atSign and no typed key material.
  Map<String, dynamic> toDocumentJson() {
    if (atsign == null) {
      if (keyMaterials.isNotEmpty) {
        throw AtKeysValidationException(
            'atSign is required to serialize typed atKeys material');
      }
      return toJson();
    }
    return {
      ...toJson(),
      'version': supportedVersion,
      'atSign': atsign.toString(),
      'keys': _groupIntoRecords().map((record) => record.toJson()).toList(),
    };
  }

  /// Groups the flat [keyMaterials] back into [AtKeysRecord]s by `keyId`,
  /// purely to produce the wire's nested shape — never exposed publicly.
  List<AtKeysRecord> _groupIntoRecords() {
    final materialsByKeyId = <String, List<AtKeysMaterial>>{};
    for (final material in keyMaterials) {
      materialsByKeyId.putIfAbsent(material.keyId, () => []).add(material);
    }
    return materialsByKeyId.entries.map((entry) {
      final materials = entry.value;
      return AtKeysRecord(
        keyId: entry.key,
        keyGroup: materials.first.keyGroup,
        enrollmentId: materials.first.enrollmentId,
        materials: materials,
      );
    }).toList();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AtKeys) return false;
    return atsign == other.atsign &&
        enrollmentId == other.enrollmentId &&
        apkamPublicKey == other.apkamPublicKey &&
        apkamPrivateKey == other.apkamPrivateKey &&
        defaultEncryptionPublicKey == other.defaultEncryptionPublicKey &&
        defaultEncryptionPrivateKey == other.defaultEncryptionPrivateKey &&
        defaultSelfEncryptionKey == other.defaultSelfEncryptionKey &&
        apkamSymmetricKey == other.apkamSymmetricKey &&
        _mapEquals(metadata, other.metadata) &&
        _listEquals(keyMaterials.toList(), other.keyMaterials.toList());
  }

  @override
  int get hashCode => Object.hash(
        atsign,
        enrollmentId,
        apkamPublicKey,
        apkamPrivateKey,
        defaultEncryptionPublicKey,
        defaultEncryptionPrivateKey,
        defaultSelfEncryptionKey,
        apkamSymmetricKey,
        _metadataHash(metadata),
        Object.hashAll(keyMaterials),
      );

  // the LEGACY

  @Deprecated('hard-coded keys are legacy, see new methods')
  AtBytes? apkamPublicKey;
  @Deprecated('hard-coded keys are legacy, see new methods')
  AtBytes? apkamPrivateKey;
  @Deprecated('hard-coded keys are legacy, see new methods')
  AtBytes? defaultEncryptionPublicKey;
  @Deprecated('hard-coded keys are legacy, see new methods')
  AtBytes? defaultEncryptionPrivateKey;
  @Deprecated('hard-coded keys are legacy, see new methods')
  AtBytes? defaultSelfEncryptionKey;
  @Deprecated('hard-coded keys are legacy, see new methods')
  AtBytes? apkamSymmetricKey;
  @Deprecated('hard-coded keys are legacy, see new methods')
  String? enrollmentId;
  @Deprecated('hard-coded keys are legacy, see new methods')
  Map<String, dynamic> metadata = {};
  @Deprecated(
      'designed for legacy hard-coded atkeys, see serialization/resolver.dart')
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

  @Deprecated('designed for legacy loading of keys')
  factory AtKeys.fromJson(Map<String, dynamic> json, {AtKeys? existing}) {
    var keys = existing ?? AtKeys();
    keys
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

  @Deprecated('AtChops is being deprecated, by extension this method as well')
  AtChops toAtChops() {
    //if the keys contain an apkamSymmetricKey, they're a apkam key
    return switch (apkamSymmetricKey) {
      AtBytes() => _createApkamChops(this),
      null => _createPkamChops(this),
    };
  }

  @Deprecated('legacy, please use addKey to add additional keys.')
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
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) {
      return false;
    }
  }
  return true;
}

bool _mapEquals(Map<String, dynamic> left, Map<String, dynamic> right) {
  if (left.length != right.length) {
    return false;
  }
  for (final entry in left.entries) {
    if (!right.containsKey(entry.key) || right[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

int _metadataHash(Map<String, dynamic> metadata) {
  final entries = metadata.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  return Object.hashAll(
    entries.map((entry) => Object.hash(entry.key, entry.value)),
  );
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
    throw AtKeyNotFoundException(
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
