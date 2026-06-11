import 'package:at_auth/src/keys/at_keys_document.dart';
import 'package:at_auth/src/keys/legacy/at_keys.dart';
import 'package:at_commons/at_commons.dart';

class LegacyAtKeysAdapter {
  static const int version = 2;

  AtKeysDocument toDocument(String atSign, AtKeys atKeys) {
    final records = <KeyRecord>[
      if (atKeys.apkamPublicKey != null)
        _asymmetricRecord(
          id: 'legacy-pkam-public',
          pairId: 'legacy-pkam',
          purpose: KeyPurpose.pkam,
          kind: KeyRecordKind.public,
          value: atKeys.apkamPublicKey!.toString(),
        ),
      if (atKeys.apkamPrivateKey != null)
        _asymmetricRecord(
          id: 'legacy-pkam-private',
          pairId: 'legacy-pkam',
          purpose: KeyPurpose.pkam,
          kind: KeyRecordKind.private,
          value: atKeys.apkamPrivateKey!.toString(),
        ),
      if (atKeys.defaultEncryptionPublicKey != null)
        _asymmetricRecord(
          id: 'legacy-encryption-public',
          pairId: 'legacy-encryption',
          purpose: KeyPurpose.encryption,
          kind: KeyRecordKind.public,
          value: atKeys.defaultEncryptionPublicKey!.toString(),
        ),
      if (atKeys.defaultEncryptionPrivateKey != null)
        _asymmetricRecord(
          id: 'legacy-encryption-private',
          pairId: 'legacy-encryption',
          purpose: KeyPurpose.encryption,
          kind: KeyRecordKind.private,
          value: atKeys.defaultEncryptionPrivateKey!.toString(),
        ),
      if (atKeys.defaultSelfEncryptionKey != null)
        _symmetricRecord(
          id: 'legacy-self-encryption',
          purpose: KeyPurpose.selfEncryption,
          value: atKeys.defaultSelfEncryptionKey!.toString(),
        ),
      if (atKeys.apkamSymmetricKey != null)
        _symmetricRecord(
          id: 'legacy-apkam-symmetric',
          purpose: KeyPurpose.apkamSymmetric,
          value: atKeys.apkamSymmetricKey!.toString(),
        ),
    ];

    return AtKeysDocument(
      version: version,
      atsign: atSign,
      enrollmentId: atKeys.enrollmentId,
      keys: records,
      defaults: _defaultsFor(records),
    );
  }

  KeyRecord _asymmetricRecord({
    required String id,
    required String pairId,
    required KeyPurpose purpose,
    required KeyRecordKind kind,
    required String value,
  }) {
    return KeyRecord(
      id: id,
      pairId: pairId,
      purpose: purpose,
      kind: kind,
      algorithm: 'rsa-2048',
      bytes: AtBytes.fromString(value),
    );
  }

  KeyRecord _symmetricRecord({
    required String id,
    required KeyPurpose purpose,
    required String value,
  }) {
    return KeyRecord(
      id: id,
      purpose: purpose,
      kind: KeyRecordKind.symmetric,
      algorithm: 'aes-256',
      bytes: AtBytes.fromString(value),
    );
  }

  AtKeysDefaults _defaultsFor(List<KeyRecord> records) {
    final values = <KeyPurpose, String>{};
    if (_hasPair(records, 'legacy-pkam')) {
      values[KeyPurpose.pkam] = 'legacy-pkam';
    }
    if (_hasPair(records, 'legacy-encryption')) {
      values[KeyPurpose.encryption] = 'legacy-encryption';
    }
    if (_hasRecord(records, 'legacy-self-encryption')) {
      values[KeyPurpose.selfEncryption] = 'legacy-self-encryption';
    }
    if (_hasRecord(records, 'legacy-apkam-symmetric')) {
      values[KeyPurpose.apkamSymmetric] = 'legacy-apkam-symmetric';
    }
    return AtKeysDefaults(values: values);
  }

  bool _hasPair(List<KeyRecord> records, String pairId) {
    return records.any((record) => record.pairId == pairId);
  }

  bool _hasRecord(List<KeyRecord> records, String id) {
    return records.any((record) => record.id == id);
  }
}
