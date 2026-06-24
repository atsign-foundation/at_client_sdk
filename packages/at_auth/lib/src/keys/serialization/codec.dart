import 'dart:convert';

import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/atkeys.dart';
import 'package:at_auth/src/keys/serialization/document.dart';
import 'package:at_commons/at_commons.dart';

abstract class AtKeysCodec {
  AtKeysDocument decodeDocument(Map<String, dynamic> json);
  Map<String, dynamic> encodeDocument(AtKeysDocument document);
}

class AtKeysJsonCodec implements AtKeysCodec {
  const AtKeysJsonCodec();

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

    return AtKeysDocument(
      version: version,
      atsign: atsign,
      enrollmentId: _optionalString(json['enrollmentId'], 'enrollmentId'),
      keys: keys,
    );
  }

  @override
  Map<String, dynamic> encodeDocument(AtKeysDocument document) {
    return {
      'version': document.version,
      'atSign': document.atsign,
      if (document.enrollmentId != null) 'enrollmentId': document.enrollmentId,
      'keys': document.keys.map(_encodeRecord).toList(),
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
      rotation: json.containsKey('rotation')
          ? _decodeRotation(
              _expectMap(json['rotation'], '$fieldPrefix.rotation'),
              '$fieldPrefix.rotation',
            )
          : null,
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
      if (record.rotation != null) 'rotation': record.rotation!.toJson(),
      if (record.operations.isNotEmpty) 'operations': record.operations,
      if (record.protection != null)
        'protection': _encodeProtection(record.protection!),
      'value': record.bytes.toString(),
    };
  }

  KeyRotation _decodeRotation(
    Map<String, dynamic> json,
    String fieldPrefix,
  ) {
    try {
      return KeyRotation.fromJson(json);
    } on ArgumentError catch (e) {
      throw AtKeysParseException('Invalid rotation at $fieldPrefix: $e');
    } on FormatException catch (e) {
      throw AtKeysParseException('Invalid rotation at $fieldPrefix: $e');
    } on StateError catch (e) {
      throw AtKeysParseException('Invalid rotation at $fieldPrefix: $e');
    }
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
