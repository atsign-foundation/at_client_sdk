import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys_models.dart';

abstract class AtKeysResolver {
  AtKeysSet resolve(AtKeysDocument document);
}

class AtKeysDocumentResolver implements AtKeysResolver {
  @override
  AtKeysSet resolve(AtKeysDocument document) {
    final asymmetricKeys = _resolveAsymmetricKeys(document.keys);
    final symmetricKeys = _resolveSymmetricKeys(document.keys);
    _validateDefaults(
      document.defaults,
      records: document.keys,
      asymmetricKeys: asymmetricKeys,
      symmetricKeys: symmetricKeys,
    );

    return AtKeysSet(
      atSign: document.atSign,
      enrollmentId: document.enrollmentId,
      asymmetricKeys: asymmetricKeys,
      symmetricKeys: symmetricKeys,
      defaults: document.defaults,
    );
  }

  List<AtAsymmetricKey> _resolveAsymmetricKeys(List<AtKeyRecord> records) {
    final recordsByPairId = <String, Map<AtKeyKind, AtKeyRecord>>{};

    for (final record in records.where((record) => record.isAsymmetric)) {
      final pairId = record.pairId!;
      final recordsByKind =
          recordsByPairId.putIfAbsent(pairId, () => <AtKeyKind, AtKeyRecord>{});
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

  AtAsymmetricKey _resolveAsymmetricPair(
    String pairId,
    Map<AtKeyKind, AtKeyRecord> recordsByKind,
  ) {
    final publicRecord = recordsByKind[AtKeyKind.public];
    final privateRecord = recordsByKind[AtKeyKind.private];
    if (publicRecord == null || privateRecord == null) {
      throw AtKeysValidationException(
          'Asymmetric pair "$pairId" must include public and private records');
    }
    _validatePairAgreement(pairId, publicRecord, privateRecord);

    return AtAsymmetricKey(
      pairId: pairId,
      purpose: publicRecord.purpose,
      algorithm: publicRecord.algorithm,
      fingerprint: publicRecord.fingerprint,
      publicKey: publicRecord.value,
      privateKey: privateRecord.value,
      publicKeyProtection: publicRecord.protection,
      privateKeyProtection: privateRecord.protection,
      status: _mergeStringField(
        pairId,
        'status',
        publicRecord.status,
        privateRecord.status,
      ),
      createdAt: _mergeDateTimeField(
        pairId,
        'createdAt',
        publicRecord.createdAt,
        privateRecord.createdAt,
      ),
      notAfter: _mergeDateTimeField(
        pairId,
        'notAfter',
        publicRecord.notAfter,
        privateRecord.notAfter,
      ),
      operations: _mergeOperations(publicRecord, privateRecord),
    );
  }

  List<AtSymmetricKey> _resolveSymmetricKeys(List<AtKeyRecord> records) {
    return [
      for (final record in records.where(
        (record) => record.kind == AtKeyKind.symmetric,
      ))
        AtSymmetricKey(
          id: record.id,
          purpose: record.purpose,
          algorithm: record.algorithm,
          value: record.value,
          protection: record.protection,
          status: record.status,
          createdAt: record.createdAt,
          notAfter: record.notAfter,
          operations: record.operations,
        ),
    ];
  }

  void _validatePairAgreement(
    String pairId,
    AtKeyRecord publicRecord,
    AtKeyRecord privateRecord,
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

  void _validateDefaults(
    AtKeyDefaults defaults, {
    required List<AtKeyRecord> records,
    required List<AtAsymmetricKey> asymmetricKeys,
    required List<AtSymmetricKey> symmetricKeys,
  }) {
    final recordsById = {
      for (final record in records) record.id: record,
    };
    final asymmetricKeysByPairId = {
      for (final key in asymmetricKeys) key.pairId: key,
    };
    final symmetricKeysById = {
      for (final key in symmetricKeys) key.id: key,
    };

    for (final entry in defaults.values.entries) {
      final purpose = entry.key;
      final reference = entry.value;
      if (purpose.usesAsymmetricPair) {
        if (!asymmetricKeysByPairId.containsKey(reference)) {
          throw AtKeysValidationException(
              'Default ${purpose.defaultsKey} references missing pairId "$reference"');
        }
        continue;
      }

      final record = recordsById[reference];
      if (record == null) {
        throw AtKeysValidationException(
            'Default ${purpose.defaultsKey} references missing id "$reference"');
      }
      if (record.kind != AtKeyKind.symmetric ||
          !symmetricKeysById.containsKey(reference)) {
        throw AtKeysValidationException(
            'Default ${purpose.defaultsKey} must reference a symmetric key');
      }
    }
  }

  String? _mergeStringField(
    String pairId,
    String fieldName,
    String? publicValue,
    String? privateValue,
  ) {
    if (publicValue != null &&
        privateValue != null &&
        publicValue != privateValue) {
      throw AtKeysValidationException(
          'Asymmetric pair "$pairId" has mismatched $fieldName');
    }
    return publicValue ?? privateValue;
  }

  DateTime? _mergeDateTimeField(
    String pairId,
    String fieldName,
    DateTime? publicValue,
    DateTime? privateValue,
  ) {
    if (publicValue != null &&
        privateValue != null &&
        publicValue != privateValue) {
      throw AtKeysValidationException(
          'Asymmetric pair "$pairId" has mismatched $fieldName');
    }
    return publicValue ?? privateValue;
  }

  List<String> _mergeOperations(
    AtKeyRecord publicRecord,
    AtKeyRecord privateRecord,
  ) {
    return {
      ...publicRecord.operations,
      ...privateRecord.operations,
    }.toList();
  }
}
