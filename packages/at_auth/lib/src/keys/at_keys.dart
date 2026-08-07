import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';

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
///
/// [atsign], [enrollmentId] and the typed materials are the document's
/// structural content ([KeyIds.reservedTopLevelKeys]); anything else a keyfile
/// carries at its top level is kept verbatim in [metadata] and round-trips
/// untouched. The two never mix: a metadata key that collides with a structural
/// or key-material field is dropped rather than allowed to shadow it.
final class AtKeys {
  static const supportedVersion = 1;

  final Atsign atsign;
  List<NamespacePermission>? namespaces;

  /// The enrollment this keyset belongs to.
  ///
  /// Set once — when the atServer allocates it during onboarding or enrollment
  /// approval. `WrittenAtKeysIo.flush` will accept setting it on a keyfile that
  /// carried none, but rejects repointing an existing one at a different
  /// enrollment (see `AtKeysAssurance.validateMapUpdate`).
  String? enrollmentId;

  // Inner map keyed by keyPartType (see CryptographicKeyType for the known
  // tokens; unknown tokens are held too).
  final Map<String, Map<String, AtKeysMaterial>> _materialsByKeyId = {};

  Iterable<AtKeysMaterial> get keys =>
      _materialsByKeyId.values.expand((byType) => byType.values);

  AtKeys({
    required this.atsign,
    List<AtKeysMaterial> keysList = const [],
    this.namespaces,
    this.enrollmentId,
  }) {
    for (final key in keysList) {
      addKey(key);
    }
  }

  /// Mints a brand-new key set for [atsign] — the post-quantum material
  /// (ML-DSA-65 for APKAM signing, X-Wing for encryption) always, and the
  /// legacy RSA/AES fields too unless [mintLegacy] is false.
  ///
  /// Nothing here touches the atServer: the caller is responsible for
  /// enrolling the generated public keys and for setting [enrollmentId] if
  /// the server allocates it.
  ///
  /// **`mintLegacy: false` is not yet proven end to end.** A post-quantum-only
  /// keyset authenticates as far as this package is concerned — under
  /// `ApkamSigningScheme.postQuantum` it signs PKAM with ML-DSA-65 — but whether the
  /// atServer verifies that signature is a server-side question, not settled
  /// here. It also cannot authenticate at all under the default
  /// `ApkamSigningScheme.legacy`. Leave [mintLegacy] at its default unless you are
  /// specifically exercising the PQ material.
  static Future<AtKeys> generate(
    Atsign atsign, {
    String? enrollmentId,
    bool mintLegacy = true,
  }) async {
    final keys = AtKeys(
      atsign: atsign,
      keysList: await _generatePqKeys(),
      enrollmentId: enrollmentId,
    );
    if (mintLegacy) {
      await keys._mintLegacyKeys();
    }
    return keys;
  }

  /// The post-quantum half of [generate], on its own: the ML-DSA-65 APKAM
  /// keypair and the X-Wing encryption keypair, ready to be added to an
  /// [AtKeys].
  ///
  /// This is what an enrollment mints for itself
  /// (`ApkamSigningScheme.mintKeys`), so a keyset minted at enrollment time and
  /// one minted at activation time carry the same material under the same
  /// `keyId`s.
  ///
  /// [enrollmentId] is null when the atServer has not allocated one yet, which
  /// is the case at enrollment-submit time.
  static Future<List<AtKeysMaterial>> generatePQEnrollmentPackage(
    Atsign atsign,
    String? enrollmentId,
  ) async {
    List<AtKeysMaterial> list = [];
    final mldsa = await MlDsa65PureDartAlgo().generateKeyPair();
    list.add(AtKeysMaterial(
      keyId: KeyIds.apkamPQ,
      keyPartType: CryptographicKeyType.publicVerification,
      keyAlgorithmType: KeyAlgorithmType.mlDsa65,
      bytes: mldsa.publicKey,
      createdAt: DateTime.timestamp(),
    ));
    list.add(AtKeysMaterial(
      keyId: KeyIds.apkamPQ,
      keyPartType: CryptographicKeyType.privateSigning,
      keyAlgorithmType: KeyAlgorithmType.mlDsa65,
      bytes: mldsa.secretKey,
      createdAt: DateTime.timestamp(),
    ));

    final xwing = await XWingPureDartAlgo.instance.generateKeyPair();
    list.add(AtKeysMaterial(
      keyId: KeyIds.keyPackageXWing,
      keyPartType: CryptographicKeyType.publicEncryption,
      keyAlgorithmType: KeyAlgorithmType.xWing,
      bytes: xwing.publicKey,
      createdAt: DateTime.timestamp(),
    ));
    list.add(AtKeysMaterial(
      keyId: KeyIds.keyPackageXWing,
      keyPartType: CryptographicKeyType.privateDecryption,
      keyAlgorithmType: KeyAlgorithmType.xWing,
      bytes: xwing.secretKey,
      createdAt: DateTime.timestamp(),
    ));
    return list;
  }

