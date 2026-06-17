import 'dart:convert';

import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys_document.dart';
import 'package:at_commons/at_commons.dart';

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

  @override
  AtKeysDocument decodeDocument(Map<String, dynamic> json) {
    final version = _expectInt(json['version'], 'version');
    if (version != supportedVersion) {
      throw AtKeysUnsupportedVersionException(
          'Unsupported atKeys version: $version');
    }

    final atsign = _expectNonEmptyString(json['atSign'], 'atSign');
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
      atsign: atsign,
      enrollmentId: _optionalString(json['enrollmentId'], 'enrollmentId'),
      keys: keys,
      defaults: defaults,
    );
  }

  @override
  Map<String, dynamic> encodeDocument(AtKeysDocument document) {
    return {
      'version': document.version,
      'atSign': document.atsign,
      if (document.enrollmentId != null) 'enrollmentId': document.enrollmentId,
      'keys': document.keys.map(_encodeRecord).toList(),
      'defaults': _encodeDefaults(document.defaults),
    };
  }

  KeyRecord _decodeRecord(Map<String, dynamic> json, int index) {
    final fieldPrefix = 'keys[$index]';
    final id = _expectNonEmptyString(json['id'], '$fieldPrefix.id');
    final purpose = _expectNonEmptyString(
      json['purpose'],
      '$fieldPrefix.purpose',
    );

    final kindToken = _expectNonEmptyString(json['kind'], '$fieldPrefix.kind');
    final kind = keyKindFromJsonToken(kindToken);
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

    if (kind == KeyRecordKind.symmetric) {
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

    return KeyRecord(
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
      bytes: AtBytes.fromString(value),
    );
  }

  Map<String, dynamic> _encodeRecord(KeyRecord record) {
    return {
      'id': record.id,
      if (record.pairId != null) 'pairId': record.pairId,
      'purpose': record.purpose,
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
      'value': record.bytes.toString,
    };
  }

  AtKeysDefaults _decodeDefaults(Map<String, dynamic> json) {
    final values = <KeyPurpose, String>{
      for (final entry in json.entries)
        entry.key: _expectNonEmptyString(
          entry.value,
          'defaults.${entry.key}',
        ),
    };

    return AtKeysDefaults(values: values);
  }

  Map<String, dynamic> _encodeDefaults(AtKeysDefaults defaults) {
    return {
      for (final entry in defaults.values.entries) entry.key: entry.value,
    };
  }

  KeyFingerprint _decodeFingerprint(
    Map<String, dynamic> json,
    String fieldPrefix,
  ) {
    final algorithm =
        _expectNonEmptyString(json['algorithm'], '$fieldPrefix.algorithm');
    if (!supportedFingerprintAlgorithms.contains(algorithm)) {
      throw AtKeysUnsupportedAlgorithmException(
          'Unsupported fingerprint algorithm "$algorithm" at $fieldPrefix');
    }

    return KeyFingerprint(
      algorithm: algorithm,
      value: AtBytes.fromString(
        _expectNonEmptyString(json['value'], '$fieldPrefix.value'),
      ),
    );
  }

  Map<String, dynamic> _encodeFingerprint(KeyFingerprint fingerprint) {
    return {
      'algorithm': fingerprint.algorithm,
      'value': fingerprint.value,
    };
  }

  KeyProtection _decodeProtection(
    Map<String, dynamic> json,
    String fieldPrefix,
  ) {
    final algorithm =
        _expectNonEmptyString(json['algorithm'], '$fieldPrefix.algorithm');
    if (!supportedProtectionAlgorithms.contains(algorithm)) {
      throw AtKeysUnsupportedAlgorithmException(
          'Unsupported protection algorithm "$algorithm" at $fieldPrefix');
    }

    return KeyProtection(
      keyRef: _expectNonEmptyString(json['keyRef'], '$fieldPrefix.keyRef'),
      algorithm: algorithm,
      iv: _expectNonEmptyString(json['iv'], '$fieldPrefix.iv'),
    );
  }

  Map<String, dynamic> _encodeProtection(KeyProtection protection) {
    return {
      'keyRef': protection.keyRef,
      'algorithm': protection.algorithm,
      'iv': protection.iv,
    };
  }

  void _validateDuplicateIds(List<KeyRecord> records) {
    final ids = <String>{};
    for (final record in records) {
      if (!ids.add(record.id)) {
        throw AtKeysValidationException(
            'Duplicate atKeys record id "${record.id}"');
      }
    }
  }

  void _validateProtectionReferences(List<KeyRecord> records) {
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
}
