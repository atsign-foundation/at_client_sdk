import 'dart:convert';

import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys_models.dart';

abstract class AtKeysCodec {
  AtKeysDocument decodeDocument(Map<String, dynamic> json);
  Map<String, dynamic> encodeDocument(AtKeysDocument document);
}

class AtKeysJsonCodec implements AtKeysCodec {
  static const int supportedVersion = 2;

  static const Set<String> supportedKeyMaterialAlgorithms = {
    'rsa-2048',
    'rsa-4096',
    'aes-128',
    'aes-192',
    'aes-256',
    'ecc',
    'ed25519',
  };

  static const Set<String> supportedFingerprintAlgorithms = {
    'sha-256',
  };

  static const Set<String> supportedProtectionAlgorithms = {
    'aes-128-ctr',
    'aes-192-ctr',
    'aes-256-ctr',
  };

  static const Set<String> _topLevelFields = {
    'version',
    'atSign',
    'enrollmentId',
    'keys',
    'defaults',
  };

  static const Set<String> _recordFields = {
    'id',
    'pairId',
    'purpose',
    'kind',
    'algorithm',
    'fingerprint',
    'status',
    'createdAt',
    'notAfter',
    'operations',
    'protection',
    'value',
  };

  static const Set<String> _protectionFields = {
    'type',
    'keyRef',
    'algorithm',
    'iv',
  };

  @override
  AtKeysDocument decodeDocument(Map<String, dynamic> json) {
    final version = _expectInt(json['version'], 'version');
    if (version != supportedVersion) {
      throw AtKeysUnsupportedVersionException(
          'Unsupported atKeys version: $version');
    }

    final atSign = _expectNonEmptyString(json['atSign'], 'atSign');
    final keysJson = _expectList(json['keys'], 'keys');
    final defaultsJson = _expectMap(json['defaults'], 'defaults');

    final keys = keysJson
        .asMap()
        .entries
        .map((entry) => _decodeRecord(
              _expectMap(entry.value, 'keys[${entry.key}]'),
              entry.key,
            ))
        .toList();

    _validateDuplicateIds(keys);
    _validateProtectionReferences(keys);

    final defaults = _decodeDefaults(defaultsJson);

    return AtKeysDocument(
      version: version,
      atSign: atSign,
      enrollmentId: _optionalString(json['enrollmentId'], 'enrollmentId'),
      keys: keys,
      defaults: defaults,
      metadata: _metadataFrom(json, _topLevelFields),
    );
  }

  @override
  Map<String, dynamic> encodeDocument(AtKeysDocument document) {
    return {
      'version': document.version,
      'atSign': document.atSign,
      if (document.enrollmentId != null) 'enrollmentId': document.enrollmentId,
      'keys': document.keys.map(_encodeRecord).toList(),
      'defaults': _encodeDefaults(document.defaults),
      ...document.metadata,
    };
  }

