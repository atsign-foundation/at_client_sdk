enum AtKeyPurpose {
  pkam,
  encryption,
  signing,
  selfEncryption,
  apkamSymmetric,
}

enum AtKeyKind {
  public,
  private,
  symmetric,
}

AtKeyPurpose? atKeyPurposeFromJsonToken(String token) {
  return switch (token) {
    'pkam' => AtKeyPurpose.pkam,
    'encryption' => AtKeyPurpose.encryption,
    'signing' => AtKeyPurpose.signing,
    'self-encryption' => AtKeyPurpose.selfEncryption,
    'apkam-symmetric' => AtKeyPurpose.apkamSymmetric,
    _ => null,
  };
}

AtKeyPurpose? atKeyPurposeFromDefaultsKey(String key) {
  return switch (key) {
    'pkam' => AtKeyPurpose.pkam,
    'encryption' => AtKeyPurpose.encryption,
    'signing' => AtKeyPurpose.signing,
    'selfEncryption' => AtKeyPurpose.selfEncryption,
    'apkamSymmetric' => AtKeyPurpose.apkamSymmetric,
    _ => null,
  };
}

AtKeyKind? atKeyKindFromJsonToken(String token) {
  return switch (token) {
    'public' => AtKeyKind.public,
    'private' => AtKeyKind.private,
    'symmetric' => AtKeyKind.symmetric,
    _ => null,
  };
}

extension AtKeyPurposeJson on AtKeyPurpose {
  String get jsonToken {
    return switch (this) {
      AtKeyPurpose.pkam => 'pkam',
      AtKeyPurpose.encryption => 'encryption',
      AtKeyPurpose.signing => 'signing',
      AtKeyPurpose.selfEncryption => 'self-encryption',
      AtKeyPurpose.apkamSymmetric => 'apkam-symmetric',
    };
  }

  String get defaultsKey {
    return switch (this) {
      AtKeyPurpose.pkam => 'pkam',
      AtKeyPurpose.encryption => 'encryption',
      AtKeyPurpose.signing => 'signing',
      AtKeyPurpose.selfEncryption => 'selfEncryption',
      AtKeyPurpose.apkamSymmetric => 'apkamSymmetric',
    };
  }

  bool get usesAsymmetricPair {
    return switch (this) {
      AtKeyPurpose.pkam ||
      AtKeyPurpose.encryption ||
      AtKeyPurpose.signing =>
        true,
      AtKeyPurpose.selfEncryption || AtKeyPurpose.apkamSymmetric => false,
    };
  }
}

extension AtKeyKindJson on AtKeyKind {
  String get jsonToken {
    return switch (this) {
      AtKeyKind.public => 'public',
      AtKeyKind.private => 'private',
      AtKeyKind.symmetric => 'symmetric',
    };
  }

  bool get isAsymmetric => this != AtKeyKind.symmetric;
}

class AtKeysDocument {
  final int version;
  final String atSign;
  final String? enrollmentId;
  final List<AtKeyRecord> keys;
  final AtKeyDefaults defaults;
  final Map<String, dynamic> metadata;

  const AtKeysDocument({
    required this.version,
    required this.atSign,
    required this.keys,
    required this.defaults,
    this.enrollmentId,
    this.metadata = const {},
  });
}

class AtKeyDefaults {
  final Map<AtKeyPurpose, String> values;
  final Map<String, dynamic> metadata;

  const AtKeyDefaults({
    required this.values,
    this.metadata = const {},
  });

  String? operator [](AtKeyPurpose purpose) => values[purpose];
}

class AtKeyRecord {
  final String id;
  final String? pairId;
  final AtKeyPurpose purpose;
  final AtKeyKind kind;
  final String algorithm;
  final AtKeyFingerprint? fingerprint;
  final String? status;
  final DateTime? createdAt;
  final DateTime? notAfter;
  final List<String> operations;
  final AtKeyProtection? protection;
  final String value;
  final Map<String, dynamic> metadata;

  const AtKeyRecord({
    required this.id,
    required this.purpose,
    required this.kind,
    required this.algorithm,
    required this.value,
    this.pairId,
    this.fingerprint,
    this.status,
    this.createdAt,
    this.notAfter,
    this.operations = const [],
    this.protection,
    this.metadata = const {},
  });

  bool get isAsymmetric => kind.isAsymmetric;
}

class AtKeyFingerprint {
  final String algorithm;
  final String value;

  const AtKeyFingerprint({
    required this.algorithm,
    required this.value,
  });
}

class AtKeyProtection {
  final String type;
  final String keyRef;
  final String algorithm;
  final String iv;
  final Map<String, dynamic> metadata;

  const AtKeyProtection({
    required this.type,
    required this.keyRef,
    required this.algorithm,
    required this.iv,
    this.metadata = const {},
  });
}

class AtKeysSet {
  final String atSign;
  final String? enrollmentId;
  final List<AtAsymmetricKey> asymmetricKeys;
  final List<AtSymmetricKey> symmetricKeys;
  final AtKeyDefaults defaults;

  const AtKeysSet({
    required this.atSign,
    required this.asymmetricKeys,
    required this.symmetricKeys,
    required this.defaults,
    this.enrollmentId,
  });
}

class AtAsymmetricKey {
  final String pairId;
  final AtKeyPurpose purpose;
  final String algorithm;
  final AtKeyFingerprint? fingerprint;
  final String publicKey;
  final String privateKey;
  final AtKeyProtection? publicKeyProtection;
  final AtKeyProtection? privateKeyProtection;
  final String? status;
  final DateTime? createdAt;
  final DateTime? notAfter;
  final List<String> operations;

  const AtAsymmetricKey({
    required this.pairId,
    required this.purpose,
    required this.algorithm,
    required this.publicKey,
    required this.privateKey,
    this.fingerprint,
    this.publicKeyProtection,
    this.privateKeyProtection,
    this.status,
    this.createdAt,
    this.notAfter,
    this.operations = const [],
  });
}

class AtSymmetricKey {
  final String id;
  final AtKeyPurpose purpose;
  final String algorithm;
  final String value;
  final AtKeyProtection? protection;
  final String? status;
  final DateTime? createdAt;
  final DateTime? notAfter;
  final List<String> operations;

  const AtSymmetricKey({
    required this.id,
    required this.purpose,
    required this.algorithm,
    required this.value,
    this.protection,
    this.status,
    this.createdAt,
    this.notAfter,
    this.operations = const [],
  });
}