  static Future<List<AtKeysMaterial>> _generatePqKeys() async {
    List<AtKeysMaterial> list = [];
    final mldsa = await MlDsa65PureDartAlgo().generateKeyPair();
    list.add(AtKeysMaterial(
      keyId: KeyIds.apkamPQ,
      keyPartType: CryptographicKeyType.publicVerification,
      keyAlgorithmType: KeyAlgorithmType.mlDsa65,
      bytes: mldsa.publicKey,
      createdAt: DateTime.timestamp(),
    ));
    list.add(AtKeysMaterial(
      keyId: KeyIds.apkamPQ,
      keyPartType: CryptographicKeyType.privateSigning,
      keyAlgorithmType: KeyAlgorithmType.mlDsa65,
      bytes: mldsa.secretKey,
      createdAt: DateTime.timestamp(),
    ));

    final xwing = await XWingPureDartAlgo.instance.generateKeyPair();
    list.add(AtKeysMaterial(
      keyId: KeyIds.globalXWing,
      keyPartType: CryptographicKeyType.publicEncryption,
      keyAlgorithmType: KeyAlgorithmType.xWing,
      bytes: xwing.publicKey,
      createdAt: DateTime.timestamp(),
    ));
    list.add(AtKeysMaterial(
      keyId: KeyIds.globalXWing,
      keyPartType: CryptographicKeyType.privateDecryption,
      keyAlgorithmType: KeyAlgorithmType.xWing,
      bytes: xwing.secretKey,
      createdAt: DateTime.timestamp(),
    ));
    return list;
  }