  AtKeyRecord _decodeRecord(Map<String, dynamic> json, int index) {
    final fieldPrefix = 'keys[$index]';
    final id = _expectNonEmptyString(json['id'], '$fieldPrefix.id');
    final purposeToken =
        _expectNonEmptyString(json['purpose'], '$fieldPrefix.purpose');
    final purpose = atKeyPurposeFromJsonToken(purposeToken);
    if (purpose == null) {
      throw AtKeysValidationException(
          'Unsupported atKeys purpose "$purposeToken" at $fieldPrefix');
    }

    final kindToken = _expectNonEmptyString(json['kind'], '$fieldPrefix.kind');
    final kind = atKeyKindFromJsonToken(kindToken);
    if (kind == null) {
      throw AtKeysValidationException(
          'Unsupported atKeys kind "$kindToken" at $fieldPrefix');
    }

    final algorithm =
        _expectNonEmptyString(json['algorithm'], '$fieldPrefix.algorithm');
    _validateKeyMaterialAlgorithm(algorithm, '$fieldPrefix.algorithm');

    final value = _expectNonEmptyString(json['value'], '$fieldPrefix.value');
    _validateBase64(value, '$fieldPrefix.value');

    final pairId = _optionalString(json['pairId'], '$fieldPrefix.pairId');
    final fingerprint = json.containsKey('fingerprint')
        ? _decodeFingerprint(
            _expectMap(json['fingerprint'], '$fieldPrefix.fingerprint'),
            '$fieldPrefix.fingerprint',
          )
        : null;

    if (kind == AtKeyKind.symmetric) {
      if (pairId != null) {
        throw AtKeysValidationException(
            'Symmetric key "$id" must not have pairId');
      }
      if (fingerprint != null) {
        throw AtKeysValidationException(
            'Symmetric key "$id" must not have fingerprint');
      }
    } else if (pairId == null || pairId.isEmpty) {
      throw AtKeysValidationException('Asymmetric key "$id" must have pairId');
    }

    return AtKeyRecord(
      id: id,
      pairId: pairId,
      purpose: purpose,
      kind: kind,
      algorithm: algorithm,
      fingerprint: fingerprint,
      status: _optionalString(json['status'], '$fieldPrefix.status'),
      createdAt: _optionalDateTime(json['createdAt'], '$fieldPrefix.createdAt'),
      notAfter: _optionalDateTime(json['notAfter'], '$fieldPrefix.notAfter'),
      operations:
          _optionalStringList(json['operations'], '$fieldPrefix.operations'),
      protection: json.containsKey('protection')
          ? _decodeProtection(
              _expectMap(json['protection'], '$fieldPrefix.protection'),
              '$fieldPrefix.protection',
            )
          : null,
      value: value,
      metadata: _metadataFrom(json, _recordFields),
    );
  }

  Map<String, dynamic> _encodeRecord(AtKeyRecord record) {
    return {
      'id': record.id,
      if (record.pairId != null) 'pairId': record.pairId,
      'purpose': record.purpose.jsonToken,
      'kind': record.kind.jsonToken,
      'algorithm': record.algorithm,
      if (record.fingerprint != null)
        'fingerprint': _encodeFingerprint(record.fingerprint!),
      if (record.status != null) 'status': record.status,
      if (record.createdAt != null)
        'createdAt': record.createdAt!.toUtc().toIso8601String(),
      if (record.notAfter != null)
        'notAfter': record.notAfter!.toUtc().toIso8601String(),
      if (record.operations.isNotEmpty) 'operations': record.operations,
      if (record.protection != null)
        'protection': _encodeProtection(record.protection!),
      'value': record.value,
      ...record.metadata,
    };
  }

  AtKeyDefaults _decodeDefaults(Map<String, dynamic> json) {
    final values = <AtKeyPurpose, String>{};
    final metadata = <String, dynamic>{};

    for (final entry in json.entries) {
      final purpose = atKeyPurposeFromDefaultsKey(entry.key);
      if (purpose == null) {
        metadata[entry.key] = entry.value;
        continue;
      }
      values[purpose] =
          _expectNonEmptyString(entry.value, 'defaults.${entry.key}');
    }

    return AtKeyDefaults(values: values, metadata: metadata);
  }

  Map<String, dynamic> _encodeDefaults(AtKeyDefaults defaults) {
    return {
      for (final entry in defaults.values.entries)
        entry.key.defaultsKey: entry.value,
      ...defaults.metadata,
    };
  }

  AtKeyFingerprint _decodeFingerprint(
    Map<String, dynamic> json,
    String fieldPrefix,
  ) {
    final algorithm =
        _expectNonEmptyString(json['algorithm'], '$fieldPrefix.algorithm');
    if (!supportedFingerprintAlgorithms.contains(algorithm)) {
      throw AtKeysUnsupportedAlgorithmException(
          'Unsupported fingerprint algorithm "$algorithm" at $fieldPrefix');
    }

    return AtKeyFingerprint(
      algorithm: algorithm,
      value: _expectNonEmptyString(json['value'], '$fieldPrefix.value'),
    );
  }

  Map<String, dynamic> _encodeFingerprint(AtKeyFingerprint fingerprint) {
    return {
      'algorithm': fingerprint.algorithm,
      'value': fingerprint.value,
    };
  }

