import 'package:at_auth/src/keys/types.dart';
import 'package:at_chops/at_chops.dart' hide AtPublicKey, AtPrivateKey;
import 'package:at_commons/at_commons.dart';
import 'package:at_auth/src/auth_constants.dart' as auth_constants;

class AtKeys {
  final Atsign? atsign;
  final Map<Type, Map<String, AtKeysMaterial>> _keysByType = {};
  final List<AtKeysMaterial> _keyMaterials = [];

  Iterable<AtKeysMaterial> get keyMaterials => List.unmodifiable(_keyMaterials);

  // will become the default ctor for v4
  AtKeys({
    this.atsign,
    List<AtKeysMaterial> keysList = const [],
    Map<String, dynamic>? legacyJson,
  }) {
    for (final key in keysList) {
      switch (key) {
        case AtPublicKey():
          //uses the pairId in their respective map
          addKey<AtPublicKey>(key.pairId, key);
        case AtPrivateKey():
          //uses the pairId in their respective map
          addKey<AtPrivateKey>(key.pairId, key);
        case AtSymmetricKey():
          //uses id in their respective map
          addKey<AtSymmetricKey>(key.id, key);
        case AtKeyPackage():
          //uses enrollmentId in their respective map
          addKey<AtKeyPackage>(key.enrollmentId, key);
      }
    }
  }

  T? getKey<T extends AtKeysMaterial>(String id) {
    final key = _keysByType[T]?[id];
    return key is T ? key : null;
  }

  void addKey<T extends AtKeysMaterial>(
    String id,
    T key,
  ) {
    final keysForType = _keysByType.putIfAbsent(T, () => {});
    if (keysForType.containsKey(id)) {
      throw ArgumentError.value(id, 'primaryId',
          'Duplicate $T with their unique privateId, see AtKeys ctor for the respective id');
    }
    keysForType[id] = key;
    _keyMaterials.add(key);
  }

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

  @Deprecated(
      'designed for legacy hard-coded atkeys, see serialization/resolver.dart')
  factory AtKeys.fromJson(Map<String, dynamic> json) {
    var keys = AtKeys();
    return loadLegacy(keys, json);
  }

  @Deprecated('designed for legacy loading of keys')
  static AtKeys loadLegacy(AtKeys keys, Map<String, dynamic>? json) {
    if (json == null) return keys;
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
