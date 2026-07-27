import 'package:at_auth/src/keys/serialization/assurance.dart';
import 'package:at_auth/src/keys/serialization/atkey_material.dart';
import 'package:at_auth/src/keys/serialization/auth_bootstrap.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_auth/src/exception/at_auth_exceptions.dart';

/// The in-memory model of an atsign's cryptographic keys.
///
/// An AtKeys instance always holds **plaintext** key material — every
/// at-rest concern (the passphrase envelope, self-encryption of the legacy
/// fields) lives in `FileAtKeysIo`, not here. Typed key material
/// ([AtKeysMaterial]) is added with [addKey], looked up by
/// `(keyId, keyPartType)` via [getKey] / [keysForKeyId], and retired (never
/// removed) with [retireKey]. The whole [AtKeys] belongs to a single
/// enrollment ([enrollmentId]); every material under it belongs to that
/// enrollment.
final class AtKeys {
  static const supportedVersion = 1;
  static const _reservedTopLevelKeys = {'version', 'atsign', 'keys'};

  Atsign atsign;
  String? enrollmentId;

  // Inner map keyed by keyPartType (see CryptographicKeyType for the known
  // tokens; unknown tokens are held too).
  final Map<String, Map<String, AtKeysMaterial>> _materialsByKeyId = {};

  Iterable<AtKeysMaterial> get keys =>
      _materialsByKeyId.values.expand((byType) => byType.values);