  AtKeyProtection _decodeProtection(
    Map<String, dynamic> json,
    String fieldPrefix,
  ) {
    final algorithm =
        _expectNonEmptyString(json['algorithm'], '$fieldPrefix.algorithm');
    if (!supportedProtectionAlgorithms.contains(algorithm)) {
      throw AtKeysUnsupportedAlgorithmException(
          'Unsupported protection algorithm "$algorithm" at $fieldPrefix');
    }

    return AtKeyProtection(
      type: _expectNonEmptyString(json['type'], '$fieldPrefix.type'),
      keyRef: _expectNonEmptyString(json['keyRef'], '$fieldPrefix.keyRef'),
      algorithm: algorithm,
      iv: _expectNonEmptyString(json['iv'], '$fieldPrefix.iv'),
      metadata: _metadataFrom(json, _protectionFields),
    );
  }

  Map<String, dynamic> _encodeProtection(AtKeyProtection protection) {
    return {
      'type': protection.type,
      'keyRef': protection.keyRef,
      'algorithm': protection.algorithm,
      'iv': protection.iv,
      ...protection.metadata,
    };
  }

  void _validateDuplicateIds(List<AtKeyRecord> records) {
    final ids = <String>{};
    for (final record in records) {
      if (!ids.add(record.id)) {
        throw AtKeysValidationException(
            'Duplicate atKeys record id "${record.id}"');
      }
    }
  }

  void _validateProtectionReferences(List<AtKeyRecord> records) {
    final ids = records.map((record) => record.id).toSet();
    for (final record in records) {
      final protection = record.protection;
      if (protection != null && !ids.contains(protection.keyRef)) {
        throw AtKeysProtectionException(
            'Protection keyRef "${protection.keyRef}" for "${record.id}" does not exist');
      }
    }
  }

  void _validateKeyMaterialAlgorithm(String algorithm, String fieldName) {
    if (!supportedKeyMaterialAlgorithms.contains(algorithm)) {
      throw AtKeysUnsupportedAlgorithmException(
          'Unsupported key material algorithm "$algorithm" at $fieldName');
    }
  }

  int _expectInt(Object? value, String fieldName) {
    if (value is int) {
      return value;
    }
    throw AtKeysParseException('Expected integer at $fieldName');
  }

  Map<String, dynamic> _expectMap(Object? value, String fieldName) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    throw AtKeysParseException('Expected object at $fieldName');
  }

  List<dynamic> _expectList(Object? value, String fieldName) {
    if (value is List) {
      return value;
    }
    throw AtKeysParseException('Expected array at $fieldName');
  }

  String _expectNonEmptyString(Object? value, String fieldName) {
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw AtKeysParseException('Expected non-empty string at $fieldName');
  }

  String? _optionalString(Object? value, String fieldName) {
    if (value == null) {
      return null;
    }
    if (value is String) {
      return value;
    }
    throw AtKeysParseException('Expected string at $fieldName');
  }

  DateTime? _optionalDateTime(Object? value, String fieldName) {
    final text = _optionalString(value, fieldName);
    if (text == null) {
      return null;
    }
    final dateTime = DateTime.tryParse(text);
    if (dateTime == null) {
      throw AtKeysParseException('Expected ISO-8601 timestamp at $fieldName');
    }
    return dateTime;
  }

  List<String> _optionalStringList(Object? value, String fieldName) {
    if (value == null) {
      return const [];
    }
    if (value is! List) {
      throw AtKeysParseException('Expected array at $fieldName');
    }
    return value
        .asMap()
        .entries
        .map((entry) =>
            _expectNonEmptyString(entry.value, '$fieldName[${entry.key}]'))
        .toList();
  }

  void _validateBase64(String value, String fieldName) {
    try {
      base64Decode(value);
    } on FormatException catch (e) {
      throw AtKeysValidationException('Malformed base64 at $fieldName: $e');
    }
  }

  Map<String, dynamic> _metadataFrom(
    Map<String, dynamic> json,
    Set<String> knownFields,
  ) {
    return {
      for (final entry in json.entries)
        if (!knownFields.contains(entry.key)) entry.key: entry.value,
    };
  }
}
