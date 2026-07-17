import 'package:at_auth/src/keys/serialization/assurance.dart';
import 'package:at_auth/src/keys/serialization/atkey_material.dart';
import 'package:at_chops/at_chops.dart' hide AtPublicKey, AtPrivateKey;
import 'package:at_commons/at_commons.dart';
import 'package:at_auth/src/auth_constants.dart' as auth_constants;
import 'package:at_auth/src/exception/at_auth_exceptions.dart';

/// The in-memory model of an atsign's cryptographic keys.
///
/// An AtKeys instance always holds **plaintext** key material — every
/// at-rest concern (the passphrase envelope, self-encryption of the legacy
/// fields) lives in `FileAtKeysIo`, not here. Typed key material
/// ([AtKeysMaterial]) is added with [addKey], looked up by
/// `(keyId, keyPartType)` via [getKey] / [keysForKeyId] /
/// [keysForEnrollment], and retired (never removed) with [retireKey].
class AtKeys {
  static const supportedVersion = 1;
  static const _reservedTopLevelKeys = {'version', 'atsign', 'keys'};

  //todo: make non-nullable and final in v4
  Atsign? atsign;

  // Inner map keyed by keyPartType (see CryptographicKeyType for the known
  // tokens; unknown tokens are held too).
  final Map<String, Map<String, AtKeysMaterial>> _materialsByKeyId = {};

  Iterable<AtKeysMaterial> get keys =>
      _materialsByKeyId.values.expand((byType) => byType.values);

  AtKeys({
    this.atsign,
    List<AtKeysMaterial> keysList = const [],
  }) {
    for (final key in keysList) {
      addKey(key);
    }
  }

  /// Looks up one material by its `(keyId, keyPartType)` — [type] is a
  /// [CryptographicKeyType] token.
  AtKeysMaterial? getKey(String keyId, String type) =>
      _materialsByKeyId[keyId]?[type];

  /// Returns every material sharing [keyId] — e.g. the public+private halves
  /// of one keypair.
  ///
  /// Potentially might only contain a half of a keypair. Typically the public one.
  Iterable<AtKeysMaterial> keysForKeyId(String keyId) =>
      _materialsByKeyId[keyId]?.values ?? const [];

  /// Returns every material tagged with [enrollmentId].
  Iterable<AtKeysMaterial> keysForEnrollment(String enrollmentId) =>
      keys.where((material) => material.enrollmentId == enrollmentId);

  void addKey(AtKeysMaterial material) {
    const AtKeysAssurance().validateAddKey(existing: keys, candidate: material);
    _materialsByKeyId.putIfAbsent(
        material.keyId, () => {})[material.keyPartType] = material;
  }

  /// Marks every material of [keyId] as [to] ([KeyPartStatus.retired] by
  /// default). Key material is never removed — retired/dead bytes are still
  /// needed to decrypt data they protected — so this is the delete
  /// operation. Status only moves forward (active → retired → dead): a
  /// same-status call is a no-op and a backward transition throws, as does
  /// an unknown [keyId] or `to: KeyPartStatus.active`.
  void retireKey(String keyId, {KeyPartStatus to = KeyPartStatus.retired}) {
    if (to == KeyPartStatus.active) {
      throw ArgumentError.value(to, 'to', 'retireKey cannot reactivate a key');
    }
    final byType = _materialsByKeyId[keyId];
    if (byType == null) {
      throw ArgumentError.value(keyId, 'keyId', 'AtKeys has no such keyId');
    }
    for (final material in byType.values) {
      if (material.status.index > to.index) {
        throw ArgumentError.value(to, 'to',
            'cannot move keyId "$keyId" backward from ${material.status.name}');
      }
    }
    byType.updateAll((_, material) => material.withStatus(to));
  }

