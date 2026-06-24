import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/serialization/document.dart';
import 'package:at_commons/at_commons.dart';

import '../atkeys.dart';

abstract class AtKeysResolver {
  AtKeysSet resolve(AtKeysDocument document);
  AtKeysDocument resolveToDocument(AtKeysSet keys);
}

class AtKeysDocumentResolver implements AtKeysResolver {
  const AtKeysDocumentResolver();

  static const int version = 2;

  @override
  AtKeysSet resolve(AtKeysDocument document) {
    final keyPairs = _resolveAsymmetricKeys(document.keys);
    final symmetricKeys = _resolveSymmetricKeys(document.keys);

    return WritableAtKeysSet(
      atsign: document.atsign.toAtsign(),
      enrollmentId: document.enrollmentId,
      keys: [
        ...keyPairs,
        ...symmetricKeys,
      ],
    );
  }

  List<AtKeyPair> _resolveAsymmetricKeys(List<KeyRecord> records) {
    final recordsByPairId = <String, Map<KeyRecordKind, KeyRecord>>{};

    for (final record in records.where((record) => record.isAsymmetric)) {
      final pairId = record.pairId!;
      final recordsByKind = recordsByPairId.putIfAbsent(
          pairId, () => <KeyRecordKind, KeyRecord>{});
      if (recordsByKind.containsKey(record.kind)) {
        throw AtKeysValidationException(
            'Duplicate asymmetric key for pairId "$pairId" and kind "${record.kind.jsonToken}"');
      }
      recordsByKind[record.kind] = record;
    }

    return [
      for (final entry in recordsByPairId.entries)
        _resolveAsymmetricPair(entry.key, entry.value),
    ];
  }

  AtKeyPair _resolveAsymmetricPair(
    String pairId,
    Map<KeyRecordKind, KeyRecord> recordsByKind,
  ) {
    final publicRecord = recordsByKind[KeyRecordKind.public];
    final privateRecord = recordsByKind[KeyRecordKind.private];
    if (publicRecord == null || privateRecord == null) {
      throw AtKeysValidationException(
          'Asymmetric pair "$pairId" must include public and private records');
    }
    _validatePairAgreement(pairId, publicRecord, privateRecord);

    return AtKeyPair(
      pairId: pairId,
      purpose: publicRecord.purpose,
      algorithm: publicRecord.algorithm,
      fingerprint: publicRecord.fingerprint,
      publicKey: publicRecord.bytes,
      privateKey: privateRecord.bytes,
      publicKeyProtection: publicRecord.protection,
      privateKeyProtection: privateRecord.protection,
      rotation: _mergeRotationField(
        pairId,
        publicRecord.rotation,
        privateRecord.rotation,
      ),
      operations: _mergeOperations(publicRecord, privateRecord),
    );
  }

  @override
  AtKeysDocument resolveToDocument(AtKeysSet keys) {
    return AtKeysDocument(
      version: version,
      atsign: keys.atsign.toString(),
      enrollmentId: keys.enrollmentId,
      keys: [
        for (final key in keys.keyPairs) ...[
          _unresolveAsymmetricKey(key, KeyRecordKind.public),
          _unresolveAsymmetricKey(key, KeyRecordKind.private),
        ],
        for (final key in keys.symmetricKeys)
          KeyRecord(
            id: key.id,
            purpose: key.purpose,
            kind: KeyRecordKind.symmetric,
            algorithm: key.algorithm,
            bytes: key.bytes,
            protection: key.protection,
            rotation: key.rotation,
            operations: key.operations,
          ),
      ],
    );
  }

  KeyRecord _unresolveAsymmetricKey(
    AtKeyPair key,
    KeyRecordKind kind,
  ) {
    return KeyRecord(
      id: '${key.pairId}-${kind.jsonToken}',
      pairId: key.pairId,
      purpose: key.purpose,
      kind: kind,
      algorithm: key.algorithm,
      fingerprint: key.fingerprint,
      bytes: kind == KeyRecordKind.public ? key.publicKey : key.privateKey,
      protection: kind == KeyRecordKind.public
          ? key.publicKeyProtection
          : key.privateKeyProtection,
      rotation: key.rotation,
      operations: key.operations,
    );
  }

  List<AtSymmetricKey> _resolveSymmetricKeys(List<KeyRecord> records) {
    return [
      for (final record in records.where(
        (record) => record.kind == KeyRecordKind.symmetric,
      ))
        AtSymmetricKey(
          id: record.id,
          purpose: record.purpose,
          algorithm: record.algorithm,
          bytes: record.bytes,
          protection: record.protection,
          rotation: record.rotation,
          operations: record.operations,
        ),
    ];
  }

  void _validatePairAgreement(
    String pairId,
    KeyRecord publicRecord,
    KeyRecord privateRecord,
  ) {
    if (publicRecord.purpose != privateRecord.purpose) {
      throw AtKeysValidationException(
          'Asymmetric pair "$pairId" has mismatched purposes');
    }
    if (publicRecord.algorithm != privateRecord.algorithm) {
      throw AtKeysValidationException(
          'Asymmetric pair "$pairId" has mismatched algorithms');
    }
    final publicFingerprint = publicRecord.fingerprint;
    final privateFingerprint = privateRecord.fingerprint;
    if ((publicFingerprint == null) != (privateFingerprint == null)) {
      throw AtKeysValidationException(
          'Asymmetric pair "$pairId" has mismatched fingerprints');
    }
    if (publicFingerprint != null &&
        privateFingerprint != null &&
        (publicFingerprint.algorithm != privateFingerprint.algorithm ||
            publicFingerprint.value != privateFingerprint.value)) {
      throw AtKeysValidationException(
          'Asymmetric pair "$pairId" has mismatched fingerprints');
    }
  }

  KeyRotation? _mergeRotationField(
    String pairId,
    KeyRotation? publicValue,
    KeyRotation? privateValue,
  ) {
    if (publicValue != null &&
        privateValue != null &&
        publicValue != privateValue) {
      throw AtKeysValidationException(
          'Asymmetric pair "$pairId" has mismatched rotation');
    }
    return publicValue ?? privateValue;
  }

  List<String> _mergeOperations(
    KeyRecord publicRecord,
    KeyRecord privateRecord,
  ) {
    return {
      ...publicRecord.operations,
      ...privateRecord.operations,
    }.toList();
  }
}