  AtKeys({
    required this.atsign,
    List<AtKeysMaterial> keysList = const [],
    String? enrollmentId,
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
  factory AtKeys.fromJson(Map<String, dynamic> json, {Atsign? atsign}) {
    const assurance = AtKeysAssurance();
    // Legacy files have no version field - accept them as legacy. A legacy
    // file doesn't store the atsign, so the reader supplies it.
    if (!json.containsKey('version')) {
      return AtKeys._fromLegacyJson(json, atsign: atsign);
    }
    final version = assurance.expectInt(json['version'], 'version');
    if (version != supportedVersion) {
      throw AtKeysUnsupportedVersionException(
          'Unsupported atKeys version: $version');
    }

    final atsignFromDoc =
        assurance.expectNonEmptyString(json['atsign'], 'atsign').toAtsign();
    if (atsign != null && atsign != atsignFromDoc) {
      throw AtKeysValidationException(
          'atsign $atsign does not match the keyfile atsign $atsignFromDoc');
    }
    final keysJson = assurance.expectList(json['keys'], 'keys');

    final materials = parseAtKeysDocument(keysJson);

    final legacyJson = {
      for (final entry in json.entries)
        if (!_reservedTopLevelKeys.contains(entry.key)) entry.key: entry.value,
    };

    //form the new AtKeys
    AtKeys atKeys = AtKeys(
      atsign: atsignFromDoc,
      keysList: materials,
    );

    // join them with the legacy format
    return AtKeys._fromLegacyJson(legacyJson, existing: atKeys);
  }

  /// Encodes this [AtKeys] to the typed-keys document shape. Legacy fields
  /// merge flatly into the top level alongside `version`/`atsign`/`keys` —
  /// upgrading a legacy file is additive, not a format swap.
  ///
  /// All values are emitted plaintext; at-rest self-encryption of the legacy
  /// portion (and the optional passphrase envelope) is `FileAtKeysIo`'s job.
  Map<String, dynamic> toJson() {
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
  Map<String, dynamic> metadata = {};

  /// Encodes just the legacy flat shape — the hard-coded fields plus
  /// [metadata] — with no `version`/`atsign`/`keys`.
  Map<String, dynamic> _toLegacyJson() {
    return {
      KeyIds.apkamPublicKey: apkamPublicKey?.toString(),
      KeyIds.apkamPrivateKey: apkamPrivateKey?.toString(),
      KeyIds.defaultEncryptionPublicKey: defaultEncryptionPublicKey?.toString(),
      KeyIds.defaultEncryptionPrivateKey:
          defaultEncryptionPrivateKey?.toString(),
      KeyIds.defaultSelfEncryptionKey: defaultSelfEncryptionKey?.toString(),
      KeyIds.apkamSymmetricKey: apkamSymmetricKey?.toString(),
      AtConstants.enrollmentId: enrollmentId,
      for (var entry in metadata.entries)
        if (!KeyIds.keySchemaList.contains(entry.key)) entry.key: entry.value
    };
  }

  static AtKeys _fromLegacyJson(Map<String, dynamic> json,
      {AtKeys? existing, Atsign? atsign}) {
    var keys = existing ??
        AtKeys(
            atsign: atsign ??
                (throw AtKeysValidationException(
                    'atsign is required to read a legacy .atKeys file '
                    '(it is not stored in the file)')));
    keys
      ..apkamPublicKey = _existsAndNotNull(json, KeyIds.apkamPublicKey)
          ? AtBytes.fromString(json[KeyIds.apkamPublicKey])
          : null
      ..apkamPrivateKey = _existsAndNotNull(json, KeyIds.apkamPrivateKey)
          ? AtBytes.fromString(json[KeyIds.apkamPrivateKey])
          : null
      ..defaultEncryptionPublicKey =
          _existsAndNotNull(json, KeyIds.defaultEncryptionPublicKey)
              ? AtBytes.fromString(json[KeyIds.defaultEncryptionPublicKey])
              : null
      ..defaultEncryptionPrivateKey =
          _existsAndNotNull(json, KeyIds.defaultEncryptionPrivateKey)
              ? AtBytes.fromString(json[KeyIds.defaultEncryptionPrivateKey])
              : null
      ..defaultSelfEncryptionKey =
          _existsAndNotNull(json, KeyIds.defaultSelfEncryptionKey)
              ? AtBytes.fromString(json[KeyIds.defaultSelfEncryptionKey])
              : null
      ..apkamSymmetricKey = _existsAndNotNull(json, KeyIds.apkamSymmetricKey)
          ? AtBytes.fromString(json[KeyIds.apkamSymmetricKey])
          : null
      ..enrollmentId =
          _existsAndNotNull(json, 'enrollmentId') ? json['enrollmentId'] : null;
    for (var entry in json.entries) {
      if (!KeyIds.keySchemaList.contains(entry.key)) {
        keys.metadata[entry.key] = entry.value;
      }
    }
    return keys;
  }
}

// metadata holds JSON-derived values, so nested maps/lists compare by
// identity under ==; compare (and hash) them structurally instead.
bool _mapEquals(Map<String, dynamic> left, Map<String, dynamic> right) {
  return _deepEquals(left, right);
}

bool _deepEquals(Object? left, Object? right) {
  if (left is Map && right is Map) {
    if (left.length != right.length) {
      return false;
    }
    for (final key in left.keys) {
      if (!right.containsKey(key) || !_deepEquals(left[key], right[key])) {
        return false;
      }
    }
    return true;
  }
  if (left is List && right is List) {
    if (left.length != right.length) {
      return false;
    }
    for (var i = 0; i < left.length; i++) {
      if (!_deepEquals(left[i], right[i])) {
        return false;
      }
    }
    return true;
  }
  return left == right;
}

int _metadataHash(Map<String, dynamic> metadata) => _deepHash(metadata);

int _deepHash(Object? value) {
  if (value is Map) {
    final entries = value.entries.toList()
      ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
    return Object.hashAll(entries.map(
        (entry) => Object.hash(entry.key.toString(), _deepHash(entry.value))));
  }
  if (value is List) {
    return Object.hashAll(value.map(_deepHash));
  }
  return value.hashCode;
}

bool _existsAndNotNull(Map<String, dynamic> json, String key) {
  return json.containsKey(key) && json[key] != null;
}
