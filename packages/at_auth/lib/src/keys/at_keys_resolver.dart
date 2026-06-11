import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys_document.dart';
import 'package:at_commons/at_commons.dart';

abstract class AtKeysResolver {
  AtKeysSet resolve(AtKeysDocument document);
  AtKeysDocument resolveToDocument(AtKeysSet keys);
}

class AtKeysDocumentResolver implements AtKeysResolver {
  static const int version = 2;

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
      atSign: document.atsign.toAtsign(),
      enrollmentId: document.enrollmentId,
      asymmetricKeys: asymmetricKeys,
      symmetricKeys: symmetricKeys,
      defaults: document.defaults,
    );
  }

  List<AtAsymmetricKey> _resolveAsymmetricKeys(List<KeyRecord> records) {
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

  AtAsymmetricKey _resolveAsymmetricPair(
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

    return AtAsymmetricKey(
      pairId: pairId,
      purpose: publicRecord.purpose,
      algorithm: publicRecord.algorithm,
      fingerprint: publicRecord.fingerprint,
      publicKey: publicRecord.bytes,
      privateKey: privateRecord.bytes,
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

  @override
  AtKeysDocument resolveToDocument(AtKeysSet keys) {
    return AtKeysDocument(
      version: version,
      atsign: keys.atSign,
      enrollmentId: keys.enrollmentId,
      keys: [
        for (final key in keys.asymmetricKeys) ...[
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
            status: key.status,
            createdAt: key.createdAt,
            notAfter: key.notAfter,
            operations: key.operations,
          ),
      ],
      defaults: keys.defaults,
    );
  }

  KeyRecord _unresolveAsymmetricKey(
    AtAsymmetricKey key,
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
      status: key.status,
      createdAt: key.createdAt,
      notAfter: key.notAfter,
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
          status: record.status,
          createdAt: record.createdAt,
          notAfter: record.notAfter,
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

  void _validateDefaults(
    AtKeysDefaults defaults, {
    required List<KeyRecord> records,
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
      if (record.kind != KeyRecordKind.symmetric ||
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
    KeyRecord publicRecord,
    KeyRecord privateRecord,
  ) {
    return {
      ...publicRecord.operations,
      ...privateRecord.operations,
    }.toList();
  }
}