  /// Decodes the typed-keys document shape (`version`, `atsign`, `keys`,
  /// plus legacy fields flat at the top level). Json without a `version`
  /// field is accepted as the legacy flat shape (delegates to
  /// [_fromLegacyJson]); a `version` other than [supportedVersion] throws
  /// [AtKeysUnsupportedVersionException]. `keys` entries are parsed and
  /// validated by [parseAtKeysDocument], which returns the flattened
  /// [AtKeysMaterial]s that are actually stored.
  factory AtKeys.fromJson(Map<String, dynamic> json) {
    const assurance = AtKeysAssurance();
    // Legacy files have no version field - accept them as legacy.
    if (!json.containsKey('version')) {
      return AtKeys._fromLegacyJson(json);
    }
    final version = assurance.expectInt(json['version'], 'version');
    if (version != supportedVersion) {
      throw AtKeysUnsupportedVersionException(
          'Unsupported atKeys version: $version');
    }

    final atsign =
        assurance.expectNonEmptyString(json['atsign'], 'atsign').toAtsign();
    final keysJson = assurance.expectList(json['keys'], 'keys');

    final materials = parseAtKeysDocument(keysJson);
    assurance.validateKeyMaterials(materials);

    final legacyJson = {
      for (final entry in json.entries)
        if (!_reservedTopLevelKeys.contains(entry.key)) entry.key: entry.value,
    };

    //form the new AtKeys
    AtKeys atKeys = AtKeys(
      atsign: atsign,
      keysList: materials,
    );

    // join them with the legacy format
    return AtKeys._fromLegacyJson(legacyJson, existing: atKeys);
  }

  /// Encodes this [AtKeys] to the typed-keys document shape. Legacy fields
  /// merge flatly into the top level alongside `version`/`atsign`/`keys` —
  /// upgrading a legacy file is additive, not a format swap. Falls back to
  /// the legacy flat shape (see [_toLegacyJson]) when there's no atsign and
  /// no typed key material.
  ///
  /// All values are emitted plaintext; at-rest self-encryption of the legacy
  /// portion (and the optional passphrase envelope) is `FileAtKeysIo`'s job.
  Map<String, dynamic> toJson() {
    if (atsign == null) {
      if (keys.isNotEmpty) {
        throw AtKeysValidationException(
            'atsign is required to serialize typed atKeys material');
      }
      return _toLegacyJson();
    }
    return {
      ..._toLegacyJson(),
      'version': supportedVersion,
      'atsign': atsign.toString(),
      'keys': encodeAtKeysDocument(keys),
    };
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
        _materialsEqual(other);
  }

  /// Order-insensitive: two AtKeys holding the same materials are equal no
  /// matter the order they were added in.
  bool _materialsEqual(AtKeys other) {
    final materials = keys.toList();
    if (materials.length != other.keys.length) {
      return false;
    }
    return materials.every((material) =>
        other.getKey(material.keyId, material.keyPartType) == material);
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
        // Commutative fold so hashCode matches the order-insensitive equality.
        keys.fold<int>(0, (acc, material) => acc ^ material.hashCode),
      );

  // ───── Legacy flat fields ─────
  // A legacy .atKeys file is a flat JSON object of the six fields below plus
  // enrollmentId and arbitrary metadata. They stay readable/writable (and
  // merge flatly into the typed-keys document) so existing files keep working.

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

  /// Encodes just the legacy flat shape — the hard-coded fields plus
  /// [metadata] — with no `version`/`atsign`/`keys`.
  Map<String, dynamic> _toLegacyJson() {
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

  static AtKeys _fromLegacyJson(Map<String, dynamic> json, {AtKeys? existing}) {
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
    throw AtPrivateKeyNotFoundException('PKAM mode requires apkamPrivateKey');
  }
  if (atKeys.apkamPublicKey == null) {
    throw AtKeyNotFoundException('PKAM mode requires apkamPublicKey');
  }
  if (atKeys.defaultEncryptionPublicKey == null) {
    throw AtKeyNotFoundException(
        'PKAM mode requires defaultEncryptionPublicKey');
  }
  if (atKeys.defaultSelfEncryptionKey == null) {
    throw AtKeyNotFoundException('PKAM mode requires defaultSelfEncryptionKey');
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
