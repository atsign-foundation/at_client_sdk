import 'package:at_commons/at_commons.dart';

enum KeyPurpose {
  pkam,
  encryption,
  signing,
  selfEncryption,
  apkamSymmetric,
}

KeyPurpose? keyPurposeFromJsonToken(String token) {
  return switch (token) {
    'pkam' => KeyPurpose.pkam,
    'encryption' => KeyPurpose.encryption,
    'signing' => KeyPurpose.signing,
    'self-encryption' => KeyPurpose.selfEncryption,
    'apkam-symmetric' => KeyPurpose.apkamSymmetric,
    _ => null,
  };
}

KeyPurpose? keyPurposeFromDefaultsKey(String key) {
  return switch (key) {
    'pkam' => KeyPurpose.pkam,
    'encryption' => KeyPurpose.encryption,
    'signing' => KeyPurpose.signing,
    'selfEncryption' => KeyPurpose.selfEncryption,
    'apkamSymmetric' => KeyPurpose.apkamSymmetric,
    _ => null,
  };
}

extension keyPurposeJson on KeyPurpose {
  String get jsonToken {
    return switch (this) {
      KeyPurpose.pkam => 'pkam',
      KeyPurpose.encryption => 'encryption',
      KeyPurpose.signing => 'signing',
      KeyPurpose.selfEncryption => 'self-encryption',
      KeyPurpose.apkamSymmetric => 'apkam-symmetric',
    };
  }

  String get defaultsKey {
    return switch (this) {
      KeyPurpose.pkam => 'pkam',
      KeyPurpose.encryption => 'encryption',
      KeyPurpose.signing => 'signing',
      KeyPurpose.selfEncryption => 'selfEncryption',
      KeyPurpose.apkamSymmetric => 'apkamSymmetric',
    };
  }

  bool get usesAsymmetricPair {
    return switch (this) {
      KeyPurpose.pkam || KeyPurpose.encryption || KeyPurpose.signing => true,
      KeyPurpose.selfEncryption || KeyPurpose.apkamSymmetric => false,
    };
  }
}


class AtKeysDefaults {
  final Map<KeyPurpose, String> values;

  const AtKeysDefaults({
    required this.values,
  });

  String? operator [](KeyPurpose purpose) => values[purpose];
}

class KeyFingerprint {
  final String algorithm;
  final AtBytes value;

  const KeyFingerprint({
    required this.algorithm,
    required this.value,
  });
}

class KeyProtection {
  final String keyRef;
  final String algorithm;
  final String iv;

  const KeyProtection({
    required this.keyRef,
    required this.algorithm,
    required this.iv,
  });
}

class AtKeysSet {
  final Atsign atSign;
  String? enrollmentId;
  final List<AtAsymmetricKey> asymmetricKeys;
  final List<AtSymmetricKey> symmetricKeys;
  final AtKeysDefaults defaults;

  AtKeysSet({
    required this.atSign,
    required this.asymmetricKeys,
    required this.symmetricKeys,
    required this.defaults,
    this.enrollmentId,
  });

  AtAsymmetricKey? getKeyPair(String pairId) {
    for (final key in asymmetricKeys) {
      if (key.pairId == pairId) {
        return key;
      }
    }
    return null;
  }

  AtSymmetricKey? getSymmetricKey(String id) {
    for (final key in symmetricKeys) {
      if (key.id == id) {
        return key;
      }
    }
    return null;
  }
}

class AtAsymmetricKey {
  final String pairId;
  final KeyPurpose purpose;
  final String algorithm;
  final KeyFingerprint? fingerprint;
  final AtBytes publicKey;
  final AtBytes privateKey;
  final KeyProtection? publicKeyProtection;
  final KeyProtection? privateKeyProtection;
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
  final KeyPurpose purpose;
  final String algorithm;
  final AtBytes bytes;
  final KeyProtection? protection;
  final String? status;
  final DateTime? createdAt;
  final DateTime? notAfter;
  final List<String> operations;

  const AtSymmetricKey({
    required this.id,
    required this.purpose,
    required this.algorithm,
    required this.bytes,
    this.protection,
    this.status,
    this.createdAt,
    this.notAfter,
    this.operations = const [],
  });
}
