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

  /// Files a freshly minted APKAM keypair as an enrollment's
  /// **authentication** material, under the keyId
  /// `apkam:<enrollmentId>:<generation>`.
  ///
  /// This is the one place that id shape is written. The generation suffix is
  /// what lets one enrollment hold more than one APKAM keypair over its life:
  /// a rotation retires the previous generation and files the next under the
  /// same enrollment id, and the retired bytes stay in the file because they
  /// are still needed to verify what they signed. Without the suffix the map
  /// key `(keyId, keyPartType)` collides and a second generation cannot be
  /// filed at all.
  ///
  /// [algorithm] is a [KeyAlgorithmType] token, which is also the enrollment
  /// `signingAlgo` spelling — the keyfile and the wire use the same strings.
  /// Both halves are filed and share one creation timestamp: the private one
  /// is what PKAM signs with, and the public one is what a reader checks this
  /// enrollment's server-side record against.
  ///
  /// Filed as `privateAuthentication` / `publicAuthentication`, NOT as
  /// signing material: this keypair authenticates, and an enrollment's
  /// signing keys are separate material with their own lifecycle.
  void fileApkamMaterial({
    required String enrollmentId,
    required String algorithm,
    required String publicKey,
    required String privateKey,
  }) {
    final now = DateTime.now().toUtc();
    final keyId = 'apkam:$enrollmentId:${nextApkamGeneration(enrollmentId)}';
    addKey(AtKeysMaterial(
        keyId: keyId,
        enrollmentId: enrollmentId,
        keyPartType: CryptographicKeyType.privateAuthentication,
        keyAlgorithmType: algorithm,
        bytes: AtBytes.fromString(privateKey),
        createdAt: now));
    addKey(AtKeysMaterial(
        keyId: keyId,
        enrollmentId: enrollmentId,
        keyPartType: CryptographicKeyType.publicAuthentication,
        keyAlgorithmType: algorithm,
        bytes: AtBytes.fromString(publicKey),
        createdAt: now));
  }

  /// The generation number [fileApkamMaterial] will use next for
  /// [enrollmentId] — one past the highest already filed, or 1.
  ///
  /// Derived from the keyIds present rather than counted separately, so it
  /// cannot drift from what the file actually holds. An id whose suffix is
  /// not a number is ignored rather than rejected: a keyfile written by a
  /// build that spells generations differently must still be readable.
  int nextApkamGeneration(String enrollmentId) {
    final prefix = 'apkam:$enrollmentId:';
    var highest = 0;
    for (final keyId in _materialsByKeyId.keys) {
      if (!keyId.startsWith(prefix)) continue;
      final generation = int.tryParse(keyId.substring(prefix.length));
      if (generation != null && generation > highest) {
        highest = generation;
      }
    }
    return highest + 1;
  }

  /// Files a signing keypair for [enrollmentId] under
  /// `sign:<enrollmentId>:<algorithm>:<generation>`.
  ///
  /// Algorithm leads the id because algorithm is what a verifier selects on:
  /// an enrollment holds one active signing key per algorithm, and an
  /// envelope's signature names which one produced it. The generation suffix
  /// allows rotating a signing key within its algorithm.
  void fileSigningMaterial({
    required String enrollmentId,
    required String algorithm,
    required String publicKey,
    required String privateKey,
  }) {
    final now = DateTime.now().toUtc();
    final keyId = 'sign:$enrollmentId:$algorithm:'
        '${nextSigningGeneration(enrollmentId, algorithm)}';
    addKey(AtKeysMaterial(
        keyId: keyId,
        enrollmentId: enrollmentId,
        keyPartType: CryptographicKeyType.privateSigning,
        keyAlgorithmType: algorithm,
        bytes: AtBytes.fromString(privateKey),
        createdAt: now));
    addKey(AtKeysMaterial(
        keyId: keyId,
        enrollmentId: enrollmentId,
        keyPartType: CryptographicKeyType.publicVerification,
        keyAlgorithmType: algorithm,
        bytes: AtBytes.fromString(publicKey),
        createdAt: now));
  }

  /// The generation [fileSigningMaterial] will use next for [enrollmentId]'s
  /// [algorithm] — one past the highest already filed, or 1.
  int nextSigningGeneration(String enrollmentId, String algorithm) {
    final prefix = 'sign:$enrollmentId:$algorithm:';
    var highest = 0;
    for (final keyId in _materialsByKeyId.keys) {
      if (!keyId.startsWith(prefix)) continue;
      final generation = int.tryParse(keyId.substring(prefix.length));
      if (generation != null && generation > highest) {
        highest = generation;
      }
    }
    return highest + 1;
  }

  /// Adopts [materials] — what an enrollment request's metadataBuilder filed
  /// into the construction keys it was handed — tagged with the enrollment id
  /// they now belong to.
  ///
  /// Every other field rides across untouched, `createdAt` and `status`
  /// included: at_auth carries key material and does not interpret it, so the
  /// only thing an adoption may change is whose enrollment it is.
  void adoptMaterials(Iterable<AtKeysMaterial> materials,
      {required String enrollmentId}) {
    for (final material in materials.toList()) {
      addKey(AtKeysMaterial(
          keyId: material.keyId,
          enrollmentId: enrollmentId,
          keyPartType: material.keyPartType,
          keyAlgorithmType: material.keyAlgorithmType,
          bytes: material.bytes,
          operations: material.operations,
          createdAt: material.createdAt,
          status: material.status));
    }
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

  /// Retires [keyId] and files [replacements] in one call — a key rotation,
  /// as a single operation rather than two the caller has to sequence.
  ///
  /// The order is forced and it is the only order that works. The invariants
  /// permit one ACTIVE material per (enrollment, role), so the outgoing key
  /// must be retired before the incoming one can be filed; add-then-retire is
  /// rejected by [addKey] before the retire ever runs. Leaving callers to
  /// sequence that themselves means a keyfile flush can land between the two
  /// steps, and a crash there leaves an enrollment with no active key of that
  /// role at all.
  ///
  /// Rolls back if any replacement is refused, so a rejected rotation leaves
  /// the outgoing key active rather than retiring it and then failing to
  /// install its successor — which would be worse than not rotating.
  ///
  /// [to] is how far the outgoing material moves: `retired` by default,
  /// `dead` when it should no longer be used even to verify history.
  void replaceKey(String keyId, Iterable<AtKeysMaterial> replacements,
      {KeyPartStatus to = KeyPartStatus.retired}) {
    final outgoing = keysForKeyId(keyId).toList();
    if (outgoing.isEmpty) {
      throw ArgumentError.value(keyId, 'keyId', 'AtKeys has no such keyId');
    }
    retireKey(keyId, to: to);
    final filed = <AtKeysMaterial>[];
    try {
      for (final replacement in replacements) {
        addKey(replacement);
        filed.add(replacement);
      }
    } on Object {
      // Undo, so a refused rotation is a no-op rather than a keyfile with the
      // old key retired and no new one in its place.
      for (final material in filed) {
        _materialsByKeyId[material.keyId]?.remove(material.keyPartType);
        if (_materialsByKeyId[material.keyId]?.isEmpty ?? false) {
          _materialsByKeyId.remove(material.keyId);
        }
      }
      for (final material in outgoing) {
        _materialsByKeyId[material.keyId]![material.keyPartType] = material;
      }
      rethrow;
    }
  }

  /// The enrollment this keyfile authenticates as, or null when it holds no
  /// typed authentication material (a legacy keyfile, whose APKAM keypair
  /// lives in the flat fields).
  ///
  /// Derived rather than stored. A pointer field duplicating this would be a
  /// second writer able to disagree with the material itself, and after a
  /// retrofit — when the file legitimately holds a capped enrollment's keys
  /// alongside the live one's — disagreeing means authenticating as the
  /// wrong enrollment. The document-wide single-active-authentication
  /// invariant is what makes the answer unique.
  String? get activeEnrollmentId => keys
      .where((m) =>
          m.keyPartType == CryptographicKeyType.privateAuthentication &&
          m.status == KeyPartStatus.active)
      .map((m) => m.enrollmentId)
      .firstOrNull;

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
    if (keys.isEmpty) {
      // A keyfile holding no typed material comes back exactly as it went in,
      // byte for byte. The version marker describes what the document
      // CONTAINS, and a `version: 1` document with an empty `keys` array says
      // nothing a legacy file does not — so emitting one would stamp every
      // file a new build merely opened, producing a diff on files nobody
      // meant to change. The marker appears the moment there is typed
      // material to mark.
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

  /// AtChops for [enrollmentId]'s typed signing material, sharing the
  /// keyfile's flat encryption and self-encryption keys.
  ///
  /// This is how a second enrollment held in the same keyfile — a
  /// self-retrofit's, whose APKAM keypair lives in the typed `keys` section
  /// under its own enrollment id while the flat fields keep carrying the
  /// original enrollment's — becomes able to authenticate at all;
  /// [toAtChops] reads only the flat fields and cannot see it.
  ///
  /// The signing keypair rides the String-typed pkam slot as base64 of the
  /// raw key bytes. A caller authenticating over at_lookup must also set
  /// `signingAlgoType` to what [signingAlgorithmForEnrollment] reports, or
  /// the signature is produced by the wrong routine.
  AtChops toAtChopsForEnrollment(String enrollmentId) {
    final materials = keysForEnrollment(enrollmentId);
    final privateSigning = materials
        .where((m) =>
            m.keyPartType == CryptographicKeyType.privateAuthentication &&
            m.status == KeyPartStatus.active)
        .firstOrNull;
    final publicVerification = materials
        .where((m) =>
            m.keyPartType == CryptographicKeyType.publicAuthentication &&
            m.status == KeyPartStatus.active)
        .firstOrNull;
    if (privateSigning == null || publicVerification == null) {
      throw AtKeyNotFoundException(
          'AtKeys holds no active authentication keypair for enrollment '
          '$enrollmentId');
    }

    final atChopsKeys = AtChopsKeys.create(
        AtEncryptionKeyPair.create(
          defaultEncryptionPublicKey?.toString() ?? '',
          defaultEncryptionPrivateKey?.toString() ?? '',
        ),
        AtPkamKeyPair.create(publicVerification.bytes.toString(),
            privateSigning.bytes.toString()));
    if (defaultSelfEncryptionKey != null) {
      atChopsKeys.selfEncryptionKey =
          AESKey(defaultSelfEncryptionKey!.toString());
    }
    return AtChopsImpl(atChopsKeys);
  }

  /// The algorithm of [enrollmentId]'s active **authentication** material —
  /// what PKAM must sign with — or null when the enrollment has no typed
  /// authentication material this build recognises (a legacy flat-fields
  /// enrollment reports null: its RSA keypair lives in the flat fields, not
  /// the typed section).
  ///
  /// Named for signing because that is what `SigningAlgoType` calls it and
  /// what the wire's `signingAlgo` field carries; the key it describes is the
  /// authentication keypair, not the enrollment's attestation signing keys.
  SigningAlgoType? signingAlgorithmForEnrollment(String enrollmentId) {
    final material = keysForEnrollment(enrollmentId)
        .where((m) =>
            m.keyPartType == CryptographicKeyType.privateAuthentication &&
            m.status == KeyPartStatus.active)
        .firstOrNull;
    if (material == null) return null;
    return SigningAlgoType.values
        .where((a) => a.name == material.keyAlgorithmType)
        .firstOrNull;
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