  Future<void> _mintLegacyKeys() async {
    // RSA-2048 keypairs, DER-encoded exactly as an .atKeys file carries them.
    final rsa = RsaSigningAlgo();
    final apkamRsaKeypair = await rsa.generateKeyPair();
    final atEncryptionKeyPair = await rsa.generateKeyPair();
    // The constructor argument is a length in BYTES: AES-256 is 32, not 256.
    final aes = AesCtrEncryptionAlgo(32);

    apkamPublicKey = AtBytes(apkamRsaKeypair.publicKey);
    apkamPrivateKey = AtBytes(apkamRsaKeypair.secretKey);
    defaultEncryptionPublicKey = AtBytes(atEncryptionKeyPair.publicKey);
    defaultEncryptionPrivateKey = AtBytes(atEncryptionKeyPair.secretKey);
    defaultSelfEncryptionKey = AtBytes(aes.generateKey());
    apkamSymmetricKey = AtBytes(aes.generateKey());
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

  /// Marks every material of [keyId] as [KeyPartStatus.active] — the promotion
  /// that happens once the atServer has accepted the key the material was
  /// waiting on ([KeyPartStatus.pendingEnrollment] or
  /// [KeyPartStatus.pendingCramDeletion]).
  ///
  /// The counterpart of [retireKey]: this is the one transition that moves a
  /// status *forward into* active, so it is the only way out of a pending
  /// state. Promoting anything else throws, as does an unknown [keyId].
  void promoteKey(String keyId) {
    final byType = _materialsByKeyId[keyId];
    if (byType == null) {
      throw ArgumentError.value(keyId, 'keyId', 'AtKeys has no such keyId');
    }
    const promotable = {
      KeyPartStatus.pendingEnrollment,
      KeyPartStatus.pendingCramDeletion,
    };
    for (final material in byType.values) {
      if (!promotable.contains(material.status)) {
        throw ArgumentError.value(
          material.status,
          'status',
          'cannot move a non-pending key status to active',
        );
      }
    }
    byType
        .updateAll((_, material) => material.withStatus(KeyPartStatus.active));
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
    // enrollmentId is a structural field that sits at the top level of both the
    // legacy and the typed shape, so it is read once here for either path.
    final enrollmentId = assurance.optionalString(
        json[AtConstants.enrollmentId], AtConstants.enrollmentId);
    // Legacy files have no version field - accept them as legacy. A legacy
    // file doesn't store the atsign, so the reader supplies it.
    if (!json.containsKey('version')) {
      return AtKeys._fromLegacyJson(
        json,
        atsign: atsign,
        enrollmentId: enrollmentId,
      );
    }
    final version = assurance.expectInt(json['version'], 'version');
    if (version != supportedVersion) {
      throw AtKeysUnsupportedVersionException(
          'Unsupported atKeys version: $version');
    }

    final namespacesJson =
        assurance.optionalStringList(json['namespaces'], 'namespaces');
    final List<NamespacePermission> namespaces = [];
    for (var namespace in namespacesJson) {
      namespaces.add(NamespacePermission.fromString(namespace));
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
        if (!KeyIds.reservedTopLevelKeys.contains(entry.key))
          entry.key: entry.value,
    };

    //form the new AtKeys
    AtKeys atKeys = AtKeys(
      atsign: atsignFromDoc,
      namespaces: namespaces,
      keysList: materials,
      enrollmentId: enrollmentId,
    );

    // join them with the legacy format
    return AtKeys._fromLegacyJson(legacyJson, existing: atKeys);
  }

  /// Encodes this [AtKeys] to the typed-keys document shape. Legacy fields
  /// merge flatly into the top level alongside the structural fields
  /// (`version`/`atsign`/`enrollmentId`/`keys`) — upgrading a legacy file is
  /// additive, not a format swap.
  ///
  /// All values are emitted plaintext; at-rest self-encryption of the legacy
  /// portion (and the optional passphrase envelope) is `FileAtKeysIo`'s job.
  Map<String, dynamic> toJson() {
    return {
      for (final entry in metadata.entries)
        if (KeyIds.isMetadata(entry.key)) entry.key: entry.value,
      ..._legacySchemaJson(),
      KeyIds.version: supportedVersion,
      KeyIds.atsign: atsign.toString(),
      AtConstants.enrollmentId: enrollmentId,
      // A JSON array of "ns:rw" tokens — [fromJson] reads it back with
      // AtKeysAssurance.optionalStringList, which rejects anything else.
      AtConstants.apkamNamespaces:
          namespaces?.map((n) => n.toString()).toList(),
      KeyIds.keys: encodeAtKeysDocument(keys),
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

  /// Deprecated in favour of typed material ([AtKeysMaterial] via [addKey] /
  /// [getKey]), but **still required** and therefore not removable yet: PKAM
  /// signs with [apkamPrivateKey] under the default `ApkamSigningScheme.legacy`,
  /// `FileAtKeysIo`
  /// self-encrypts four of these fields at rest, and enrollment reads
  /// [apkamSymmetricKey] / [defaultEncryptionPrivateKey] /
  /// [defaultSelfEncryptionKey]. They can only go once ML-DSA PKAM is verified
  /// against the atServer — until then the deprecation marks direction of
  /// travel, not an available replacement.
  static const _legacyFieldDeprecation =
      'legacy flat-file key material: prefer typed AtKeysMaterial (addKey/'
      'getKey) for new material. Still load-bearing for PKAM signing, at-rest '
      'self-encryption and enrollment, so it cannot be removed yet.';

  @Deprecated(_legacyFieldDeprecation)
  AtBytes? apkamPublicKey;
  @Deprecated(_legacyFieldDeprecation)
  AtBytes? apkamPrivateKey;
  @Deprecated(_legacyFieldDeprecation)
  AtBytes? defaultEncryptionPublicKey;
  @Deprecated(_legacyFieldDeprecation)
  AtBytes? defaultEncryptionPrivateKey;
  @Deprecated(_legacyFieldDeprecation)
  AtBytes? defaultSelfEncryptionKey;
  @Deprecated(_legacyFieldDeprecation)
  AtBytes? apkamSymmetricKey;

  /// Top-level keyfile fields this version does not recognise, kept verbatim
  /// so a file written by a newer client survives a read-modify-flush here.
  ///
  /// Not deprecated: this is the supported forward-compatibility escape hatch,
  /// and it has no replacement. What counts as metadata is decided solely by
  /// [KeyIds.isMetadata] — a structural or key-material field is never copied
  /// in here, so metadata can never shadow one.
  Map<String, dynamic> metadata = {};

  /// Encodes just the legacy flat key material — exactly
  /// [KeyIds.keySchemaList], each field emitted even when null. Carries no
  /// structural field and no [metadata]; [toJson] assembles those around it.
  Map<String, dynamic> _legacySchemaJson() {
    return {
      KeyIds.apkamPublicKey: apkamPublicKey?.toString(),
      KeyIds.apkamPrivateKey: apkamPrivateKey?.toString(),
      KeyIds.defaultEncryptionPublicKey: defaultEncryptionPublicKey?.toString(),
      KeyIds.defaultEncryptionPrivateKey:
          defaultEncryptionPrivateKey?.toString(),
      KeyIds.defaultSelfEncryptionKey: defaultSelfEncryptionKey?.toString(),
      KeyIds.apkamSymmetricKey: apkamSymmetricKey?.toString(),
    };
  }

  /// Reads the legacy flat key material out of [json] onto [existing] (the
  /// typed path) or onto a fresh [AtKeys] for [atsign] (the legacy path).
  ///
  /// [enrollmentId] is supplied by [fromJson], which reads it structurally for
  /// both shapes; nothing here touches it. Anything in [json] that
  /// [KeyIds.isMetadata] accepts is kept verbatim as [metadata].
  static AtKeys _fromLegacyJson(Map<String, dynamic> json,
      {AtKeys? existing, Atsign? atsign, String? enrollmentId}) {
    var keys = existing ??
        AtKeys(
            atsign: atsign ??
                (throw AtKeysValidationException(
                    'atsign is required to read a legacy .atKeys file '
                    '(it is not stored in the file)')),
            enrollmentId: enrollmentId);
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
          : null;
    for (var entry in json.entries) {
      if (KeyIds.isMetadata(entry.key)) {
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
